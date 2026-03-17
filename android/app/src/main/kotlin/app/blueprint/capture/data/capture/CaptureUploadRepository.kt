package app.blueprint.capture.data.capture

import android.content.SharedPreferences
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.edit
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.model.UploadQueueStatus
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import com.google.firebase.storage.StorageReference
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Singleton
class CaptureUploadRepository @Inject constructor(
    private val sharedPreferences: SharedPreferences,
    private val storage: FirebaseStorage,
) {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val queueLock = Any()
    private val activeUploads = linkedMapOf<String, kotlinx.coroutines.Job>()
    private val _queue = MutableStateFlow(loadQueue().normalizeInterruptedUploads())

    val queue: StateFlow<List<UploadQueueItem>> = _queue.asStateFlow()

    init {
        persistQueue(_queue.value)
    }

    fun enqueueBundleUpload(
        label: String,
        bundleRoot: File,
        creatorId: String?,
    ): String {
        val uploadId = bundleRoot.name
        val item = UploadQueueItem(
            id = uploadId,
            label = label,
            progress = 0f,
            status = UploadQueueStatus.Queued,
            detail = "Queued for upload",
            localBundlePath = bundleRoot.absolutePath,
            creatorId = creatorId,
        )
        synchronized(queueLock) {
            val trimmed = _queue.value.filterNot { it.id == uploadId }.take(7)
            val updated = listOf(item) + trimmed
            _queue.value = updated
            persistQueue(updated)
        }
        startUpload(uploadId)
        return uploadId
    }

    fun retryUpload(id: String) {
        val item = _queue.value.firstOrNull { it.id == id } ?: return
        if (item.localBundlePath.isNullOrBlank()) {
            markFailed(id, "Local capture bundle is missing.")
            return
        }
        updateItem(id) {
            it.copy(
                progress = 0f,
                status = UploadQueueStatus.Queued,
                detail = "Retry queued",
                remotePrefix = null,
            )
        }
        startUpload(id)
    }

    private fun startUpload(id: String) {
        synchronized(queueLock) {
            if (activeUploads.containsKey(id)) return
            activeUploads[id] = scope.launch {
                try {
                    performUpload(id)
                } finally {
                    synchronized(queueLock) {
                        activeUploads.remove(id)
                    }
                }
            }
        }
    }

    private suspend fun performUpload(id: String) {
        val item = _queue.value.firstOrNull { it.id == id } ?: return
        val bundlePath = item.localBundlePath ?: run {
            markFailed(id, "Local capture bundle is missing.")
            return
        }
        val bundleRoot = File(bundlePath)
        if (!bundleRoot.exists()) {
            markFailed(id, "Local capture bundle is missing.")
            return
        }

        val files = bundleRoot.walkTopDown()
            .filter(File::isFile)
            .sortedBy { file -> file.absolutePath }
            .toList()

        if (files.isEmpty()) {
            markFailed(id, "Capture bundle has no files to upload.")
            return
        }

        val totalBytes = files.sumOf { it.length().coerceAtLeast(1L) }.coerceAtLeast(1L)
        val remotePrefix = buildRemotePrefix(item)

        updateItem(id) {
            it.copy(
                status = UploadQueueStatus.Preparing,
                detail = "Preparing ${files.size} files",
                remotePrefix = remotePrefix,
                progress = 0.02f,
            )
        }

        var uploadedBytes = 0L
        try {
            files.forEach { file ->
                val relativePath = file.relativeTo(bundleRoot).invariantSeparatorsPath
                updateItem(id) {
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
                        .coerceIn(0f, 0.99f)
                    updateItem(id) {
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

            updateItem(id) {
                it.copy(
                    status = UploadQueueStatus.Completed,
                    progress = 1f,
                    detail = "Uploaded to Firebase Storage",
                    remotePrefix = remotePrefix,
                )
            }
        } catch (_: CancellationException) {
            markFailed(id, "Upload cancelled.")
        } catch (error: Exception) {
            markFailed(id, error.message ?: "Upload failed.")
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

    private fun buildRemotePrefix(item: UploadQueueItem): String {
        val creatorSegment = sanitizePathSegment(item.creatorId ?: "anonymous")
        val captureSegment = sanitizePathSegment(item.id)
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

    private fun markFailed(id: String, reason: String) {
        updateItem(id) {
            it.copy(
                status = UploadQueueStatus.Failed,
                detail = reason,
            )
        }
    }

    private fun updateItem(
        id: String,
        transform: (UploadQueueItem) -> UploadQueueItem,
    ) {
        synchronized(queueLock) {
            val updated = _queue.value.map { item ->
                if (item.id == id) {
                    transform(item)
                } else {
                    item
                }
            }
            _queue.value = updated
            persistQueue(updated)
        }
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

    private fun List<UploadQueueItem>.normalizeInterruptedUploads(): List<UploadQueueItem> = map { item ->
        if (item.status == UploadQueueStatus.Queued ||
            item.status == UploadQueueStatus.Preparing ||
            item.status == UploadQueueStatus.Uploading
        ) {
            item.copy(
                status = UploadQueueStatus.Failed,
                detail = "Upload interrupted. Retry to continue.",
                progress = item.progress.coerceAtMost(0.98f),
            )
        } else {
            item
        }
    }

    private fun sanitizePathSegment(value: String): String {
        return value.lowercase()
            .replace(SEGMENT_SANITIZE_REGEX, "-")
            .trim('-')
            .ifBlank { "capture" }
    }

    private companion object {
        const val QUEUE_KEY = "capture_upload_queue"
        val SEGMENT_SANITIZE_REGEX = "[^a-z0-9._-]+".toRegex()
    }
}
