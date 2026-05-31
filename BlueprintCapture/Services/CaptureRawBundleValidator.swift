import Foundation

struct CaptureRawBundleValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Validates the raw capture bundle on disk against the V3/V3.1 contract before finalization.
    /// Returns a list of failure reasons; empty means the bundle passes.
    func validate(in directory: URL) -> [String] {
        var reasons: [String] = []

        let movURL = directory.appendingPathComponent("walkthrough.mov")
        let mp4URL = directory.appendingPathComponent("walkthrough.mp4")
        if !fileManager.fileExists(atPath: movURL.path) && !fileManager.fileExists(atPath: mp4URL.path) {
            reasons.append("missing_walkthrough_video")
        }

        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            reasons.append("missing_or_unreadable_manifest")
            return reasons
        }

        if (manifest["scene_id"] as? String)?.isEmpty != false {
            reasons.append("missing_scene_id")
        }
        if (manifest["capture_id"] as? String)?.isEmpty != false {
            reasons.append("missing_capture_id")
        }
        if (manifest["video_uri"] as? String)?.isEmpty != false {
            reasons.append("missing_video_uri")
        }
        if manifest["capture_start_epoch_ms"] as? Double == nil,
           manifest["capture_start_epoch_ms"] as? Int == nil {
            reasons.append("missing_capture_start_epoch_ms")
        }
        if manifest["fps_source"] as? Double == nil {
            reasons.append("missing_fps_source")
        }
        if manifest["width"] as? Int == nil {
            reasons.append("missing_width")
        }
        if manifest["height"] as? Int == nil {
            reasons.append("missing_height")
        }

        // V3.1 additive fields remain soft during alpha; finalization still writes them.
        if (manifest["capture_profile_id"] as? String)?.isEmpty != false {
            // Not blocking in alpha; will become required after alpha.
        }
        if manifest["capture_capabilities"] as? [String: Any] == nil {
            // Not blocking in alpha; will become required after alpha.
        }

        let rightsURL = directory.appendingPathComponent("rights_consent.json")
        if !fileManager.fileExists(atPath: rightsURL.path) {
            reasons.append("missing_rights_consent")
        }

        for sidecar in Self.requiredSidecars {
            let sidecarURL = directory.appendingPathComponent(sidecar)
            if !fileManager.fileExists(atPath: sidecarURL.path) {
                reasons.append("missing_sidecar_\(sidecar.replacingOccurrences(of: ".", with: "_"))")
            }
        }

        return reasons
    }

    private static let requiredSidecars = [
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
        "semantic_anchor_observations.jsonl"
    ]
}
