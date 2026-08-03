import Foundation

// SDK-neutral value types for the optional Niantic NSDK recording wrapper.
//
// Blueprint's V3.2 ARKit bundle remains capture truth. NSDK reads the same live
// ARSession, but it is allowed to decimate, recompress, transform, or omit samples.
// Its export is therefore supplemental vendor evidence until the archive is
// inspected and aligned back to the canonical ARKit/video timing contract.

enum NianticScanningAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

struct NianticScanAugmentationConfig: Equatable {
    /// Fail closed. Enabling a third-party recorder is an explicit operational choice.
    let isEnabled: Bool
    /// Operator attestation that the applicable Niantic Business and Developer
    /// Terms and the capture's privacy/consent scope authorize this use.
    let businessTermsAuthorized: Bool
    /// Development-only access token. Production must inject a short-lived token
    /// returned by Blueprint's backend; this value is never read from Info.plist.
    let accessToken: String?
    /// Individual images retain the vendor frame records without another video PTS
    /// layer and are the quality-first default. Video remains available for storage.
    let exportAsVideo: Bool
    /// Limit this first integration to the iPhone Pro/LiDAR lane. NSDK-estimated
    /// depth is deliberately not substituted for platform depth.
    let requiresLiDAR: Bool
    /// NSDK's general scan recording cadence.
    let scanFramerate: Int
    /// Whether NSDK also stores the full camera resolution rather than only 720x540.
    let enableFullResolution: Bool
    /// Full-resolution JPEG cadence. Five FPS is intentionally conservative until
    /// device canaries prove higher rates do not reduce Blueprint V3.2 retention.
    let fullResolutionFramerate: Int
    /// Ceiling for the vendor archive export after a capture stops.
    let exportTimeoutSeconds: Double
    /// Ceiling for the vendor save-scan step after a capture stops.
    let saveTimeoutSeconds: Double
    /// Free-disk floor below which augmentation is skipped so the canonical
    /// capture never competes with the vendor scan store for space.
    let minimumFreeDiskBytes: Int64

    static let defaultExportTimeoutSeconds: Double = 300
    static let defaultSaveTimeoutSeconds: Double = 30
    static let defaultMinimumFreeDiskBytes: Int64 = 10 * 1024 * 1024 * 1024
    static let defaultScanFramerate = 30
    static let defaultFullResolutionFramerate = 5

