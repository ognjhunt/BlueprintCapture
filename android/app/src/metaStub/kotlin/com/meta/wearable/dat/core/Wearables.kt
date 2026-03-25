package com.meta.wearable.dat.core

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContract
import com.meta.wearable.dat.core.types.DatResult
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.DeviceMetadata
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object Wearables {
    private const val UNAVAILABLE_MESSAGE =
        "Meta DAT SDK credentials are not configured in this build."

    private val _registrationState = MutableStateFlow<RegistrationState>(RegistrationState.Unavailable())
    private val _devices = MutableStateFlow<List<DeviceIdentifier>>(emptyList())

    val registrationState: StateFlow<RegistrationState> = _registrationState
    val devices: StateFlow<List<DeviceIdentifier>> = _devices
    val devicesMetadata: Map<DeviceIdentifier, MutableStateFlow<DeviceMetadata?>> = emptyMap()

    fun initialize(context: Context): DatResult<Unit> = DatResult.success(Unit)

    fun startRegistration(activity: Activity) {
        throw UnsupportedOperationException(UNAVAILABLE_MESSAGE)
    }

    fun checkPermissionStatus(permission: Permission): DatResult<PermissionStatus> =
        DatResult.failure(UNAVAILABLE_MESSAGE)

    class RequestPermissionContract : ActivityResultContract<Permission, DatResult<PermissionStatus>>() {
        override fun createIntent(
            context: Context,
            input: Permission,
        ): Intent = Intent()

        override fun parseResult(
            resultCode: Int,
            intent: Intent?,
        ): DatResult<PermissionStatus> = DatResult.success(PermissionStatus.Denied)
    }
}
