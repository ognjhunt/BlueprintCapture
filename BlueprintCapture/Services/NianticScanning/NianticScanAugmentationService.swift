import ARKit
import CryptoKit
import Foundation

/// Runs an opt-in NSDK recording beside the canonical shared-ARKit recorder and
/// attaches the vendor archive to the raw bundle as an additive `nsdk/` family.
///
/// Contract guarantees:
/// - The canonical V3 bundle is never blocked, altered, or failed by this service;
///   every augmentation failure downgrades to a truthful `nsdk/archive_manifest.json`
///   failure record (or to no `nsdk/` directory at all when augmentation never began).
/// - Vendor archives are preserved byte-exact; `CaptureBundleFinalizer` hashes them
///   into `hashes.json` with every other bundle file, and the upload plan carries
///   them because both walk the bundle directory recursively.
/// - `nsdk/reconstruction_binding.json` declares how derived reconstructions bind
///   back to the canonical metric trajectory; it never claims metric proof itself.
@MainActor
protocol NianticScanAugmentationServiceProtocol: AnyObject {
    var isActive: Bool { get }

    func beginIfAvailable(arSession: ARSession, identity: NianticScanCaptureIdentity)
    func noteFrame()
    func captureDidFail()
    func finishAndAttach(to bundleDirectory: URL) async
}

@MainActor
final class NianticScanAugmentationService: NianticScanAugmentationServiceProtocol {
    enum Outcome: Equatable {
        case notAttempted(reason: String)
        case exported(archiveCount: Int)
        case failed(reason: String)
    }

    private struct ActiveScan {
        let identity: NianticScanCaptureIdentity
        let scanStoreDirectoryURL: URL
    }

    private let backend: NianticScanningBackendProtocol
    private let config: NianticScanAugmentationConfig
    private let fileManager: FileManager
    private let liDARAvailable: () -> Bool
    private var activeScan: ActiveScan?
    private(set) var lastOutcome: Outcome?

    var isActive: Bool { activeScan != nil }