    init(
        isEnabled: Bool = false,
        businessTermsAuthorized: Bool = false,
        accessToken: String? = nil,
        exportAsVideo: Bool = false,
        requiresLiDAR: Bool = true,
        scanFramerate: Int = NianticScanAugmentationConfig.defaultScanFramerate,
        enableFullResolution: Bool = true,
        fullResolutionFramerate: Int = NianticScanAugmentationConfig.defaultFullResolutionFramerate,
        exportTimeoutSeconds: Double = NianticScanAugmentationConfig.defaultExportTimeoutSeconds,
        saveTimeoutSeconds: Double = NianticScanAugmentationConfig.defaultSaveTimeoutSeconds,
        minimumFreeDiskBytes: Int64 = NianticScanAugmentationConfig.defaultMinimumFreeDiskBytes
    ) {
        self.isEnabled = isEnabled
        self.businessTermsAuthorized = businessTermsAuthorized
        self.accessToken = accessToken
        self.exportAsVideo = exportAsVideo
        self.requiresLiDAR = requiresLiDAR
        self.scanFramerate = min(max(scanFramerate, 1), 60)
        self.enableFullResolution = enableFullResolution
        self.fullResolutionFramerate = min(max(fullResolutionFramerate, 1), 60)
        self.exportTimeoutSeconds = exportTimeoutSeconds
        self.saveTimeoutSeconds = saveTimeoutSeconds
        self.minimumFreeDiskBytes = minimumFreeDiskBytes
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NianticScanAugmentationConfig {
        return NianticScanAugmentationConfig(
            isEnabled: boolValue(
                environment["BLUEPRINT_ENABLE_NIANTIC_SCAN_AUGMENTATION"],
                defaultValue: false
            ),
            businessTermsAuthorized: boolValue(
                environment["BLUEPRINT_NIANTIC_BUSINESS_TERMS_AUTHORIZED"],
                defaultValue: false
            ),
            accessToken: trimmed(environment["BLUEPRINT_NIANTIC_ACCESS_TOKEN"]),
            exportAsVideo: boolValue(
                environment["BLUEPRINT_NIANTIC_EXPORT_AS_VIDEO"],
                defaultValue: false
            ),
            requiresLiDAR: boolValue(
                environment["BLUEPRINT_NIANTIC_REQUIRE_LIDAR"],
                defaultValue: true
            ),
            scanFramerate: intValue(
                environment["BLUEPRINT_NIANTIC_SCAN_FPS"],
                defaultValue: defaultScanFramerate
            ),
            enableFullResolution: boolValue(
                environment["BLUEPRINT_NIANTIC_ENABLE_FULL_RESOLUTION"],
                defaultValue: true
            ),
            fullResolutionFramerate: intValue(
                environment["BLUEPRINT_NIANTIC_FULL_RESOLUTION_FPS"],
                defaultValue: defaultFullResolutionFramerate
            ),
            exportTimeoutSeconds: doubleValue(
                environment["BLUEPRINT_NIANTIC_EXPORT_TIMEOUT_SECONDS"],
                defaultValue: defaultExportTimeoutSeconds
            ),
            saveTimeoutSeconds: doubleValue(
                environment["BLUEPRINT_NIANTIC_SAVE_TIMEOUT_SECONDS"],
                defaultValue: defaultSaveTimeoutSeconds
            ),
            minimumFreeDiskBytes: int64Value(
                environment["BLUEPRINT_NIANTIC_MINIMUM_FREE_DISK_BYTES"],
                defaultValue: defaultMinimumFreeDiskBytes
            )
        )
    }

    private static func boolValue(_ raw: String?, defaultValue: Bool) -> Bool {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return defaultValue }
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func doubleValue(_ raw: String?, defaultValue: Double) -> Double {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(raw), value > 0 else { return defaultValue }
        return value
    }

    private static func int64Value(_ raw: String?, defaultValue: Int64) -> Int64 {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int64(raw), value >= 0 else { return defaultValue }
        return value
    }

    private static func intValue(_ raw: String?, defaultValue: Int) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(raw), value > 0 else { return defaultValue }
        return value
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct NianticScanRecordingProfile: Codable, Equatable {
    let scanFramerate: Int
    let enableFullResolution: Bool
    let fullResolutionFramerate: Int
    // Use conventional `Lidar` casing here so Foundation's snake-case key
    // strategies round-trip this field as `generate_depths_if_lidar_unavailable`.
    // The `LiDAR` acronym spelling would encode and decode to different Swift
    // property names (`li_dar` versus `lidar`).
    let generateDepthsIfLidarUnavailable: Bool
    let recordAllSensors: Bool

    init(config: NianticScanAugmentationConfig) {
        scanFramerate = config.scanFramerate
        enableFullResolution = config.enableFullResolution
        fullResolutionFramerate = config.fullResolutionFramerate
        generateDepthsIfLidarUnavailable = false
        recordAllSensors = false
    }
}

/// Identity available at recording time. `scene_id`/`capture_id` are assigned at
/// finalize/upload; the vendor sidecars bind through `coordinate_frame_session_id`
/// and the capture base filename, both of which the enclosing bundle's manifest and
/// hashes.json tie to the final identity.
struct NianticScanCaptureIdentity: Equatable {
    let captureBaseFilename: String
    let coordinateFrameSessionId: String
    let startedAt: Date
    let appVersion: String
    let appBuild: String

    var exportUserData: [String: String] {
        [
            "blueprint_binding_schema": "blueprint_nsdk_export_binding.v1",
            "blueprint_capture_base_filename": captureBaseFilename,
            "blueprint_coordinate_frame_session_id": coordinateFrameSessionId,
            "blueprint_capture_started_at": ISO8601DateFormatter().string(from: startedAt),
            "blueprint_app_version": appVersion,
            "blueprint_app_build": appBuild,
        ]
    }
}

struct NianticSavedScanInfo: Equatable {
    let scanId: String
    let scanDirectoryURL: URL
}

enum NianticScanningBackendError: LocalizedError, Equatable {
    case sdkUnavailable(reason: String)
    case configurationFailed(String)
    case noFramesRecorded
    case saveFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable(let reason):
            return "Niantic SDK unavailable: \(reason)"
        case .configurationFailed(let message):
            return "Niantic scan configuration failed: \(message)"
        case .noFramesRecorded:
            return "Niantic scan recorded no frames."
        case .saveFailed(let message):
            return "Niantic scan save failed: \(message)"
        case .exportFailed(let message):
            return "Niantic scan export failed: \(message)"
        }
    }
}

// MARK: - Sidecar payloads (raw/nsdk/*)

/// Written to `raw/nsdk/archive_manifest.json`. Present whenever augmentation was
/// attempted; `status` records the truthful outcome. Archives are preserved
/// byte-exact and covered by the bundle's `hashes.json` like every other file.
struct NianticArchiveManifest: Codable, Equatable {
    struct ArchiveEntry: Codable, Equatable {
        let index: Int
        let file: String
        let sha256: String
        let sizeBytes: Int64
    }

    struct ExportRecord: Codable, Equatable {
        let exportAsVideo: Bool
        let startedAt: Date
        let completedAt: Date
        let durationSec: Double
        let archives: [ArchiveEntry]
    }

    let schemaVersion: String
    let status: String
    let vendor: String
    let sdkProduct: String
    let sdkVersion: String?
    let evidenceClass: String
    let authority: String
    let scanId: String?
    let coordinateFrameSessionId: String
    let captureBaseFilename: String
    let captureStartedAt: Date
    let recordedFrameCountReported: Int?
    let recordingProfile: NianticScanRecordingProfile
    let businessTermsAuthorization: String
    let canonicalCaptureAuthority: Bool
    let archiveInspectionStatus: String
    let export: ExportRecord?
    let failureReason: String?

