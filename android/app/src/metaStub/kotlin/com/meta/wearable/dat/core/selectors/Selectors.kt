package com.meta.wearable.dat.core.selectors

import com.meta.wearable.dat.core.types.DeviceIdentifier

sealed interface DeviceSelector

class AutoDeviceSelector : DeviceSelector

data class SpecificDeviceSelector(
    val identifier: DeviceIdentifier,
) : DeviceSelector
