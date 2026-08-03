import ARKit
import Foundation

/// Seam over the Niantic Spatial SDK (NSDK) scanning stack.
///
/// The real conformance (`NianticNSDKScanningBackend`) is compiled only when the
/// NSDK package is linked and the build targets a device; everywhere else the
/// unavailable stub keeps the app and tests building without the SDK, mirroring
/// the Meta MWDAT wrapper pattern in `GlassesCaptureManager`.
@MainActor
protocol NianticScanningBackendProtocol: AnyObject {
    var availability: NianticScanningAvailability { get }
    var sdkVersion: String? { get }

    /// Attaches NSDK to the app-owned, already-running ARSession and starts the
    /// vendor scan recording into `scanStoreDirectory`. NSDK never owns the camera.
    func beginScan(
        arSession: ARSession,
        accessToken: String,
        scanStoreDirectory: URL,
        profile: NianticScanRecordingProfile
    ) throws

    /// Per-ARFrame tick; forwards the latest camera/pose/depth samples to NSDK.
    func noteFrame()

    /// Frame count NSDK reports for the in-progress recording.
    func recordedFrameCount() -> Int?

    /// Stops the vendor recording and persists the scan into the scan store.
    func finishScan(timeoutSeconds: Double) async throws -> NianticSavedScanInfo

    /// Exports the saved scan as one or more `.tgz` archives and returns their paths.
    func exportArchives(
        scan: NianticSavedScanInfo,
        exportAsVideo: Bool,
        userData: [String: String],
        timeoutSeconds: Double,
        progress: ((Float) -> Void)?
    ) async throws -> [URL]

    /// Discards any in-progress, unsaved vendor recording.
    func cancelScan()
}

/// Stub used when the NSDK package is not linked (or on simulator builds).
@MainActor
final class NianticScanningBackendUnavailable: NianticScanningBackendProtocol {
    let availability: NianticScanningAvailability
    let sdkVersion: String? = nil

    init(reason: String = "nsdk_package_not_linked") {
        availability = .unavailable(reason: reason)
    }

    func beginScan(
        arSession: ARSession,
        accessToken: String,
        scanStoreDirectory: URL,
        profile: NianticScanRecordingProfile
    ) throws {
        throw NianticScanningBackendError.sdkUnavailable(reason: availability.unavailableReason ?? "unavailable")
    }

    func noteFrame() {}

    func recordedFrameCount() -> Int? { nil }

    func finishScan(timeoutSeconds: Double) async throws -> NianticSavedScanInfo {
        throw NianticScanningBackendError.sdkUnavailable(reason: availability.unavailableReason ?? "unavailable")
    }

    func exportArchives(
        scan: NianticSavedScanInfo,
        exportAsVideo: Bool,
        userData: [String: String],
        timeoutSeconds: Double,
        progress: ((Float) -> Void)?
    ) async throws -> [URL] {
        throw NianticScanningBackendError.sdkUnavailable(reason: availability.unavailableReason ?? "unavailable")
    }

    func cancelScan() {}
}

@MainActor
enum NianticScanningBackendFactory {
    /// True when this build can drive the real NSDK scanning stack.
    nonisolated static var supportsRealNSDK: Bool {
        #if canImport(NSDK) && !targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func make() -> NianticScanningBackendProtocol {
        #if canImport(NSDK) && !targetEnvironment(simulator)
        return NianticNSDKScanningBackend()
        #else
        return NianticScanningBackendUnavailable()
        #endif
    }
}
