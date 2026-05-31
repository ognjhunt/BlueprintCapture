import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureRawBundleValidatorTests {

    @Test
    func acceptsMaterializedBundleWithRequiredFinalizationSidecars() throws {
        let root = try makeBundleRoot()

        let reasons = CaptureRawBundleValidator().validate(in: root)

        #expect(reasons.isEmpty)
    }

    @Test
    func rejectsMissingVideoManifestIdentityAndFinalizationSidecars() throws {
        let root = try makeBundleRoot(includeVideo: false, includeManifest: false)
        try FileManager.default.removeItem(at: root.appendingPathComponent("rights_consent.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("capture_context.json"))

        let reasons = CaptureRawBundleValidator().validate(in: root)

        #expect(reasons.contains("missing_walkthrough_video"))
        #expect(reasons.contains("missing_or_unreadable_manifest"))
        #expect(!reasons.contains("missing_sidecar_capture_context_json"))
    }

    @Test
    func preservesExistingRequiredSidecarReasonNames() throws {
        let root = try makeBundleRoot()
        try FileManager.default.removeItem(at: root.appendingPathComponent("hashes.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("sync_map.jsonl"))

        let reasons = CaptureRawBundleValidator().validate(in: root)

        #expect(reasons.contains("missing_sidecar_hashes_json"))
        #expect(reasons.contains("missing_sidecar_sync_map_jsonl"))
    }

    private func makeBundleRoot(includeVideo: Bool = true, includeManifest: Bool = true) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("raw-bundle-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if includeVideo {
            try Data([0x01]).write(to: root.appendingPathComponent("walkthrough.mov"))
        }

        if includeManifest {
            let manifest: [String: Any] = [
                "scene_id": "scene-1",
                "capture_id": "capture-1",
                "video_uri": "raw/walkthrough.mov",
                "capture_start_epoch_ms": 1_700_000_000_000,
                "fps_source": 30.0,
                "width": 1920,
                "height": 1080,
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest)
            try data.write(to: root.appendingPathComponent("manifest.json"))
        }

        for filename in requiredSidecarFilenames + ["rights_consent.json"] {
            try Data("{}".utf8).write(to: root.appendingPathComponent(filename))
        }

        return root
    }

    private var requiredSidecarFilenames: [String] {
        [
            "provenance.json",
            "capture_context.json",
            "intake_packet.json",
            "task_hypothesis.json",
            "recording_session.json",
            "capture_topology.json",
            "route_anchors.json",
            "checkpoint_events.json",
            "relocalization_events.json",
            "overlap_graph.json",
            "video_track.json",
            "hashes.json",
            "sync_map.jsonl",
            "motion.jsonl",
            "semantic_anchor_observations.jsonl",
        ]
    }
}
