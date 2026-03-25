package com.meta.wearable.dat.core.types

data class DatError(
    val description: String,
)

class DatResult<T> private constructor(
    private val value: T?,
    private val error: DatError?,
    private val errorCode: Int? = null,
) {
    val isSuccess: Boolean
        get() = error == null

    fun getOrNull(): T? = value

    fun getOrDefault(defaultValue: T): T = value ?: defaultValue

    fun onFailure(block: (DatError, Int?) -> Unit): DatResult<T> {
        error?.let { block(it, errorCode) }
        return this
    }

    companion object {
        fun <T> success(value: T): DatResult<T> = DatResult(value = value, error = null)

        fun <T> failure(
            description: String,
            errorCode: Int? = null,
        ): DatResult<T> = DatResult(value = null, error = DatError(description), errorCode = errorCode)
    }
}

data class DeviceIdentifier(
    private val rawValue: String,
) {
    override fun toString(): String = rawValue
}

enum class DeviceType {
    META_RAYBAN_DISPLAY,
    RAYBAN_META,
    OAKLEY_META_HSTN,
    OAKLEY_META_VANGUARD,
    UNKNOWN,
}

data class DeviceMetadata(
    val name: String? = null,
    val deviceType: DeviceType? = null,
)

enum class Permission {
    CAMERA,
}

enum class PermissionStatus {
    Granted,
    Denied,
}

sealed class RegistrationState {
    class Unavailable : RegistrationState()
    class Registering : RegistrationState()
    class Unregistering : RegistrationState()
    class Registered : RegistrationState()
}
