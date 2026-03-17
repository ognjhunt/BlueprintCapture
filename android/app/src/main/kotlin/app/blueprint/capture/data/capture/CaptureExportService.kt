package app.blueprint.capture.data.capture

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.inject.Inject
import javax.inject.Singleton

data class FinalizedCaptureBundle(
    val sceneId: String,
    val captureId: String,
    val captureRoot: File,
    val shareArtifact: File,
)

interface CaptureExportServiceProtocol {
    suspend fun exportCapture(
        request: AndroidCaptureBundleRequest,
        bundleRoot: File,
    ): FinalizedCaptureBundle
}

@Singleton
class CaptureExportService @Inject constructor(
    @ApplicationContext private val context: Context,
) : CaptureExportServiceProtocol {
    override suspend fun exportCapture(
        request: AndroidCaptureBundleRequest,
        bundleRoot: File,
    ): FinalizedCaptureBundle {
        val exportRoot = makeExportRoot(
            sceneId = request.sceneId,
            captureId = request.captureId,
        )
        if (exportRoot.exists()) {
            exportRoot.deleteRecursively()
        }
        exportRoot.parentFile?.mkdirs()
        copyRecursively(source = bundleRoot, destination = exportRoot)

        val exportParent = requireNotNull(exportRoot.parentFile) {
            "Export root must have a parent directory."
        }
        val shareArtifact = exportParent.resolve("${exportRoot.name}.zip")
        if (shareArtifact.exists()) {
            shareArtifact.delete()
        }
        zipDirectory(sourceRoot = exportRoot, output = shareArtifact)

        return FinalizedCaptureBundle(
            sceneId = request.sceneId,
            captureId = request.captureId,
            captureRoot = exportRoot,
            shareArtifact = shareArtifact,
        )
    }

    private fun makeExportRoot(
        sceneId: String,
        captureId: String,
    ): File {
        return context.filesDir
            .resolve("exports")
            .resolve("scenes")
            .resolve(sceneId)
            .resolve("captures")
            .resolve(captureId)
    }

    private fun copyRecursively(
        source: File,
        destination: File,
    ) {
        if (source.isDirectory) {
            destination.mkdirs()
            source.listFiles().orEmpty().forEach { child ->
                copyRecursively(
                    source = child,
                    destination = destination.resolve(child.name),
                )
            }
        } else {
            destination.parentFile?.mkdirs()
            source.copyTo(destination, overwrite = true)
        }
    }

    private fun zipDirectory(
        sourceRoot: File,
        output: File,
    ) {
        ZipOutputStream(FileOutputStream(output)).use { zipOutput ->
            val zipBase = requireNotNull(sourceRoot.parentFile) {
                "Export source must have a parent directory."
            }
            sourceRoot.walkTopDown()
                .filter { it.isFile }
                .forEach { file ->
                    val entryName = file.relativeTo(zipBase).invariantSeparatorsPath
                    zipOutput.putNextEntry(ZipEntry(entryName))
                    FileInputStream(file).use { input ->
                        input.copyTo(zipOutput)
                    }
                    zipOutput.closeEntry()
                }
        }
    }
}