    init(
        backend: NianticScanningBackendProtocol? = nil,
        config: NianticScanAugmentationConfig? = nil,
        fileManager: FileManager = .default,
        liDARAvailable: @escaping () -> Bool = {
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
    ) {
        self.backend = backend ?? NianticScanningBackendFactory.make()
        self.config = config ?? .load()
        self.fileManager = fileManager
        self.liDARAvailable = liDARAvailable
    }

    func beginIfAvailable(arSession: ARSession, identity: NianticScanCaptureIdentity) {
        guard activeScan == nil else { return }

        if let skipReason = skipReason() {
            lastOutcome = .notAttempted(reason: skipReason)
            print("ℹ️ [NianticScan] Augmentation skipped: \(skipReason)")
            return
        }
        guard let accessToken = config.accessToken else {
            lastOutcome = .notAttempted(reason: "access_token_missing")
            return
        }

        let scanStoreURL = fileManager.temporaryDirectory
            .appendingPathComponent("nsdk-scan-\(identity.captureBaseFilename)", isDirectory: true)
        do {
            if fileManager.fileExists(atPath: scanStoreURL.path) {
                try fileManager.removeItem(at: scanStoreURL)
            }
            try fileManager.createDirectory(at: scanStoreURL, withIntermediateDirectories: true)
            try backend.beginScan(
                arSession: arSession,
                accessToken: accessToken,
                scanStoreDirectory: scanStoreURL,
                profile: NianticScanRecordingProfile(config: config)
            )
        } catch {
            lastOutcome = .notAttempted(reason: "begin_failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: scanStoreURL)
            CaptureCrashTelemetryService.shared.recordBreadcrumb(
                name: "niantic_scan_augmentation_begin_failed",
                status: "skipped",
                metadata: ["capture_id": identity.captureBaseFilename, "reason": error.localizedDescription]
            )
            print("⚠️ [NianticScan] Failed to begin vendor scan: \(error.localizedDescription)")
            return
        }

        activeScan = ActiveScan(identity: identity, scanStoreDirectoryURL: scanStoreURL)
        lastOutcome = nil
        CaptureCrashTelemetryService.shared.recordBreadcrumb(
            name: "niantic_scan_augmentation_started",
            status: "recording",
            metadata: ["capture_id": identity.captureBaseFilename]
        )
        print("🟢 [NianticScan] Vendor scan recording started (sdk=\(backend.sdkVersion ?? "unknown"))")
    }

    func noteFrame() {
        guard activeScan != nil else { return }
        backend.noteFrame()
    }

    func captureDidFail() {
        guard let scan = activeScan else { return }
        backend.cancelScan()
        try? fileManager.removeItem(at: scan.scanStoreDirectoryURL)
        activeScan = nil
        lastOutcome = .failed(reason: "capture_failed_before_export")
        print("⚪️ [NianticScan] Vendor scan discarded — capture failed")
    }

    func finishAndAttach(to bundleDirectory: URL) async {
        guard let scan = activeScan else { return }
        activeScan = nil
        defer { try? fileManager.removeItem(at: scan.scanStoreDirectoryURL) }

        let identity = scan.identity
        let frameCount = backend.recordedFrameCount()
        let exportStartedAt = Date()
        do {
            let saved = try await backend.finishScan(timeoutSeconds: config.saveTimeoutSeconds)
            let exportedURLs = try await backend.exportArchives(
                scan: saved,
                exportAsVideo: config.exportAsVideo,
                userData: identity.exportUserData,
                timeoutSeconds: config.exportTimeoutSeconds,
                progress: nil
            )
            guard !exportedURLs.isEmpty else {
                throw NianticScanningBackendError.exportFailed("no_archives_returned")
            }

            let archives = try attachArchives(exportedURLs, to: bundleDirectory)
            let completedAt = Date()
            let manifest = NianticArchiveManifest(
                schemaVersion: NianticArchiveManifest.schemaVersionValue,
                status: NianticArchiveManifest.statusExported,
                vendor: NianticArchiveManifest.vendorValue,
                sdkProduct: NianticArchiveManifest.sdkProductValue,
                sdkVersion: backend.sdkVersion,
                evidenceClass: NianticArchiveManifest.evidenceClassValue,
                authority: NianticArchiveManifest.authorityValue,
                scanId: saved.scanId,
                coordinateFrameSessionId: identity.coordinateFrameSessionId,
                captureBaseFilename: identity.captureBaseFilename,
                captureStartedAt: identity.startedAt,
                recordedFrameCountReported: frameCount,
                recordingProfile: NianticScanRecordingProfile(config: config),
                businessTermsAuthorization: "operator_attested",
                canonicalCaptureAuthority: false,
                archiveInspectionStatus: "required_before_alignment_or_reconstruction_claims",
                export: NianticArchiveManifest.ExportRecord(
                    exportAsVideo: config.exportAsVideo,
                    startedAt: exportStartedAt,
                    completedAt: completedAt,
                    durationSec: completedAt.timeIntervalSince(exportStartedAt),
                    archives: archives
                ),
                failureReason: nil
            )
            let binding = NianticReconstructionBinding.make(
                identity: identity,
                scanId: saved.scanId
            )
            try writeSidecars(manifest: manifest, binding: binding, in: bundleDirectory)

            lastOutcome = .exported(archiveCount: archives.count)
            CaptureCrashTelemetryService.shared.recordBreadcrumb(
                name: "niantic_scan_augmentation_exported",
                status: "exported",
                metadata: [
                    "capture_id": identity.captureBaseFilename,
                    "scan_id": saved.scanId,
                    "archive_count": "\(archives.count)",
                    "export_duration_sec": String(format: "%.1f", completedAt.timeIntervalSince(exportStartedAt)),
                ]
            )
            print("✅ [NianticScan] Vendor archive attached (\(archives.count) file(s), scan=\(saved.scanId))")
        } catch {
            backend.cancelScan()
            recordFailure(
                reason: error.localizedDescription,
                identity: identity,
                frameCount: frameCount,
                in: bundleDirectory
            )
        }
    }

    // MARK: - Private

    private func skipReason() -> String? {
        guard config.isEnabled else { return "disabled_by_config" }
        guard config.businessTermsAuthorized else { return "business_terms_not_authorized" }
        guard config.accessToken?.isEmpty == false else { return "access_token_missing" }
        if config.requiresLiDAR, !liDARAvailable() {
            return "lidar_required_for_qualified_lane"
        }
        if let reason = backend.availability.unavailableReason {
            return reason
        }
        if let freeBytes = availableDiskBytes(), freeBytes < config.minimumFreeDiskBytes {
            return "insufficient_free_disk"
        }
        return nil
    }

    private func availableDiskBytes() -> Int64? {
        let values = try? fileManager.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func attachArchives(_ exportedURLs: [URL], to bundleDirectory: URL) throws -> [NianticArchiveManifest.ArchiveEntry] {
        let archivesDirectory = bundleDirectory
            .appendingPathComponent(NianticScanSidecarLayout.directoryName, isDirectory: true)
            .appendingPathComponent(NianticScanSidecarLayout.archivesDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: archivesDirectory, withIntermediateDirectories: true)

        var entries: [NianticArchiveManifest.ArchiveEntry] = []
        for (index, sourceURL) in exportedURLs.enumerated() {
            let filename = NianticScanSidecarLayout.archiveFilename(index: index)
            let destinationURL = archivesDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            let sizeBytes = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            entries.append(
                NianticArchiveManifest.ArchiveEntry(
                    index: index,
                    file: "\(NianticScanSidecarLayout.directoryName)/\(NianticScanSidecarLayout.archivesDirectoryName)/\(filename)",
                    sha256: try sha256Hex(ofFileAt: destinationURL),
                    sizeBytes: Int64(sizeBytes)
                )
            )
        }
        return entries
    }

    private func recordFailure(
        reason: String,
        identity: NianticScanCaptureIdentity,
        frameCount: Int?,
        in bundleDirectory: URL
    ) {
        // Remove any partially attached archives so the bundle carries either the
        // complete vendor export or an explicit failure record — never fragments.
        let nsdkDirectory = bundleDirectory.appendingPathComponent(NianticScanSidecarLayout.directoryName, isDirectory: true)
        try? fileManager.removeItem(
            at: nsdkDirectory.appendingPathComponent(NianticScanSidecarLayout.archivesDirectoryName, isDirectory: true)
        )

        let manifest = NianticArchiveManifest(
            schemaVersion: NianticArchiveManifest.schemaVersionValue,
            status: NianticArchiveManifest.statusFailed,
            vendor: NianticArchiveManifest.vendorValue,
            sdkProduct: NianticArchiveManifest.sdkProductValue,
            sdkVersion: backend.sdkVersion,
            evidenceClass: NianticArchiveManifest.evidenceClassValue,
            authority: NianticArchiveManifest.authorityValue,
            scanId: nil,
            coordinateFrameSessionId: identity.coordinateFrameSessionId,
            captureBaseFilename: identity.captureBaseFilename,
            captureStartedAt: identity.startedAt,
            recordedFrameCountReported: frameCount,
            recordingProfile: NianticScanRecordingProfile(config: config),
            businessTermsAuthorization: "operator_attested",
            canonicalCaptureAuthority: false,
            archiveInspectionStatus: "export_failed_no_archive_to_inspect",
            export: nil,
            failureReason: reason
        )
        do {
            try writeSidecars(manifest: manifest, binding: nil, in: bundleDirectory)
        } catch {
            // If even the failure record cannot be written, leave no nsdk/ residue.
            try? fileManager.removeItem(at: nsdkDirectory)
        }

        lastOutcome = .failed(reason: reason)
        CaptureCrashTelemetryService.shared.recordErrorCode(
            "niantic_scan_augmentation_failed",
            metadata: ["capture_id": identity.captureBaseFilename, "reason": reason]
        )
        print("⚠️ [NianticScan] Vendor scan export failed: \(reason)")
    }

    private func writeSidecars(
        manifest: NianticArchiveManifest,
        binding: NianticReconstructionBinding?,
        in bundleDirectory: URL
    ) throws {
        let nsdkDirectory = bundleDirectory.appendingPathComponent(NianticScanSidecarLayout.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: nsdkDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: nsdkDirectory.appendingPathComponent(NianticScanSidecarLayout.archiveManifestFilename),
            options: .atomic
        )
        if let binding {
            let bindingData = try encoder.encode(binding)
            try bindingData.write(
                to: nsdkDirectory.appendingPathComponent(NianticScanSidecarLayout.reconstructionBindingFilename),
                options: .atomic
            )
        }
    }

    private func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
