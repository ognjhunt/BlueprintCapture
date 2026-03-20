import Foundation
import Testing
@testable import BlueprintCapture

struct PipelineContractTests {

    @Test
    func pipelinePoseRowIncludesLegacyAndBridgeFields() throws {
        let transform: [[Double]] = [
            [1, 0, 0, 0.1],
            [0, 1, 0, 0.2],
            [0, 0, 1, 0.3],
            [0, 0, 0, 1.0]
        ]
        let row = VideoCaptureManager.PipelinePoseRow(
            pose_schema_version: VideoCaptureManager.poseSchemaVersion,
            frameIndex: 0,
            timestamp: 123.456,
            transform: transform,
            frame_id: "000001",
            t_device_sec: 0.0,
            t_monotonic_ns: 123_456_000_000,
            T_world_camera: transform,
            tracking_state: "normal",
            tracking_reason: nil,
            world_mapping_status: "mapped",
            coordinate_frame_session_id: "cfs-1"
        )

        let data = try JSONEncoder().encode(row)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let json = try #require(jsonObject as? [String: Any])

        #expect(json["pose_schema_version"] as? String == "3.0")
        #expect(json["frame_index"] as? Int == 0)
        #expect(json["timestamp"] as? Double == 123.456)
        #expect(json["frame_id"] as? String == "000001")
        #expect(json["t_device_sec"] as? Double == 0.0)
        #expect((json["t_monotonic_ns"] as? NSNumber)?.int64Value == 123_456_000_000)
        #expect((json["transform"] as? [[Double]])?.count == 4)
        #expect((json["T_world_camera"] as? [[Double]])?.count == 4)
    }

    @Test
    func deviceTimeSecondsIsRelativeAndMonotonic() {
        let t0 = VideoCaptureManager.deviceTimeSeconds(frameTimestamp: 100.0, firstFrameTimestamp: 100.0)
        let t1 = VideoCaptureManager.deviceTimeSeconds(frameTimestamp: 100.033, firstFrameTimestamp: 100.0)
        let t2 = VideoCaptureManager.deviceTimeSeconds(frameTimestamp: 100.066, firstFrameTimestamp: 100.0)

        #expect(t0 == 0.0)
        #expect(t1 > t0)
        #expect(t2 > t1)
    }

    @Test
    func captureManifestSchemaConstantsAreStable() {
        #expect(VideoCaptureManager.captureSchemaVersion == "3.0.0")
        #expect(VideoCaptureManager.captureSource == "iphone")
        #expect(VideoCaptureManager.captureTierHint == "tier1_iphone")
    }

    @Test
    func captureRightsDefaultsStayConservative() {
        let rights = CaptureRightsMetadata()

        #expect(rights.derivedSceneGenerationAllowed == false)
        #expect(rights.dataLicensingAllowed == false)
        #expect(rights.payoutEligible == false)
        #expect(rights.consentStatus == .unknown)
        #expect(rights.permissionDocumentURI == nil)
        #expect(rights.consentScope.isEmpty)
        #expect(rights.consentNotes.isEmpty)
    }
}
