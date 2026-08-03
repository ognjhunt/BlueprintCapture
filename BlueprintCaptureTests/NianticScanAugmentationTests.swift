import ARKit
import CryptoKit
import Foundation
import Testing
@testable import BlueprintCapture

@MainActor
private final class FakeNianticScanningBackend: NianticScanningBackendProtocol {
    var availability: NianticScanningAvailability = .available
    var sdkVersion: String? = "fixture-sdk"
    var beginCalls = 0
    var noteCalls = 0
    var cancelCalls = 0
    var profile: NianticScanRecordingProfile?
    var exportError: Error?
    var scanDirectory: URL?

    func beginScan(
        arSession: ARSession,
        accessToken: String,
        scanStoreDirectory: URL,
        profile: NianticScanRecordingProfile
    ) throws {
        beginCalls += 1
        self.profile = profile
        scanDirectory = scanStoreDirectory
    }

    func noteFrame() { noteCalls += 1 }
    func recordedFrameCount() -> Int? { noteCalls }

    func finishScan(timeoutSeconds: Double) async throws -> NianticSavedScanInfo {
        guard let scanDirectory else {
            throw NianticScanningBackendError.saveFailed("fixture_scan_directory_missing")
        }
        return NianticSavedScanInfo(scanId: "fixture-scan", scanDirectoryURL: scanDirectory)
    }

    func exportArchives(
        scan: NianticSavedScanInfo,
        exportAsVideo: Bool,
        userData: [String: String],
        timeoutSeconds: Double,
        progress: ((Float) -> Void)?
    ) async throws -> [URL] {
        if let exportError { throw exportError }
        let archive = scan.scanDirectoryURL.appendingPathComponent("fixture.tgz")
        try Data("fixture-nsdk-archive".utf8).write(to: archive)
        return [archive]
    }

    func cancelScan() { cancelCalls += 1 }
}

@Suite("Optional Niantic capture augmentation")
struct NianticScanAugmentationTests {
    private func identity() -> NianticScanCaptureIdentity {
        NianticScanCaptureIdentity(
            captureBaseFilename: "walkthrough-fixture",
            coordinateFrameSessionId: "coordinate-session-fixture",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "1.0",
            appBuild: "1"
        )
    }

    private func enabledConfig() -> NianticScanAugmentationConfig {
        NianticScanAugmentationConfig(
            isEnabled: true,
            businessTermsAuthorized: true,
            accessToken: "short-lived-fixture-token",
            minimumFreeDiskBytes: 0
        )
    }

    @Test @MainActor
    func configurationFailsClosedAndUsesOnlyExplicitEnvironment() {
        let defaults = NianticScanAugmentationConfig.load(environment: [:])
        #expect(defaults.isEnabled == false)
        #expect(defaults.businessTermsAuthorized == false)
        #expect(defaults.accessToken == nil)
        #expect(defaults.exportAsVideo == false)
        #expect(defaults.requiresLiDAR == true)

        let enabled = NianticScanAugmentationConfig.load(environment: [
            "BLUEPRINT_ENABLE_NIANTIC_SCAN_AUGMENTATION": "true",
            "BLUEPRINT_NIANTIC_BUSINESS_TERMS_AUTHORIZED": "true",
            "BLUEPRINT_NIANTIC_ACCESS_TOKEN": "  ephemeral  ",
            "BLUEPRINT_NIANTIC_FULL_RESOLUTION_FPS": "7",
        ])
        #expect(enabled.isEnabled == true)
        #expect(enabled.businessTermsAuthorized == true)
        #expect(enabled.accessToken == "ephemeral")
        #expect(enabled.fullResolutionFramerate == 7)
    }

