package app.blueprint.capture.data.ops

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.google.firebase.analytics.FirebaseAnalytics
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OperationalTelemetry @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val analytics = FirebaseAnalytics.getInstance(context)

    fun recordSuccess(operation: String, detail: String? = null) {
        record(operation = operation, status = "success", detail = detail)
    }

    fun recordFailure(operation: String, detail: String? = null) {
        record(operation = operation, status = "failure", detail = detail)
    }

    private fun record(operation: String, status: String, detail: String?) {
        val safeOperation = operation.take(40)
        val safeStatus = status.take(20)
        val safeDetail = detail?.take(100)

        Log.i(
            "OperationalTelemetry",
            buildString {
                append("operation=")
                append(safeOperation)
                append(" status=")
                append(safeStatus)
                if (!safeDetail.isNullOrBlank()) {
                    append(" detail=")
                    append(safeDetail)
                }
            },
        )

        analytics.logEvent(
            "blueprint_ops_event",
            Bundle().apply {
                putString("operation", safeOperation)
                putString("status", safeStatus)
                safeDetail?.let { putString("detail", it) }
            },
        )
    }
}
