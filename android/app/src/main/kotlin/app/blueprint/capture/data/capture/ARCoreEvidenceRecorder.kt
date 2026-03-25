package app.blueprint.capture.data.capture

import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ARCoreEvidenceRecorder @Inject constructor() {
    fun prepareOutput(root: File): File {
        val arcoreRoot = root.resolve("arcore")
        arcoreRoot.resolve("depth").mkdirs()
        arcoreRoot.resolve("confidence").mkdirs()
        return arcoreRoot
    }

    fun writeSessionIntrinsics(
        root: File,
        intrinsicsJson: String,
    ): File = root.resolve("session_intrinsics.json").also { it.writeText(intrinsicsJson) }

    fun appendJsonLine(
        root: File,
        relativePath: String,
        jsonLine: String,
    ) {
        val file = root.resolve(relativePath)
        file.parentFile?.mkdirs()
        file.appendText(jsonLine.trimEnd() + "\n")
    }
}