    @Test @MainActor
    func successfulExportAttachesByteExactArchiveAndConservativeBindings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("niantic-augmentation-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = FakeNianticScanningBackend()
        let service = NianticScanAugmentationService(
            backend: backend,
            config: enabledConfig(),
            liDARAvailable: { true }
        )

        service.beginIfAvailable(arSession: ARSession(), identity: identity())
        service.noteFrame()
        service.noteFrame()
        await service.finishAndAttach(to: root)

        #expect(backend.beginCalls == 1)
        #expect(backend.noteCalls == 2)
        #expect(backend.profile?.generateDepthsIfLidarUnavailable == false)
        #expect(backend.profile?.recordAllSensors == false)
        #expect(service.lastOutcome == .exported(archiveCount: 1))

        let nsdk = root.appendingPathComponent("nsdk")
        let manifestData = try Data(contentsOf: nsdk.appendingPathComponent("archive_manifest.json"))
        let manifest = try JSONDecoder.snakeCaseISO8601.decode(NianticArchiveManifest.self, from: manifestData)
        #expect(manifest.status == "exported")
        #expect(manifest.canonicalCaptureAuthority == false)
        #expect(manifest.archiveInspectionStatus.contains("required"))
        let entry = try #require(manifest.export?.archives.first)
        let archive = root.appendingPathComponent(entry.file)
        let archiveData = try Data(contentsOf: archive)
        #expect(archiveData == Data("fixture-nsdk-archive".utf8))
        #expect(entry.sha256 == SHA256.hash(data: archiveData).map {
            String(format: "%02x", $0)
        }.joined())

        let bindingData = try Data(contentsOf: nsdk.appendingPathComponent("reconstruction_binding.json"))
        let binding = try JSONDecoder.snakeCaseISO8601.decode(NianticReconstructionBinding.self, from: bindingData)
        #expect(binding.alignmentStatus.contains("unverified"))
        #expect(binding.timeBinding.status.contains("unverified"))
        #expect(binding.claimBoundaries.contains("vendor_archive_is_not_canonical_capture_truth"))
        #expect(binding.expectedDerivedAssets.map(\.provider) == [
            "postshot_primary",
            "nerfstudio_splatfacto_comparison",
        ])
        #expect(binding.claimBoundaries.contains(
            "no_niantic_reconstruction_endpoint_or_quality_advantage_is_assumed"
        ))
    }

    @Test @MainActor
    func missingTermsAttestationDoesNotStartVendorRecorder() {
        let backend = FakeNianticScanningBackend()
        let service = NianticScanAugmentationService(
            backend: backend,
            config: NianticScanAugmentationConfig(
                isEnabled: true,
                businessTermsAuthorized: false,
                accessToken: "token",
                minimumFreeDiskBytes: 0
            ),
            liDARAvailable: { true }
        )

        service.beginIfAvailable(arSession: ARSession(), identity: identity())

        #expect(backend.beginCalls == 0)
        #expect(service.lastOutcome == .notAttempted(reason: "business_terms_not_authorized"))
    }

    @Test @MainActor
    func exportFailureLeavesAnExplicitFailureRecordAndNoArchive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("niantic-augmentation-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = FakeNianticScanningBackend()
        backend.exportError = NianticScanningBackendError.exportFailed("fixture-failure")
        let service = NianticScanAugmentationService(
            backend: backend,
            config: enabledConfig(),
            liDARAvailable: { true }
        )

        service.beginIfAvailable(arSession: ARSession(), identity: identity())
        service.noteFrame()
        await service.finishAndAttach(to: root)

        let nsdk = root.appendingPathComponent("nsdk")
        let data = try Data(contentsOf: nsdk.appendingPathComponent("archive_manifest.json"))
        let manifest = try JSONDecoder.snakeCaseISO8601.decode(NianticArchiveManifest.self, from: data)
        #expect(manifest.status == "failed")
        #expect(manifest.failureReason?.contains("fixture-failure") == true)
        #expect(FileManager.default.fileExists(atPath: nsdk.appendingPathComponent("archives").path) == false)
        #expect(FileManager.default.fileExists(atPath: nsdk.appendingPathComponent("reconstruction_binding.json").path) == false)
    }
}

private extension JSONDecoder {
    static var snakeCaseISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