    static let schemaVersionValue = "v1"
    static let statusExported = "exported"
    static let statusFailed = "failed"
    static let vendorValue = "niantic_spatial"
    static let sdkProductValue = "niantic_spatial_sdk_swift"
    static let evidenceClassValue = "concurrent_vendor_recording_same_arsession"
    static let authorityValue = "supplemental_vendor_recording_not_canonical"
}

/// Written to `raw/nsdk/reconstruction_binding.json` on successful export.
/// Declares the conservative relationship between a vendor archive and the
/// canonical reconstruction campaign. The archive is not trainer input unless a
/// later measured experiment explicitly admits it.
struct NianticReconstructionBinding: Codable, Equatable {
    struct TimeBinding: Codable, Equatable {
        let vendorClock: String
        let canonicalClock: String
        let candidateJoin: String
        let requiredValidation: [String]
        let status: String
    }

    struct MetricAuthority: Codable, Equatable {
        let trajectory: String
        let intrinsics: String
        let depth: String
        let units: String
        let handedness: String
        let worldFrameDefinition: String
    }

    struct ExpectedDerivedAsset: Codable, Equatable {
        let provider: String
        let kinds: [String]
        let importRoute: String
    }

    let schemaVersion: String
    let bindingKind: String
    let coordinateFrameSessionId: String
    let captureBaseFilename: String
    let nsdkScanId: String
    let timeBinding: TimeBinding
    let metricAuthority: MetricAuthority
    let vendorDepthSource: String
    let expectedDerivedAssets: [ExpectedDerivedAsset]
    let alignmentExpectation: String
    let alignmentStatus: String
    let claimBoundaries: [String]

    static let schemaVersionValue = "v1"
    static let bindingKindValue = "same_arkit_session_identity"

    static func make(
        identity: NianticScanCaptureIdentity,
        scanId: String
    ) -> NianticReconstructionBinding {
        NianticReconstructionBinding(
            schemaVersion: schemaVersionValue,
            bindingKind: bindingKindValue,
            coordinateFrameSessionId: identity.coordinateFrameSessionId,
            captureBaseFilename: identity.captureBaseFilename,
            nsdkScanId: scanId,
            timeBinding: TimeBinding(
                vendorClock: "inspect_nsdk_archive_capture_json_frame_timestamp",
                canonicalClock: "arkit/frames.jsonl.timestamp_then_frame_id_to_sync_map.jsonl",
                candidateJoin: "nearest_timestamp_after_archive_clock_normalization",
                requiredValidation: [
                    "vendor_frame_timestamps_are_monotonic",
                    "vendor_timestamp_domain_is_identified_from_exported_capture_json",
                    "nearest_arkit_frame_residual_is_reported_not_assumed",
                    "canonical_video_binding_uses_only_retained_sync_map_rows",
                ],
                status: "unverified_until_archive_inspection"
            ),
            metricAuthority: MetricAuthority(
                trajectory: "arkit/poses.jsonl",
                intrinsics: "arkit/session_intrinsics.json",
                depth: "arkit/depth_manifest.json",
                units: "meters",
                handedness: "right_handed",
                worldFrameDefinition: "arkit_world_origin_at_session_start"
            ),
            vendorDepthSource: "arkit_scene_depth",
            expectedDerivedAssets: [
                ExpectedDerivedAsset(
                    provider: "postshot_primary",
                    kinds: ["splat_ply"],
                    importRoute: "pipeline canonical_v32_3dgs_execution_plan.v1 using the canonical candidate-only COLMAP dataset"
                ),
                ExpectedDerivedAsset(
                    provider: "nerfstudio_splatfacto_comparison",
                    kinds: ["splat_ply"],
                    importRoute: "pipeline canonical_v32_3dgs_execution_plan.v1 using the byte-identical canonical candidate-only COLMAP dataset"
                ),
            ],
            alignmentExpectation: "candidate_identity_from_shared_arkit_input_after_coordinate_convention_validation",
            alignmentStatus: "unverified_until_pose_residual_and_axis_checks_pass",
            claimBoundaries: [
                "vendor_archive_is_not_canonical_capture_truth",
                "shared_arsession_does_not_prove_identical_retained_frame_sets",
                "vendor_pose_serialization_may_use_a_different_coordinate_convention",
                "vendor_archive_is_not_reconstruction_input_without_separate_admission",
                "no_niantic_reconstruction_endpoint_or_quality_advantage_is_assumed",
                "derived_reconstructions_are_support_assets_not_raw_evidence",
                "no_metric_scale_collision_or_simulation_claims_without_pipeline_gates",
            ]
        )
    }
}

enum NianticScanSidecarLayout {
    static let directoryName = "nsdk"
    static let archivesDirectoryName = "archives"
    static let archiveManifestFilename = "archive_manifest.json"
    static let reconstructionBindingFilename = "reconstruction_binding.json"

    static func archiveFilename(index: Int) -> String {
        String(format: "nsdk_scan_archive_%03d.tgz", index)
    }
}
