import ARKit
import Foundation
import UIKit

#if canImport(NSDK) && !targetEnvironment(simulator)
import NSDK

/// Real NSDK conformance. Drives Niantic's scanning session on top of the
/// app-owned ARSession: `DefaultSessionDataSource` reads frames from our session
/// and `NSDKSession.update()` offers the latest ARKit sample on each frame tick.
/// NSDK controls its own sampling and serialization, so equality with Blueprint's
/// retained video frames is validated later rather than assumed here.
@MainActor
final class NianticNSDKScanningBackend: NianticScanningBackendProtocol {
    /// NSDK allows a single active `NSDKSession` per process; it is created on
    /// first use and kept for the app lifetime. Scan lifecycle is per capture.
    private static var sharedSession: NSDKSession?
    private static var lastAccessToken: String?

    private final class InterfaceOrientationReporter: UIOrientationReporter {
        var currentOrientation: NSDKScreenOrientation {
            let interfaceOrientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .interfaceOrientation ?? .portrait
            return NSDKScreenOrientation(interfaceOrientation)
        }
    }

    // NSDKSession holds its data source weakly; both must be retained here.
    private var dataSource: DefaultSessionDataSource?
    private let orientationReporter = InterfaceOrientationReporter()
    private var scanningSession: NSDKScanningSession?
    private var isScanning = false

    var availability: NianticScanningAvailability { .available }

    var sdkVersion: String? { NSDKSession.version() }

    func beginScan(
        arSession: ARSession,
        accessToken: String,
        scanStoreDirectory: URL,
        profile: NianticScanRecordingProfile
    ) throws {
        let session = try acquireSession(accessToken: accessToken)
        let dataSource = DefaultSessionDataSource(session: arSession, orientationReporter: orientationReporter)
        self.dataSource = dataSource
        session.dataSource = dataSource

        let scanning = session.acquireScanningSession()
        scanningSession = scanning
        let configuration = NSDKScanningSession.Configuration(
            framerate: profile.scanFramerate,
            path: scanStoreDirectory.path,
            generateDepthsIfLidarUnavailable: profile.generateDepthsIfLidarUnavailable,
            enableFullResolution: profile.enableFullResolution,
            fullResolutionFramerate: profile.fullResolutionFramerate,
            recordAllSensors: profile.recordAllSensors
        )
        do {
            try scanning.configure(with: configuration)
        } catch {
            scanningSession = nil
            self.dataSource = nil
            throw NianticScanningBackendError.configurationFailed(String(describing: error))
        }
        scanning.start()
        isScanning = true
    }

    func noteFrame() {
        guard isScanning, dataSource != nil else { return }
        Self.sharedSession?.update()
    }

    func recordedFrameCount() -> Int? {
        guard let scanning = scanningSession else { return nil }
        return scanning.recordingInfo().frameCount
    }

    func finishScan(timeoutSeconds: Double) async throws -> NianticSavedScanInfo {
        guard let scanning = scanningSession else {
            throw NianticScanningBackendError.saveFailed("no_active_scanning_session")
        }
        defer {
            scanning.stop()
            isScanning = false
            scanningSession = nil
            dataSource = nil
        }
        let frameCount = scanning.recordingInfo().frameCount
        guard frameCount > 0 else {
            throw NianticScanningBackendError.noFramesRecorded
        }
        do {
            let saveInfo = try await scanning.saveCurrentScan(timeout: timeoutSeconds)
            return NianticSavedScanInfo(
                scanId: saveInfo.scanId,
                scanDirectoryURL: URL(fileURLWithPath: saveInfo.path, isDirectory: true)
            )
        } catch {
            throw NianticScanningBackendError.saveFailed(String(describing: error))
        }
    }

    func exportArchives(
        scan: NianticSavedScanInfo,
        exportAsVideo: Bool,
        userData: [String: String],
        timeoutSeconds: Double,
        progress: ((Float) -> Void)?
    ) async throws -> [URL] {
        guard let session = Self.sharedSession else {
            throw NianticScanningBackendError.exportFailed("nsdk_session_missing")
        }
        let exporter = session.acquireRecordingExporter()
        do {
            let path = try await exporter.export(
                scanDirPath: scan.scanDirectoryURL.path,
                scanId: scan.scanId,
                userData: userData,
                exportAsVideo: exportAsVideo,
                exportResolution: .mixed,
                timeout: timeoutSeconds,
                progressCallback: progress
            )
            return [URL(fileURLWithPath: path)]
        } catch {
            throw NianticScanningBackendError.exportFailed(String(describing: error))
        }
    }

    func cancelScan() {
        guard let scanning = scanningSession else { return }
        if isScanning {
            scanning.stop()
        }
        isScanning = false
        scanningSession = nil
        dataSource = nil
    }

    private func acquireSession(accessToken: String) throws -> NSDKSession {
        if let session = Self.sharedSession {
            if Self.lastAccessToken != accessToken {
                session.setAccessToken(accessToken)
                Self.lastAccessToken = accessToken
            }
            return session
        }
        let session = NSDKSession(accessToken: accessToken, useLidar: true)
        Self.sharedSession = session
        Self.lastAccessToken = accessToken
        return session
    }
}
#endif
