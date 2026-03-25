package app.blueprint.capture.data.glasses

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@Singleton
class AndroidXrCapabilityRepository @Inject constructor() {
    private val _capabilities = MutableStateFlow(AndroidXrProjectedPlatform.capabilities)
    val capabilities: StateFlow<GlassesCapabilities> = _capabilities.asStateFlow()

    fun update(capabilities: GlassesCapabilities) {
        _capabilities.value = capabilities
    }

    fun reset() {
        _capabilities.value = AndroidXrProjectedPlatform.capabilities
    }
}
