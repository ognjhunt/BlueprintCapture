package app.blueprint.capture.data.capture

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class CaptureUploadWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val repository: CaptureUploadRepository,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val uploadId = inputData.getString(KEY_UPLOAD_ID) ?: return Result.failure()
        repository.getForegroundInfo(uploadId)?.let { setForeground(it) }

        return when (
            repository.runWorkerAttempt(
                id = uploadId,
                runAttemptCount = runAttemptCount,
                onItemUpdated = { item ->
                    if (
                        item.status == app.blueprint.capture.data.model.UploadQueueStatus.Queued ||
                        item.status == app.blueprint.capture.data.model.UploadQueueStatus.Preparing ||
                        item.status == app.blueprint.capture.data.model.UploadQueueStatus.Uploading ||
                        item.status == app.blueprint.capture.data.model.UploadQueueStatus.Registering
                    ) {
                        setForeground(CaptureUploadNotifications.buildForegroundInfo(item))
                    }
                },
            )
        ) {
            CaptureUploadWorkOutcome.Success -> Result.success()
            CaptureUploadWorkOutcome.Retry -> Result.retry()
            CaptureUploadWorkOutcome.Failure -> Result.failure()
        }
    }

    companion object {
        const val KEY_UPLOAD_ID = "upload_id"
    }
}
