import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(JavaScriptCore)
import JavaScriptCore
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
              let canonical = canonicalJSON(payload),
              let data = canonical.data(using: .utf8) else {
            return nil
        }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "base64:" + data.base64EncodedString()
        #endif
    }

    /// Match the production bridge's canonical JSON byte-for-byte.
    ///
    /// Foundation and ECMAScript serialize finite floating-point values
    /// differently (for example `1e-8` and negative zero). The bridge uses
    /// `JSON.stringify` for primitives, so using Foundation's encoder here can
    /// make a truthful ARKit manifest fail its immutable digest check after
    /// upload. JavaScriptCore is an Apple system framework and gives the app the
    /// same primitive serialization as the Node.js consumer without network or
    /// dynamic provider code.
    private static func canonicalJSON(_ value: Any) -> String? {
        #if canImport(JavaScriptCore)
        guard let context = JSContext(),
              let stringify = context
                .objectForKeyedSubscript("JSON")?
                .objectForKeyedSubscript("stringify") else {
            return nil
        }

        func encodePrimitive(_ primitive: Any) -> String? {
            stringify.call(withArguments: [primitive])?.toString()
        }

        func encode(_ item: Any) -> String? {
            if let object = item as? [String: Any] {
                let keys = object.keys.sorted {
                    $0.utf16.lexicographicallyPrecedes($1.utf16)
                }
                var fields: [String] = []
                fields.reserveCapacity(keys.count)
                for key in keys {
                    guard let encodedKey = encodePrimitive(key),
                          let child = object[key],
                          let encodedValue = encode(child) else {
                        return nil
                    }
                    fields.append("\(encodedKey):\(encodedValue)")
                }
                return "{\(fields.joined(separator: ","))}"
            }
            if let array = item as? [Any] {
                var values: [String] = []
                values.reserveCapacity(array.count)
                for child in array {
                    guard let encoded = encode(child) else { return nil }
                    values.append(encoded)
                }
                return "[\(values.joined(separator: ","))]"
            }
            if item is NSNull || item is String || item is NSNumber {
                return encodePrimitive(item)
            }
            return nil
        }

        return encode(value)
        #else
        return nil
        #endif
    }

    static func validationErrors(
        manifest: [String: Any]?,
        syncRows: [[String: Any]],
        frameRows: [[String: Any]],
        poseRows: [[String: Any]],
        expectedVideoURI: String?,
        expectedSourceVideoSHA256: String? = nil,
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
        if let expectedSourceVideoSHA256,
           sourceVideoDigest != expectedSourceVideoSHA256 {
            errors.append("downstream_candidate_source_video_digest_mismatch")
        }
        if manifest["source_video_authority"] as? String
            != "immutable_raw_capture_video" {
            errors.append("downstream_candidate_source_video_authority_invalid")
        }
        if manifest["decoded_timing_authority"] as? String
            != "sync_map_decoded_sample_presentation_timestamps" {
            errors.append("downstream_candidate_timing_authority_invalid")
        }
        if manifest["candidate_order"] as? String != "encoded_frame_index_ascending" {
            errors.append("downstream_candidate_order_invalid")
        }

        let selection = manifest["selection_contract"] as? [String: Any]
        if selection?["selection_authority"] as? String
            != "blueprint_pipeline_task_site_profile"
            || !(selection?["capture_default_selection"] is NSNull)
            || selection?["selection_parameters_required"] as? Bool != true
            || selection?["smallest_missing_input_when_unselectable"] as? String
                != "task_site_evidence_profile_with_frame_selection_parameters" {
            errors.append("downstream_candidate_selection_contract_invalid")
        }
        let expectedSelectors = [
            "explicit_encoded_frame_ordinals",
            "profile_bound_even_decoded_pts_coverage",
            "profile_bound_quality_filter",
        ]
        if selection?["allowed_deterministic_selectors"] as? [String]
            != expectedSelectors {
            errors.append("downstream_candidate_selectors_invalid")
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
        if neutrality?["provider_authorization_status"] as? String
            != "not_granted_by_capture_manifest" {
            errors.append("downstream_candidate_provider_authorization_invalid")
        }
        if neutrality?["provider_selected"] != nil {
            errors.append("downstream_candidate_provider_selection_forbidden")
        }

        let allowedUse = manifest["allowed_use_scope"] as? [String: Any]
        let derivedAllowed = rightsConsent?["derived_scene_generation_allowed"] as? Bool == true
        if allowedUse?["derived_processing_allowed"] as? Bool != derivedAllowed {
            errors.append("downstream_candidate_rights_binding_mismatch")
        }
        let dataLicensingAllowed = rightsConsent?["data_licensing_allowed"] as? Bool == true
        if allowedUse?["data_licensing_allowed"] as? Bool != dataLicensingAllowed {
            errors.append("downstream_candidate_data_licensing_binding_mismatch")
        }
        if allowedUse?["latest_revocation_check_required"] as? Bool != true {
            errors.append("downstream_candidate_revocation_check_missing")
        }
        if allowedUse?["redaction_required_before_derived_use"] as? Bool
            != (rightsConsent?["redaction_required"] as? Bool ?? true) {
            errors.append("downstream_candidate_redaction_binding_mismatch")
        }
        if allowedUse?["raw_observation_indexing_allowed"] as? Bool != true
            || allowedUse?["provider_upload_requires_separate_downstream_authorization"]
                as? Bool != true {
            errors.append("downstream_candidate_use_scope_invalid")
        }

        let claimBoundary = manifest["claim_boundary"] as? [String: Any]
        if claimBoundary?["raw_capture_remains_authoritative"] as? Bool != true
            || claimBoundary?["candidate_manifest_qualifies_reconstruction"] as? Bool
                != false
            || claimBoundary?["candidate_manifest_qualifies_metric_scale"] as? Bool
                != false
            || claimBoundary?["candidate_manifest_qualifies_collision_or_physics"] as? Bool
                != false
            || claimBoundary?["candidate_manifest_proves_task_success"] as? Bool
                != false {
            errors.append("downstream_candidate_claim_boundary_invalid")
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
        let framesById = Dictionary(
            frameRows.compactMap { row in
                (row["frame_id"] as? String).map { ($0, row) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let posesById = Dictionary(
            poseRows.compactMap { row in
                (row["frame_id"] as? String).map { ($0, row) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let frameOrdinals = Dictionary(
            frameRows.enumerated().compactMap { ordinal, row in
                (row["frame_id"] as? String).map { ($0, ordinal) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let poseOrdinals = Dictionary(
            poseRows.enumerated().compactMap { ordinal, row in
                (row["frame_id"] as? String).map { ($0, ordinal) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let tolerance = 0.000_1
        for (ordinal, candidate) in candidates.enumerated() {
            let candidateId = candidate["candidate_id"] as? String ?? ""
            if candidateId != String(format: "rgb_%06d", ordinal)
                || !candidateIds.insert(candidateId).inserted {
                errors.append("downstream_candidate_id_invalid:\(ordinal)")
            }
            let imagePath = candidate["output_image_relative_path"] as? String ?? ""
            if imagePath != String(format: "candidate_rgb/%06d.png", ordinal)
                || !isSafeRelativePath(imagePath)
                || !imagePaths.insert(imagePath).inserted {
                errors.append("downstream_candidate_output_path_invalid:\(ordinal)")
            }
            guard ordinal < syncRows.count else { continue }
            let sync = syncRows[ordinal]
            if number(candidate["decoded_frame_ordinal"])?.intValue != ordinal
                || number(candidate["encoded_frame_index"])?.intValue
                    != number(sync["encoded_frame_index"])?.intValue {
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
            if candidate["source_video_uri"] as? String != expectedVideoURI {
                errors.append("downstream_candidate_row_video_binding_mismatch:\(ordinal)")
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
            if candidate["site_frame_id"] as? String != expectedCoordinateFrameSessionId
                || candidate["site_frame_definition"] as? String
                    != "arkit_world_origin_at_session_start"
                || candidate["transform_semantics"] as? String
                    != "row_major_camera_to_site"
                || candidate["units"] as? String != "meters"
                || candidate["handedness"] as? String != "right_handed"
                || candidate["up_axis"] as? String != "Y"
                || candidate["gravity_aligned"] as? Bool != true {
                errors.append("downstream_candidate_site_frame_semantics_invalid:\(ordinal)")
            }
            if !isValidTransformMatrix(candidate["T_site_camera"])
                || !isValidTransformMatrix(candidate["T_world_camera"])
                || !matricesEqual(candidate["T_site_camera"], candidate["T_world_camera"]) {
                errors.append("downstream_candidate_camera_to_site_transform_invalid:\(ordinal)")
            }
            let frameId = candidate["frame_id"] as? String ?? ""
            let poseFrameId = candidate["pose_frame_id"] as? String ?? ""
            guard let sourceFrame = framesById[frameId],
                  let sourcePose = posesById[poseFrameId] else {
                errors.append("downstream_candidate_source_observation_missing:\(ordinal)")
                continue
            }
            if number(candidate["arkit_frame_row_ordinal"])?.intValue
                != frameOrdinals[frameId]
                || number(candidate["arkit_pose_row_ordinal"])?.intValue
                    != poseOrdinals[poseFrameId] {
                errors.append("downstream_candidate_source_row_ordinal_invalid:\(ordinal)")
            }
            if !matricesEqual(
                candidate["T_site_camera"],
                sourcePose["T_site_camera"] ?? sourcePose["T_world_camera"]
            ) {
                errors.append("downstream_candidate_pose_binding_mismatch:\(ordinal)")
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
            guard let sourceIntrinsics = sourceFrame["intrinsics"] as? [NSNumber],
                  sourceIntrinsics.count == 9,
                  let resolution = sourceFrame["image_resolution"] as? [NSNumber],
                  resolution.count == 2,
                  intrinsics["matrix_column_major"] as? [NSNumber] == sourceIntrinsics,
                  number(intrinsics["width"])?.intValue == resolution[0].intValue,
                  number(intrinsics["height"])?.intValue == resolution[1].intValue,
                  intrinsics["authority"] as? String
                    == "arkit_arframe_exact_per_observation" else {
                errors.append("downstream_candidate_intrinsics_binding_mismatch:\(ordinal)")
                continue
            }
            if candidate["camera_calibration_digest"] as? String
                != canonicalDigest(of: intrinsics) {
                errors.append("downstream_candidate_calibration_digest_invalid:\(ordinal)")
            }
            if candidate["raw_observation_authority"] as? Bool != true
                || candidate["downstream_artifact_authority"] as? Bool != false {
                errors.append("downstream_candidate_row_authority_invalid:\(ordinal)")
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
