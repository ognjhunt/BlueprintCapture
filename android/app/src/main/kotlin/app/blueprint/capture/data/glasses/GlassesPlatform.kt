package app.blueprint.capture.data.glasses

enum class GlassesPlatformId {
    MetaDat,
    AndroidXrProjected,
}

data class GlassesCapabilities(
    val hasDisplay: Boolean = false,
    val supportsProjectedCamera: Boolean = false,
    val supportsProjectedMic: Boolean = false,
    val supportsDevicePose: Boolean = false,
    val supportsGeospatial: Boolean = false,
)

interface GlassesPlatform {
    val id: GlassesPlatformId
    val title: String
    val subtitle: String
    val capabilities: GlassesCapabilities
}

object MetaDatGlassesPlatform : GlassesPlatform {
    override val id: GlassesPlatformId = GlassesPlatformId.MetaDat
    override val title: String = "Meta smart glasses"
    override val subtitle: String = "Existing Meta DAT flow for hands-free capture."
    override val capabilities: GlassesCapabilities = GlassesCapabilities(
        hasDisplay = false,
        supportsProjectedCamera = false,
        supportsProjectedMic = false,
        supportsDevicePose = false,
        supportsGeospatial = false,
    )
}

object AndroidXrProjectedPlatform : GlassesPlatform {
    override val id: GlassesPlatformId = GlassesPlatformId.AndroidXrProjected
    override val title: String = "Android XR AI glasses"
    override val subtitle: String = "Projected Android-hosted activity for display and audio-first glasses."
    override val capabilities: GlassesCapabilities = GlassesCapabilities(
        hasDisplay = false,
        supportsProjectedCamera = true,
        supportsProjectedMic = true,
        supportsDevicePose = false,
        supportsGeospatial = false,
    )
}

object GlassesPlatformRegistry {
    val all: List<GlassesPlatform> = listOf(
        AndroidXrProjectedPlatform,
        MetaDatGlassesPlatform,
    )

    fun get(id: GlassesPlatformId): GlassesPlatform = all.first { it.id == id }
}
