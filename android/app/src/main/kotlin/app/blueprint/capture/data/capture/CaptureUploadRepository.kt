package app.blueprint.capture.data.capture

import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
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
import app.blueprint.capture.data.ops.OperationalTelemetry
import app.blueprint.capture.data.session.SessionPreferences
import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.FirebaseException
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import com.google.firebase.storage.StorageReference
import com.google.firebase.storage.StorageException
import java.io.File
import java.util.Date
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
    private val auth: FirebaseAuth,
    private val workManager: WorkManager,
    private val sessionPreferences: SessionPreferences,
    private val operationalTelemetry: OperationalTelemetry,
) {
    private val repositoryScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }
    private val queueLock = Any()
    private val autoClearJobs = mutableMapOf<String, Job>()
    private val _queue = MutableStateFlow(loadQueue().recoverQueueState())

    val queue: StateFlow<List<UploadQueueItem>> = _queue.asStateFlow()

    init {
        auth.addAuthStateListener { firebaseAuth ->
            if (firebaseAuth.currentUser != null) {
                retryDeferredSubmissionRegistrations()
            }
        }
        persistQueue(_queue.value)
        scheduleRecoveredUploads(_queue.value)
        repositoryScope.launch {
            sessionPreferences.uploadAutoClear.collect { enabled ->
                syncAutoClearPreference(enabled)
            }
        }
    }

    fun enqueueBundleUpload(
        label: String,
        bundleRoot: File,
        request: AndroidCaptureBundleRequest,
        startImmediately: Boolean = true,
    ): String {
        val uploadId = request.captureId
        val existingItem = _queue.value.firstOrNull { it.id == uploadId }
        if (existingItem != null && existingItem.status.isActive) {
            return uploadId
        }
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
            captureSource = when (request.captureSource) {
                AndroidCaptureSource.AndroidPhone -> "android"
                AndroidCaptureSource.AndroidXrGlasses,
                AndroidCaptureSource.MetaGlasses,
                -> "glasses"
            },
            motionSampleCount = request.motionSampleCount,
            priorityWeight = request.priorityWeight,
            reservationId = request.reservationId,
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
        if (item.status.isActive) {
            return
        }
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
        cancelPendingAutoClear(id)
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
                val didRegisterSubmission = registerSubmission(submissionItem)
                if (!didRegisterSubmission) {
                    return CaptureUploadWorkOutcome.Success
                }
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
            val permanentMessage = permanentFailureMessage(error)
            if (permanentMessage != null) {
                markFailed(id, permanentMessage)
                CaptureUploadWorkOutcome.Failure
            } else {
                queueAutomaticRetry(id, runAttemptCount, error.message ?: "Upload failed.")
            }
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
            .toMutableList()

        if (files.isEmpty()) {
            throw PermanentUploadException("Capture bundle has no files to upload.")
        }

        val completionMarkerIndex = files.indexOfFirst { it.name == "capture_upload_complete.json" }
        val completionMarker = if (completionMarkerIndex >= 0) files.removeAt(completionMarkerIndex) else null

        val totalBytes = files.sumOf { it.length().coerceAtLeast(1L) }.coerceAtLeast(1L)
        val remotePrefix = item.remotePrefix ?: buildRemotePrefix(
            creatorId = item.creatorId ?: "anonymous",
            captureId = item.captureId.ifBlank { item.id },
        )

        updateItemAndEmit(item.id, onItemUpdated) {
            it.copy(
                status = UploadQueueStatus.Preparing,
                detail = "Preparing ${files.size + if (completionMarker != null) 1 else 0} files",
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

        completionMarker?.let { file ->
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
            uploadCompletionMarker(storageRef, file)
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

    private suspend fun registerSubmission(item: UploadQueueItem): Boolean {
        val authenticatedCreatorId = auth.currentUser?.uid
        if (authenticatedCreatorId.isNullOrBlank()) {
            updateItem(item.id) {
                it.copy(
                    status = UploadQueueStatus.Registering,
                    progress = it.progress.coerceAtLeast(0.99f),
                    detail = "Waiting for Firebase auth before registering capture submission",
                )
            }
            Log.i(
                "CaptureUploadRepository",
                "Deferring capture_submissions/${item.captureId.ifBlank { item.id }} write until Firebase auth is available",
            )
            operationalTelemetry.recordFailure(
                operation = "submission_registration",
                detail = "waiting_for_firebase_auth",
            )
            return false
        }

        val captureId = item.captureId.ifBlank { item.id }
        val sceneId = item.sceneId.ifBlank { captureId }
        val submittedAtEpochMs = item.uploadCompletedAtEpochMs ?: System.currentTimeMillis()
        val submissionDocumentPath = "capture_submissions/$captureId"
        val payload = linkedMapOf<String, Any>(
            "capture_id" to captureId,
            "scene_id" to sceneId,
            "creator_id" to authenticatedCreatorId,
            "capture_source" to item.captureSource,
            "submitted_at" to Timestamp(Date(submittedAtEpochMs)),
            "created_at" to Timestamp(Date()),
            "capture_start_epoch_ms" to item.captureStartEpochMs,
            "status" to "submitted",
            "operational_state" to linkedMapOf(
                "assignment_state" to if (item.captureJobId.isNullOrBlank()) "unassigned_or_open_capture" else "assigned_capture_job",
                "upload_state" to "uploaded",
                "qa_state" to "queued",
                "repeat_ready" to false,
            ),
            "lifecycle" to linkedMapOf(
                "capture_uploaded_at" to Timestamp(Date(submittedAtEpochMs)),
            ),
        )

        item.captureJobId?.takeIf(String::isNotBlank)?.let { payload["job_id"] = it }
        item.captureJobId?.takeIf(String::isNotBlank)?.let { payload["capture_job_id"] = it }
        item.siteSubmissionId?.takeIf(String::isNotBlank)?.let { payload["site_submission_id"] = it }
        item.quotedPayoutCents?.let { payload["estimated_payout_cents"] = it }
        item.captureDurationMs?.let { payload["capture_duration_ms"] = it }
        if (item.requestedOutputs.isNotEmpty()) {
            payload["requested_outputs"] = item.requestedOutputs
        }
        item.remotePrefix?.takeIf(String::isNotBlank)?.let { payload["raw_prefix"] = "${it}raw/" }

        // Sensor / ranking metadata enrichment
        if (item.motionSampleCount > 0) {
            payload["motion_sample_count"] = item.motionSampleCount
            payload["motion_provenance"] = "phone_imu_accelerometer_gyroscope"
        }
        if (item.priorityWeight > 0) payload["priority_weight"] = item.priorityWeight
        item.reservationId?.takeIf(String::isNotBlank)?.let { payload["reservation_id"] = it }

        // Attempt to read site_identity and capture_topology from bundle for submission doc
        val bundlePath = item.localBundlePath
        if (!bundlePath.isNullOrBlank()) {
            val rawDir = File(bundlePath).resolve("raw")
            runCatching {
                val siteFile = rawDir.resolve("site_identity.json")
                if (siteFile.exists()) payload["has_site_identity"] = true
            }
            runCatching {
                val topoFile = rawDir.resolve("capture_topology.json")
                if (topoFile.exists()) payload["has_capture_topology"] = true
            }
            runCatching {
                val imuFile = rawDir.resolve("imu_samples.jsonl")
                if (imuFile.exists() && imuFile.length() > 0) {
                    payload["imu_samples_available"] = true
                }
            }
        }

        firestore.collection("capture_submissions")
            .document(captureId)
            .set(payload, SetOptions.merge())
            .awaitResult()

        operationalTelemetry.recordSuccess(
            operation = "submission_registration",
            detail = captureId,
        )
        updateItem(item.id) {
            it.copy(creatorId = authenticatedCreatorId)
        }
        markCompleted(
            id = item.id,
            submittedAtEpochMs = System.currentTimeMillis(),
            submissionDocumentPath = submissionDocumentPath,
        )
        return true
    }

    private suspend fun uploadCompletionMarker(
        storageReference: StorageReference,
        file: File,
    ) {
        suspendCancellableCoroutine<Unit> { continuation ->
            val uploadTask = storageReference.putBytes(
                file.readBytes(),
                StorageMetadata.Builder()
                    .setContentType("application/json")
                    .build(),
            )

            uploadTask.addOnSuccessListener {
                if (continuation.isActive) {
                    continuation.resume(Unit)
                }
            }
            uploadTask.addOnFailureListener { error ->
                if (!continuation.isActive) {
                    return@addOnFailureListener
                }
                if (CaptureUploadErrorClassifier.isAlreadyFinalized(error)) {
                    storageReference.metadata
                        .addOnSuccessListener {
                            if (continuation.isActive) {
                                continuation.resume(Unit)
                            }
                        }
                        .addOnFailureListener {
                            if (continuation.isActive) {
                                continuation.resumeWithException(error)
                            }
                        }
                } else {
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
                if (!continuation.isActive) {
                    return@addOnFailureListener
                }
                if (CaptureUploadErrorClassifier.isAlreadyFinalized(error)) {
                    storageReference.metadata
                        .addOnSuccessListener {
                            if (continuation.isActive) {
                                continuation.resume(Unit)
                            }
                        }
                        .addOnFailureListener {
                            if (continuation.isActive) {
                                continuation.resumeWithException(error)
                            }
                        }
                } else if (continuation.isActive) {
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
            operationalTelemetry.recordFailure(
                operation = "capture_upload_retry",
                detail = reason,
            )
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
        operationalTelemetry.recordSuccess(
            operation = "capture_upload",
            detail = submissionDocumentPath ?: id,
        )
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
        operationalTelemetry.recordFailure(
            operation = "capture_upload",
            detail = reason,
        )
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
            if (updatedItem?.status == UploadQueueStatus.Completed) {
                scheduleAutoClearIfNeeded(id)
            } else {
                cancelPendingAutoClear(id)
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

    private fun syncAutoClearPreference(enabled: Boolean) {
        if (!enabled) {
            synchronized(queueLock) {
                autoClearJobs.keys.toList().forEach(::cancelPendingAutoClear)
            }
            return
        }

        _queue.value
            .filter { it.status == UploadQueueStatus.Completed }
            .forEach { item -> scheduleAutoClearIfNeeded(item.id) }
    }

    private fun scheduleAutoClearIfNeeded(id: String) {
        if (!sessionPreferences.uploadAutoClear.value) return
        cancelPendingAutoClear(id)
        autoClearJobs[id] = repositoryScope.launch {
            delay(AUTO_CLEAR_DELAY_MS)
            val item = _queue.value.firstOrNull { it.id == id }
            if (sessionPreferences.uploadAutoClear.value && item?.status == UploadQueueStatus.Completed) {
                dismissUpload(id)
            }
        }
    }

    private fun cancelPendingAutoClear(id: String) {
        autoClearJobs.remove(id)?.cancel()
    }

    private fun retryDeferredSubmissionRegistrations() {
        val currentUserId = auth.currentUser?.uid ?: return
        val deferredIds = _queue.value
            .filter { item ->
                item.uploadCompletedAtEpochMs != null &&
                    item.submittedAtEpochMs == null &&
                    item.cancelRequestedAtEpochMs == null
            }
            .map { it.id }

        if (deferredIds.isEmpty()) {
            return
        }

        Log.i(
            "CaptureUploadRepository",
            "Retrying ${deferredIds.size} deferred capture_submissions write(s) after Firebase auth became available for $currentUserId",
        )
        operationalTelemetry.recordSuccess(
            operation = "submission_registration_retry",
            detail = deferredIds.size.toString(),
        )

        deferredIds.forEach { id ->
            updateItem(id) {
                it.copy(
                    creatorId = currentUserId,
                    status = UploadQueueStatus.Queued,
                    progress = it.progress.coerceAtLeast(0.99f),
                    detail = "Retrying capture submission after Firebase auth became available",
                )
            }
            enqueueWork(id, replaceExisting = true)
        }
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

    private fun permanentFailureMessage(error: Exception): String? {
        return when (error) {
            is FirebaseFirestoreException -> {
                if (error.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) {
                    "Upload reached submission registration, but this account does not have permission to create capture submissions."
                } else {
                    null
                }
            }

            is StorageException -> {
                when (error.errorCode) {
                    StorageException.ERROR_NOT_AUTHENTICATED,
                    StorageException.ERROR_NOT_AUTHORIZED,
                    -> "Upload is not authorized for the current account."

                    else -> null
                }
            }

            is FirebaseException -> {
                if ((error.message ?: "").contains("Missing or insufficient permissions", ignoreCase = true)) {
                    "Upload is blocked by Firebase permissions for the current account."
                } else {
                    null
                }
            }

            else -> null
        }
    }

    private class PermanentUploadException(
        override val message: String,
    ) : IllegalStateException(message)

    private companion object {
        const val QUEUE_KEY = "capture_upload_queue"
        const val WORK_TAG = "capture_upload"
        const val MAX_AUTO_RETRIES = 5
        const val AUTO_CLEAR_DELAY_MS = 4_000L
        val SEGMENT_SANITIZE_REGEX = "[^a-z0-9._-]+".toRegex()
    }
}

private val UploadQueueStatus.isActive: Boolean
    get() = this == UploadQueueStatus.Queued ||
        this == UploadQueueStatus.Preparing ||
        this == UploadQueueStatus.Uploading ||
        this == UploadQueueStatus.Registering
