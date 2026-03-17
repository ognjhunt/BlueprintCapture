package app.blueprint.capture.data.capture

import android.content.SharedPreferences
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.edit
import androidx.work.ForegroundInfo
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.model.UploadQueueStatus
import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import com.google.firebase.storage.StorageReference
import java.io.File
import java.util.Date
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

enum class CaptureUploadWorkOutcome {
    Success,
    Retry,
    Failure,
}

@Singleton
class CaptureUploadRepository @Inject constructor(
    private val sharedPreferences: SharedPreferences,
    private val storage: FirebaseStorage,
    private val firestore: FirebaseFirestore,
    private val workManager: WorkManager,
) {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }
    private val queueLock = Any()
    private val _queue = MutableStateFlow(loadQueue().recoverQueueState())

    val queue: StateFlow<List<UploadQueueItem>> = _queue.asStateFlow()

    init {
        persistQueue(_queue.value)
        scheduleRecoveredUploads(_queue.value)
    }

    fun enqueueBundleUpload(
        label: String,
        bundleRoot: File,
        request: AndroidCaptureBundleRequest,
        startImmediately: Boolean = true,
    ): String {
        val uploadId = request.captureId
        val remotePrefix = buildRemotePrefix(
            creatorId = request.creatorId,
            captureId = request.captureId,
        )
        val item = UploadQueueItem(
            id = uploadId,
            sceneId = request.sceneId,
            captureId = request.captureId,
            label = label,
            progress = 0f,
            status = if (startImmediately) UploadQueueStatus.Queued else UploadQueueStatus.Saved,
            detail = if (startImmediately) "Queued for upload" else "Saved on this device. Upload when ready.",
            localBundlePath = bundleRoot.absolutePath,
            remotePrefix = remotePrefix,
            creatorId = request.creatorId,
            captureJobId = request.jobId,
            siteSubmissionId = request.siteSubmissionId,
            captureStartEpochMs = request.captureStartEpochMs,
            captureDurationMs = request.captureDurationMs,
            quotedPayoutCents = request.quotedPayoutCents,
            requestedOutputs = request.requestedOutputs,
        )
        synchronized(queueLock) {
            val trimmed = _queue.value.filterNot { it.id == uploadId }.take(11)
            val updated = listOf(item) + trimmed
            _queue.value = updated
            persistQueue(updated)
        }
        if (startImmediately) {
            enqueueWork(uploadId, replaceExisting = true)
        }
        return uploadId
    }

    fun saveBundleForLater(
        label: String,
        bundleRoot: File,
        request: AndroidCaptureBundleRequest,
    ): String = enqueueBundleUpload(
        label = label,
        bundleRoot = bundleRoot,
        request = request,
        startImmediately = false,
    )

    fun startUpload(id: String) {
        val item = _queue.value.firstOrNull { it.id == id } ?: return
        if (item.localBundlePath.isNullOrBlank()) {
            markFailed(id, "Local capture bundle is missing.")
            return
        }

        updateItem(id) {
            it.copy(
                progress = if (it.uploadCompletedAtEpochMs != null) {
                    it.progress.coerceAtLeast(0.99f)
                } else {
                    0f
                },
                status = UploadQueueStatus.Queued,
                detail = if (it.uploadCompletedAtEpochMs != null) {
                    "Retrying capture submission"
                } else {
                    "Queued for upload"
                },
                lastAttemptEpochMs = null,
                cancelRequestedAtEpochMs = null,
            )
        }
        enqueueWork(id, replaceExisting = true)
    }

    fun retryUpload(id: String) {
        startUpload(id)
    }

    fun cancelUpload(id: String) {
        workManager.cancelUniqueWork(uniqueWorkName(id))
        updateItem(id) {
            it.copy(
                status = UploadQueueStatus.Failed,
                detail = "Upload cancelled.",
                cancelRequestedAtEpochMs = System.currentTimeMillis(),
                progress = if (it.uploadCompletedAtEpochMs != null) {
                    it.progress.coerceAtLeast(0.99f)
                } else {
                    it.progress
                },
            )
        }
    }

    fun dismissUpload(id: String) {
        workManager.cancelUniqueWork(uniqueWorkName(id))
        synchronized(queueLock) {
            val updated = _queue.value.filterNot { it.id == id }
            if (updated.size == _queue.value.size) return
            _queue.value = updated
            persistQueue(updated)
        }
    }

    fun getForegroundInfo(id: String): ForegroundInfo? {
        val item = _queue.value.firstOrNull { it.id == id } ?: return null
        return CaptureUploadNotifications.buildForegroundInfo(item)
    }

    suspend fun runWorkerAttempt(
        id: String,
        runAttemptCount: Int,
        onItemUpdated: suspend (UploadQueueItem) -> Unit = {},
    ): CaptureUploadWorkOutcome {
        val initialItem = _queue.value.firstOrNull { it.id == id } ?: return CaptureUploadWorkOutcome.Failure

        return try {
            if (initialItem.cancelRequestedAtEpochMs != null) {
                return CaptureUploadWorkOutcome.Failure
            }

            updateItemAndEmit(id, onItemUpdated) { item ->
                item.copy(lastAttemptEpochMs = System.currentTimeMillis())
            }

            val latestItem = _queue.value.firstOrNull { it.id == id } ?: initialItem
            throwIfCancellationRequested(latestItem)
            if (latestItem.uploadCompletedAtEpochMs == null) {
                uploadBundleFiles(latestItem, onItemUpdated)
            } else {
                updateItemAndEmit(id, onItemUpdated) { item ->
                    item.copy(
                        status = UploadQueueStatus.Registering,
                        progress = item.progress.coerceAtLeast(0.99f),
                        detail = "Registering capture submission",
                    )
                }
            }

            val submissionItem = _queue.value.firstOrNull { it.id == id } ?: initialItem
            throwIfCancellationRequested(submissionItem)
            if (submissionItem.submittedAtEpochMs == null) {
                registerSubmission(submissionItem)
            } else {
                markCompleted(
                    id = id,
                    submittedAtEpochMs = submissionItem.submittedAtEpochMs,
                    submissionDocumentPath = submissionItem.submissionDocumentPath,
                )
            }

            CaptureUploadWorkOutcome.Success
        } catch (error: PermanentUploadException) {
            markFailed(id, error.message ?: "Upload failed.")
            CaptureUploadWorkOutcome.Failure
        } catch (_: CancellationException) {
            if (_queue.value.firstOrNull { it.id == id }?.cancelRequestedAtEpochMs != null) {
                CaptureUploadWorkOutcome.Failure
            } else {
                queueAutomaticRetry(id, runAttemptCount, "Upload interrupted.")
            }
        } catch (error: Exception) {
            queueAutomaticRetry(id, runAttemptCount, error.message ?: "Upload failed.")
        }
    }

    private suspend fun uploadBundleFiles(
        item: UploadQueueItem,
        onItemUpdated: suspend (UploadQueueItem) -> Unit,
    ) {
        val bundlePath = item.localBundlePath ?: throw PermanentUploadException("Local capture bundle is missing.")
        val bundleRoot = File(bundlePath)
        if (!bundleRoot.exists()) {
            throw PermanentUploadException("Local capture bundle is missing.")
        }

        val files = bundleRoot.walkTopDown()
            .filter(File::isFile)
            .sortedBy { file -> file.absolutePath }
            .toList()

        if (files.isEmpty()) {
            throw PermanentUploadException("Capture bundle has no files to upload.")
        }

        val totalBytes = files.sumOf { it.length().coerceAtLeast(1L) }.coerceAtLeast(1L)
        val remotePrefix = item.remotePrefix ?: buildRemotePrefix(
            creatorId = item.creatorId ?: "anonymous",
            captureId = item.captureId.ifBlank { item.id },
        )

        updateItemAndEmit(item.id, onItemUpdated) {
            it.copy(
                status = UploadQueueStatus.Preparing,
                detail = "Preparing ${files.size} files",
                remotePrefix = remotePrefix,
                progress = 0.02f,
            )
        }

        var uploadedBytes = 0L
        files.forEach { file ->
            throwIfCancellationRequested(item.id)
            val relativePath = file.relativeTo(bundleRoot).invariantSeparatorsPath
            updateItemAndEmit(item.id, onItemUpdated) {
                it.copy(
                    status = UploadQueueStatus.Uploading,
                    detail = "Uploading $relativePath",
                    remotePrefix = remotePrefix,
                )
            }

            val storageRef = storage.reference.child(remotePrefix + relativePath)
            uploadFile(storageRef, file) { fileBytes ->
                val totalProgress = ((uploadedBytes + fileBytes).toDouble() / totalBytes.toDouble())
                    .toFloat()
                    .coerceIn(0f, 0.985f)
                updateItemAndEmitBlocking(item.id, onItemUpdated) {
                    it.copy(
                        status = UploadQueueStatus.Uploading,
                        progress = totalProgress,
                        detail = "Uploading ${file.name}",
                        remotePrefix = remotePrefix,
                    )
                }
            }
            uploadedBytes += file.length().coerceAtLeast(1L)
        }

        updateItemAndEmit(item.id, onItemUpdated) {
            it.copy(
                status = UploadQueueStatus.Registering,
                progress = 0.995f,
                detail = "Registering capture submission",
                remotePrefix = remotePrefix,
                uploadCompletedAtEpochMs = System.currentTimeMillis(),
            )
        }
    }

    private suspend fun registerSubmission(item: UploadQueueItem) {
        val captureId = item.captureId.ifBlank { item.id }
        val sceneId = item.sceneId.ifBlank { captureId }
        val submittedAtEpochMs = item.uploadCompletedAtEpochMs ?: System.currentTimeMillis()
        val submissionDocumentPath = "capture_submissions/$captureId"
        val payload = linkedMapOf<String, Any>(
            "capture_id" to captureId,
            "scene_id" to sceneId,
            "creator_id" to (item.creatorId ?: "anonymous"),
            "status" to "submitted",
            "capture_source" to "android_phone",
            "submitted_at" to Timestamp(Date(submittedAtEpochMs)),
            "created_at" to Timestamp(Date()),
            "capture_start_epoch_ms" to item.captureStartEpochMs,
        )

        item.captureJobId?.takeIf(String::isNotBlank)?.let { payload["job_id"] = it }
        item.siteSubmissionId?.takeIf(String::isNotBlank)?.let { payload["site_submission_id"] = it }
        item.quotedPayoutCents?.let { payload["payout_cents"] = it }
        item.captureDurationMs?.let { payload["capture_duration_ms"] = it }
        if (item.requestedOutputs.isNotEmpty()) {
            payload["requested_outputs"] = item.requestedOutputs
        }
        item.remotePrefix?.takeIf(String::isNotBlank)?.let { payload["raw_prefix"] = "${it}raw/" }

        firestore.collection("capture_submissions")
            .document(captureId)
            .set(payload, SetOptions.merge())
            .awaitResult()

        markCompleted(
            id = item.id,
            submittedAtEpochMs = System.currentTimeMillis(),
            submissionDocumentPath = submissionDocumentPath,
        )
    }

    private suspend fun uploadFile(
        storageReference: StorageReference,
        file: File,
        onProgress: (Long) -> Unit,
    ) {
        suspendCancellableCoroutine<Unit> { continuation ->
            val uploadTask = storageReference.putFile(
                Uri.fromFile(file),
                StorageMetadata.Builder()
                    .setContentType(contentTypeFor(file))
                    .build(),
            )

            uploadTask.addOnProgressListener { snapshot ->
                onProgress(snapshot.bytesTransferred)
            }
            uploadTask.addOnSuccessListener {
                if (continuation.isActive) {
                    continuation.resume(Unit)
                }
            }
            uploadTask.addOnFailureListener { error ->
                if (continuation.isActive) {
                    continuation.resumeWithException(error)
                }
            }
            uploadTask.addOnCanceledListener {
                if (continuation.isActive) {
                    continuation.cancel(CancellationException("Upload cancelled"))
                }
            }

            continuation.invokeOnCancellation {
                uploadTask.cancel()
            }
        }
    }

    private fun enqueueWork(
        id: String,
        replaceExisting: Boolean,
    ) {
        val request = OneTimeWorkRequestBuilder<CaptureUploadWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                15,
                TimeUnit.SECONDS,
            )
            .setInputData(
                workDataOf(CaptureUploadWorker.KEY_UPLOAD_ID to id),
            )
            .addTag(WORK_TAG)
            .addTag("$WORK_TAG:$id")
            .build()

        workManager.enqueueUniqueWork(
            uniqueWorkName(id),
            if (replaceExisting) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }

    private fun scheduleRecoveredUploads(items: List<UploadQueueItem>) {
        items.filter { item ->
            item.status != UploadQueueStatus.Saved &&
            item.status != UploadQueueStatus.Completed &&
                item.status != UploadQueueStatus.Failed
        }.forEach { item ->
            enqueueWork(item.id, replaceExisting = false)
        }
    }

    private fun queueAutomaticRetry(
        id: String,
        runAttemptCount: Int,
        reason: String,
    ): CaptureUploadWorkOutcome {
        val item = _queue.value.firstOrNull { it.id == id } ?: return CaptureUploadWorkOutcome.Failure
        return if (runAttemptCount < MAX_AUTO_RETRIES) {
            updateItem(id) {
                it.copy(
                    status = UploadQueueStatus.Queued,
                    detail = if (item.uploadCompletedAtEpochMs != null) {
                        "Submission paused. Retrying automatically."
                    } else {
                        "Upload paused. Retrying automatically."
                    },
                    progress = if (item.uploadCompletedAtEpochMs != null) {
                        it.progress.coerceAtLeast(0.99f)
                    } else {
                        it.progress.coerceAtMost(0.95f)
                    },
                )
            }
            CaptureUploadWorkOutcome.Retry
        } else {
            markFailed(id, reason)
            CaptureUploadWorkOutcome.Failure
        }
    }

    private fun markCompleted(
        id: String,
        submittedAtEpochMs: Long?,
        submissionDocumentPath: String?,
    ) {
        updateItem(id) {
            it.copy(
                status = UploadQueueStatus.Completed,
                progress = 1f,
                detail = "Submitted for review",
                submittedAtEpochMs = submittedAtEpochMs ?: it.submittedAtEpochMs ?: System.currentTimeMillis(),
                submissionDocumentPath = submissionDocumentPath ?: it.submissionDocumentPath,
            )
        }
    }

    private fun markFailed(id: String, reason: String) {
        updateItem(id) {
            it.copy(
                status = UploadQueueStatus.Failed,
                detail = reason,
                progress = if (it.uploadCompletedAtEpochMs != null) {
                    it.progress.coerceAtLeast(0.99f)
                } else {
                    it.progress
                },
            )
        }
    }

    private fun updateItem(
        id: String,
        transform: (UploadQueueItem) -> UploadQueueItem,
    ): UploadQueueItem? {
        synchronized(queueLock) {
            var updatedItem: UploadQueueItem? = null
            val updated = _queue.value.map { item ->
                if (item.id == id) {
                    transform(item).also { updatedItem = it }
                } else {
                    item
                }
            }
            if (updatedItem == null) {
                return null
            }
            _queue.value = updated
            persistQueue(updated)
            return updatedItem
        }
    }

    private suspend fun updateItemAndEmit(
        id: String,
        onItemUpdated: suspend (UploadQueueItem) -> Unit,
        transform: (UploadQueueItem) -> UploadQueueItem,
    ) {
        val updatedItem = updateItem(id, transform) ?: return
        onItemUpdated(updatedItem)
    }

    private fun updateItemAndEmitBlocking(
        id: String,
        onItemUpdated: suspend (UploadQueueItem) -> Unit,
        transform: (UploadQueueItem) -> UploadQueueItem,
    ) {
        updateItem(id, transform)?.let { item ->
            kotlinx.coroutines.runBlocking {
                onItemUpdated(item)
            }
        }
    }

    private fun throwIfCancellationRequested(item: UploadQueueItem) {
        if (item.cancelRequestedAtEpochMs != null) {
            throw CancellationException("Upload cancelled")
        }
    }

    private fun throwIfCancellationRequested(id: String) {
        val item = _queue.value.firstOrNull { it.id == id } ?: return
        throwIfCancellationRequested(item)
    }

    private fun loadQueue(): List<UploadQueueItem> {
        val raw = sharedPreferences.getString(QUEUE_KEY, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString<List<UploadQueueItem>>(raw)
        }.getOrDefault(emptyList())
    }

    private fun persistQueue(items: List<UploadQueueItem>) {
        sharedPreferences.edit {
            putString(QUEUE_KEY, json.encodeToString(items))
        }
    }

    private fun List<UploadQueueItem>.recoverQueueState(): List<UploadQueueItem> = map { item ->
        val derived = item.withDerivedIdentifiers()
        if (
            derived.status == UploadQueueStatus.Queued ||
            derived.status == UploadQueueStatus.Preparing ||
            derived.status == UploadQueueStatus.Uploading ||
            derived.status == UploadQueueStatus.Registering
        ) {
            derived.copy(
                status = UploadQueueStatus.Queued,
                detail = if (derived.uploadCompletedAtEpochMs != null) {
                    "Resuming capture submission"
                } else {
                    "Resuming upload"
                },
                progress = if (derived.uploadCompletedAtEpochMs != null) {
                    derived.progress.coerceAtLeast(0.99f)
                } else {
                    derived.progress.coerceAtMost(0.95f)
                },
            )
        } else {
            derived
        }
    }

    private fun UploadQueueItem.withDerivedIdentifiers(): UploadQueueItem {
        val derivedSceneId = sceneId.ifBlank {
            localBundlePath
                ?.split(File.separatorChar)
                ?.windowed(size = 2, step = 1, partialWindows = false)
                ?.firstOrNull { window -> window.firstOrNull() == "scenes" }
                ?.getOrNull(1)
                ?: captureJobId
                ?: id
        }
        val derivedCaptureId = captureId.ifBlank { id }
        return copy(
            sceneId = derivedSceneId,
            captureId = derivedCaptureId,
            remotePrefix = remotePrefix ?: buildRemotePrefix(
                creatorId = creatorId ?: "anonymous",
                captureId = derivedCaptureId,
            ),
        )
    }

    private fun buildRemotePrefix(
        creatorId: String,
        captureId: String,
    ): String {
        val creatorSegment = sanitizePathSegment(creatorId)
        val captureSegment = sanitizePathSegment(captureId)
        return "captures/$creatorSegment/$captureSegment/"
    }

    private fun contentTypeFor(file: File): String {
        val extension = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: when (extension) {
                "json" -> "application/json"
                "mp4" -> "video/mp4"
                else -> "application/octet-stream"
            }
    }

    private fun sanitizePathSegment(value: String): String {
        return value.lowercase()
            .replace(SEGMENT_SANITIZE_REGEX, "-")
            .trim('-')
            .ifBlank { "capture" }
    }

    private fun uniqueWorkName(id: String): String = "$WORK_TAG-$id"

    private class PermanentUploadException(
        override val message: String,
    ) : IllegalStateException(message)

    private companion object {
        const val QUEUE_KEY = "capture_upload_queue"
        const val WORK_TAG = "capture_upload"
        const val MAX_AUTO_RETRIES = 5
        val SEGMENT_SANITIZE_REGEX = "[^a-z0-9._-]+".toRegex()
    }
}
