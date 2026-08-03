import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Contract checks for the provider-neutral retained RGB observation registry.
///
/// This manifest is capture truth plus deterministic addressing only. It never
/// selects a reconstruction provider, authorizes a third-party upload, or
/// qualifies an observation for a task/site decision.
enum CaptureDownstreamCandidateManifest {
    static let filename = "downstream_candidate_manifest.json"
    static let schemaVersion = "downstream_candidate_manifest.v1"

    static func canonicalDigest(of value: [String: Any], excludingDigest: Bool = false) -> String? {
        var payload = value
        if excludingDigest {
            payload.removeValue(forKey: "manifest_digest")
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "base64:" + data.base64EncodedString()
        #endif
    }

    static func validationErrors(
        manifest: [String: Any]?,
        syncRows: [[String: Any]],
        expectedVideoURI: String?,
        expectedCoordinateFrameSessionId: String?,
        rightsConsent: [String: Any]?
    ) -> [String] {
        guard let manifest else {
            return ["downstream_candidate_manifest_missing"]
        }

        var errors: [String] = []
        if manifest["schema_version"] as? String != schemaVersion {
            errors.append("downstream_candidate_manifest_schema_invalid")
        }
        let suppliedDigest = manifest["manifest_digest"] as? String
        if suppliedDigest == nil
            || suppliedDigest != canonicalDigest(of: manifest, excludingDigest: true) {
            errors.append("downstream_candidate_manifest_digest_mismatch")
        }
        if let expectedVideoURI,
           manifest["source_video_uri"] as? String != expectedVideoURI {
            errors.append("downstream_candidate_source_video_mismatch")
        }
        if let expectedCoordinateFrameSessionId,
           manifest["coordinate_frame_session_id"] as? String
            != expectedCoordinateFrameSessionId {
            errors.append("downstream_candidate_coordinate_frame_mismatch")
        }
        let sourceVideoDigest = manifest["source_video_sha256"] as? String ?? ""
        if sourceVideoDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
            errors.append("downstream_candidate_source_video_digest_invalid")
        }

        let neutrality = manifest["provider_neutrality"] as? [String: Any]
        if neutrality?["mobile_app_direct_provider_upload_allowed"] as? Bool != false {
            errors.append("downstream_candidate_mobile_provider_upload_not_denied")
        }
        if neutrality?["third_party_provider_upload_authorized"] as? Bool != false {
            errors.append("downstream_candidate_third_party_upload_not_denied")
        }
        if neutrality?["provider_selection_authority"] as? String != "blueprint_pipeline" {
            errors.append("downstream_candidate_provider_authority_invalid")
        }
        if neutrality?["provider_selected"] is String {
            errors.append("downstream_candidate_provider_selection_forbidden")
        }

        let allowedUse = manifest["allowed_use_scope"] as? [String: Any]
        let derivedAllowed = rightsConsent?["derived_scene_generation_allowed"] as? Bool == true
        if allowedUse?["derived_processing_allowed"] as? Bool != derivedAllowed {
            errors.append("downstream_candidate_rights_binding_mismatch")
        }
        if allowedUse?["latest_revocation_check_required"] as? Bool != true {
            errors.append("downstream_candidate_revocation_check_missing")
        }
        if allowedUse?["redaction_required_before_derived_use"] as? Bool
            != (rightsConsent?["redaction_required"] as? Bool ?? true) {
            errors.append("downstream_candidate_redaction_binding_mismatch")
        }

        guard let candidates = manifest["candidates"] as? [[String: Any]] else {
            errors.append("downstream_candidate_rows_missing")
            return errors
        }
        if candidates.count != syncRows.count {
            errors.append("downstream_candidate_count_mismatch")
        }
        if (manifest["candidate_count"] as? NSNumber)?.intValue != candidates.count {
            errors.append("downstream_candidate_declared_count_mismatch")
        }

        var candidateIds = Set<String>()
        var imagePaths = Set<String>()
        let tolerance = 0.000_1
        for (ordinal, candidate) in candidates.enumerated() {
            let candidateId = candidate["candidate_id"] as? String ?? ""
            if candidateId.isEmpty || !candidateIds.insert(candidateId).inserted {
                errors.append("downstream_candidate_id_invalid:\(ordinal)")
            }
            let imagePath = candidate["output_image_relative_path"] as? String ?? ""
            if !isSafeRelativePath(imagePath) || !imagePaths.insert(imagePath).inserted {
                errors.append("downstream_candidate_output_path_invalid:\(ordinal)")
            }
            guard ordinal < syncRows.count else { continue }
            let sync = syncRows[ordinal]
            if number(candidate["decoded_frame_ordinal"])?.intValue != ordinal
                || number(candidate["encoded_frame_index"])?.intValue != ordinal {
                errors.append("downstream_candidate_ordinal_invalid:\(ordinal)")
            }
            if candidate["frame_id"] as? String != sync["frame_id"] as? String
                || candidate["pose_frame_id"] as? String != sync["pose_frame_id"] as? String {
                errors.append("downstream_candidate_frame_binding_mismatch:\(ordinal)")
            }
            if number(candidate["write_attempt_index"])?.intValue
                != number(sync["write_attempt_index"])?.intValue {
                errors.append("downstream_candidate_attempt_binding_mismatch:\(ordinal)")
            }
            for (candidateKey, syncKey) in [
                ("decoded_pts_sec", "t_video_sec"),
                ("decoded_source_pts_sec", "decoded_source_pts_sec"),
                ("t_capture_sec", "t_capture_sec"),
            ] {
                guard let candidateValue = number(candidate[candidateKey])?.doubleValue,
                      let syncValue = number(sync[syncKey])?.doubleValue,
                      abs(candidateValue - syncValue) <= tolerance else {
                    errors.append("downstream_candidate_time_binding_mismatch:\(ordinal):\(candidateKey)")
                    continue
                }
            }
            if let expectedCoordinateFrameSessionId,
               candidate["coordinate_frame_session_id"] as? String
                != expectedCoordinateFrameSessionId {
                errors.append("downstream_candidate_row_coordinate_frame_mismatch:\(ordinal)")
            }
            if !isValidTransformMatrix(candidate["T_site_camera"])
                || !isValidTransformMatrix(candidate["T_world_camera"])
                || !matricesEqual(candidate["T_site_camera"], candidate["T_world_camera"]) {
                errors.append("downstream_candidate_camera_to_site_transform_invalid:\(ordinal)")
            }
            let trackingState = candidate["tracking_state"] as? String ?? "unknown"
            let relocalization = candidate["relocalization_event"] as? Bool ?? false
            let expectedPoseEligibility = trackingState == "normal" && !relocalization
            if candidate["pose_assisted_eligible"] as? Bool != expectedPoseEligibility {
                errors.append("downstream_candidate_pose_eligibility_invalid:\(ordinal)")
            }
            guard let intrinsics = candidate["camera_intrinsics"] as? [String: Any],
                  ["fx", "fy", "width", "height"].allSatisfy({
                    (number(intrinsics[$0])?.doubleValue ?? 0) > 0
                  }),
                  ["cx", "cy"].allSatisfy({ number(intrinsics[$0]) != nil }) else {
                errors.append("downstream_candidate_intrinsics_invalid:\(ordinal)")
                continue
            }
        }
        return errors
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\") else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func isValidTransformMatrix(_ value: Any?) -> Bool {
        guard let rows = value as? [[NSNumber]], rows.count == 4 else { return false }
        return rows.allSatisfy { row in
            row.count == 4 && row.allSatisfy { $0.doubleValue.isFinite }
        }
    }

    private static func matricesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let left = lhs as? [[NSNumber]], let right = rhs as? [[NSNumber]],
              left.count == right.count else { return false }
        return zip(left, right).allSatisfy { leftRow, rightRow in
            leftRow.count == rightRow.count && zip(leftRow, rightRow).allSatisfy {
                abs($0.0.doubleValue - $0.1.doubleValue) <= 0.000_001
            }
        }
    }
}
