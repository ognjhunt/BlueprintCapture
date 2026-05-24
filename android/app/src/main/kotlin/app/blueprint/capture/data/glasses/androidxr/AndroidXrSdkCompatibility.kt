package app.blueprint.capture.data.glasses.androidxr

data class AndroidXrArtifactReadiness(
    val coordinate: String,
    val usable: Boolean,
    val blocker: String? = null,
)

object AndroidXrSdkCompatibility {
    private const val XR_RUNTIME_DP4 = "androidx.xr.runtime:runtime:1.0.0-alpha14"
    private const val XR_ARCORE_DP4 = "androidx.xr.arcore:arcore:1.0.0-alpha14"
    private const val PROJECTED_TESTING_ALPHA08 = "androidx.xr.projected:projected-testing:1.0.0-alpha08"

    fun safeDp4Artifacts(
        compileSdk: Int,
        agpVersion: String,
    ): List<AndroidXrArtifactReadiness> {
        return listOf(
            AndroidXrArtifactReadiness(coordinate = XR_RUNTIME_DP4, usable = true),
            AndroidXrArtifactReadiness(coordinate = XR_ARCORE_DP4, usable = true),
        )
    }

    fun projectedTestRuleReadiness(
        compileSdk: Int,
        agpVersion: String,
    ): AndroidXrArtifactReadiness {
        val usable = compileSdk >= 37 && compareVersions(agpVersion, "9.2.0") >= 0
        return AndroidXrArtifactReadiness(
            coordinate = PROJECTED_TESTING_ALPHA08,
            usable = usable,
            blocker = if (usable) {
                null
            } else {
                "ProjectedTestRule is in projected-testing alpha08, but alpha08 currently requires compileSdk 37 and AGP 9.2.0."
            },
        )
    }

    private fun compareVersions(left: String, right: String): Int {
        val leftParts = left.numericParts()
        val rightParts = right.numericParts()
        val max = maxOf(leftParts.size, rightParts.size)
        for (index in 0 until max) {
            val delta = (leftParts.getOrElse(index) { 0 }) - (rightParts.getOrElse(index) { 0 })
            if (delta != 0) return delta
        }
        return 0
    }

    private fun String.numericParts(): List<Int> =
        split('.', '-', '+')
            .mapNotNull { part -> part.takeWhile(Char::isDigit).toIntOrNull() }
}
