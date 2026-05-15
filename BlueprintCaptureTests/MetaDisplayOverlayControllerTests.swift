import Foundation
import Testing
@testable import BlueprintCapture

struct MetaDisplayOverlayControllerTests {

    @Test
    func minimalHudSnapshotPreservesTargetPrivacyTimerAndFrameCount() {
        let target = MetaDisplayTargetMetadata(
            name: "Harborview Grocery Distribution Annex",
            address: "121 Dock St, Durham, NC",
            captureJobId: "job_123",
            privacyReminder: "Capture only approved areas."
        )

        let snapshot = MetaDisplayOverlayController.makeSnapshot(
            target: target,
            captureState: .recording,
            durationSeconds: 73,
            frameCount: 2190,
            advisoryHint: nil,
            deviceWarning: nil,
            uploadStatus: nil,
            supportsActions: true
        )

        #expect(snapshot.targetName == "Harborview Grocery Distribution Annex")
        #expect(snapshot.targetAddress == "121 Dock St, Durham, NC")
        #expect(snapshot.privacyReminder == "Capture only approved areas.")
        #expect(snapshot.captureState == .recording)
        #expect(snapshot.timerText == "1:13")
        #expect(snapshot.frameCount == 2190)
        #expect(snapshot.availableActions == [.pause, .checkpoint, .finish])
    }

    @Test
    func advisoryHintsAreFixedUxTelemetryNotCaptureTruth() {
        #expect(MetaDisplayAdvisoryHint.allCases == [
            .slowDown,
            .holdSteady,
            .turnLeft,
            .turnRight,
            .captureDoorway,
            .scanCorners,
            .finishWhenComplete,
        ])

        let event = MetaDisplayInteractionEvent(
            action: .checkpoint,
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            hudState: .recording,
            advisoryHint: .scanCorners,
            frameCount: 42
        )

        let sidecar = event.sidecarPayload
        #expect(sidecar["truth_scope"] as? String == "ux_telemetry")
        #expect(sidecar["excluded_from_raw_geometry"] as? Bool == true)
        #expect(sidecar["advisory_hint"] as? String == "scan_corners")
    }

    @Test
    func deviceWarningAndUploadStatesStayDisplayOnly() {
        let target = MetaDisplayTargetMetadata(
            name: "Dock A",
            address: "11 Warehouse Way",
            captureJobId: "job_upload",
            privacyReminder: MetaDisplayTargetMetadata.defaultPrivacyReminder
        )

        let snapshot = MetaDisplayOverlayController.makeSnapshot(
            target: target,
            captureState: .uploading,
            durationSeconds: 95,
            frameCount: 2400,
            advisoryHint: .finishWhenComplete,
            deviceWarning: .firmwareUpdateRequired,
            uploadStatus: .uploading(progress: 0.42),
            supportsActions: false
        )

        #expect(snapshot.deviceWarning == .firmwareUpdateRequired)
        #expect(snapshot.uploadStatus == .uploading(progress: 0.42))
        #expect(snapshot.availableActions.isEmpty)
        #expect(snapshot.truthBoundary == "Display HUD and scan coaching are advisory UX telemetry, not raw geometry, pose, depth, coverage, rights, or qualification proof.")
    }

    @Test
    @MainActor
    func snapshotsCoverReadyRecordingPausedUploadingAndDoneStates() {
        let target = MetaDisplayTargetMetadata(
            name: "Dock A",
            address: "11 Warehouse Way",
            captureJobId: "job_state_path"
        )

        let states: [MetaDisplayHUDState] = [.ready, .recording, .paused, .uploading, .done]
        let snapshots = states.map { state in
            MetaDisplayOverlayController.makeSnapshot(
                target: target,
                captureState: state,
                durationSeconds: state == .ready ? 0 : 12,
                frameCount: state == .ready ? 0 : 360,
                advisoryHint: state == .recording ? .holdSteady : nil,
                deviceWarning: nil,
                uploadStatus: state == .uploading ? .queued : nil,
                supportsActions: true
            )
        }

        #expect(snapshots.map(\.captureState) == states)
        #expect(snapshots[0].timerText == "0:00")
        #expect(snapshots[1].availableActions == [.pause, .checkpoint, .finish])
        #expect(snapshots[2].availableActions == [.resume, .checkpoint, .finish])
        #expect(snapshots[3].availableActions.isEmpty)
        #expect(snapshots[4].availableActions.isEmpty)
    }

    @Test
    @MainActor
    func renderQueuesPendingSnapshotUntilDisplayStarts() async {
        let target = MetaDisplayTargetMetadata(
            name: "Dock A",
            address: "11 Warehouse Way",
            captureJobId: "job_pending"
        )
        let ready = MetaDisplayOverlayController.makeSnapshot(
            target: target,
            captureState: .ready,
            durationSeconds: 0,
            frameCount: 0,
            advisoryHint: nil,
            deviceWarning: nil,
            uploadStatus: nil,
            supportsActions: false
        )
        let recording = MetaDisplayOverlayController.makeSnapshot(
            target: target,
            captureState: .recording,
            durationSeconds: 5,
            frameCount: 120,
            advisoryHint: .holdSteady,
            deviceWarning: nil,
            uploadStatus: nil,
            supportsActions: false
        )
        var rendered: [MetaDisplayHUDSnapshot] = []
        let controller = MetaDisplayOverlayController(renderer: { snapshot in
            rendered.append(snapshot)
        })

        await controller.render(ready)
        await controller.render(recording)

        #expect(rendered.isEmpty)
        #expect(controller.pendingSnapshotForTesting == recording)

        await controller.markDisplayStarted()

        #expect(rendered == [recording])
        #expect(controller.pendingSnapshotForTesting == nil)
    }

    @Test
    func warningMappingIncludesUserActionText() {
        #expect(MetaDisplayDeviceWarning.permissionRequired.userActionText == "Grant camera access in Meta AI, then return to BlueprintCapture.")
        #expect(MetaDisplayDeviceWarning.firmwareUpdateRequired.userActionText == "Open the Meta AI firmware update flow before recording.")
        #expect(MetaDisplayDeviceWarning.glassesAppUpdateRequired.userActionText == "Open the Meta AI glasses app update flow before using the display HUD.")
        #expect(MetaDisplayDeviceWarning.batteryCritical.userActionText == "Charge the glasses before continuing.")
    }

    @Test
    func actionsAreOnlyAvailableWhenSdkActionsAreSupported() {
        #expect(MetaDisplayOverlayController.availableActions(for: .recording, supportsActions: false).isEmpty)
        #expect(MetaDisplayOverlayController.availableActions(for: .recording, supportsActions: true) == [.pause, .checkpoint, .finish])
        #expect(MetaDisplayOverlayController.availableActions(for: .paused, supportsActions: true) == [.resume, .checkpoint, .finish])
        #expect(MetaDisplayOverlayController.availableActions(for: .uploading, supportsActions: true).isEmpty)
    }
}
