import Foundation

#if canImport(MWDATDisplay) && !targetEnvironment(simulator)
import MWDATDisplay
#endif

struct MetaDisplayTargetMetadata: Equatable, Sendable {
    static let defaultPrivacyReminder = "Capture only approved areas. Avoid private, restricted, or sensitive content."

    let name: String
    let address: String
    let captureJobId: String
    let captureBrief: String?
    let privacyReminder: String
    let allowedAdvisoryHints: [MetaDisplayAdvisoryHint]

    init(name: String,
         address: String,
         captureJobId: String,
         captureBrief: String? = nil,
         privacyReminder: String = MetaDisplayTargetMetadata.defaultPrivacyReminder,
         allowedAdvisoryHints: [MetaDisplayAdvisoryHint] = MetaDisplayAdvisoryHint.allCases) {
        self.name = name
        self.address = address
        self.captureJobId = captureJobId
        self.captureBrief = captureBrief
        self.privacyReminder = privacyReminder
        self.allowedAdvisoryHints = allowedAdvisoryHints
    }
}

enum MetaDisplayHUDState: String, Equatable, Sendable {
    case ready
    case recording
    case paused
    case uploading
    case done
    case warning
    case error

    var displayLabel: String {
        switch self {
        case .ready:
            return "Ready"
        case .recording:
            return "REC"
        case .paused:
            return "Paused"
        case .uploading:
            return "Uploading"
        case .done:
            return "Done"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}

enum MetaDisplayAdvisoryHint: String, CaseIterable, Equatable, Sendable {
    case slowDown = "slow_down"
    case holdSteady = "hold_steady"
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    case captureDoorway = "capture_doorway"
    case scanCorners = "scan_corners"
    case finishWhenComplete = "finish_when_complete"

    var displayText: String {
        switch self {
        case .slowDown:
            return "Slow down"
        case .holdSteady:
            return "Hold steady"
        case .turnLeft:
            return "Turn left"
        case .turnRight:
            return "Turn right"
        case .captureDoorway:
            return "Capture doorway"
        case .scanCorners:
            return "Scan corners"
        case .finishWhenComplete:
            return "Finish when complete"
        }
    }
}

enum MetaDisplayDeviceWarning: String, Equatable, Sendable {
    case permissionRequired = "permission_required"
    case firmwareUpdateRequired = "firmware_update_required"
    case datAppUpdateRequired = "dat_app_update_required"
    case glassesAppUpdateRequired = "glasses_app_update_required"
    case thermalCritical = "thermal_critical"
    case thermalEmergency = "thermal_emergency"
    case batteryCritical = "battery_critical"
    case peakPowerShutdown = "peak_power_shutdown"

    var displayText: String {
        switch self {
        case .permissionRequired:
            return "Permission required"
        case .firmwareUpdateRequired:
            return "Firmware update required"
        case .datAppUpdateRequired:
            return "DAT app update required"
        case .glassesAppUpdateRequired:
            return "Glasses app update required"
        case .thermalCritical:
            return "Thermal warning"
        case .thermalEmergency:
            return "Thermal emergency"
        case .batteryCritical:
            return "Battery critical"
        case .peakPowerShutdown:
            return "Peak power shutdown"
        }
    }

    var userActionText: String {
        switch self {
        case .permissionRequired:
            return "Grant camera access in Meta AI, then return to BlueprintCapture."
        case .firmwareUpdateRequired:
            return "Open the Meta AI firmware update flow before recording."
        case .datAppUpdateRequired:
            return "Update the Meta AI app, then reconnect the glasses."
        case .glassesAppUpdateRequired:
            return "Open the Meta AI glasses app update flow before using the display HUD."
        case .thermalCritical:
            return "Let the glasses cool before continuing."
        case .thermalEmergency:
            return "Stop capture and let the glasses cool before retrying."
        case .batteryCritical:
            return "Charge the glasses before continuing."
        case .peakPowerShutdown:
            return "Let the glasses recover from peak-power shutdown before retrying."
        }
    }
}

enum MetaDisplayUploadStatus: Equatable, Sendable {
    case queued
    case uploading(progress: Double)
    case done
    case failed(message: String)

    var displayText: String {
        switch self {
        case .queued:
            return "Upload queued"
        case .uploading(let progress):
            return "Uploading \(Int((progress * 100).rounded()))%"
        case .done:
            return "Upload done"
        case .failed:
            return "Upload failed"
        }
    }
}

enum MetaDisplayAction: String, Equatable, Sendable {
    case pause
    case resume
    case finish
    case checkpoint

    var displayLabel: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .finish:
            return "Finish"
        case .checkpoint:
            return "Checkpoint"
        }
    }
}

struct MetaDisplayHUDSnapshot: Equatable, Sendable {
    static let truthBoundary = "Display HUD and scan coaching are advisory UX telemetry, not raw geometry, pose, depth, coverage, rights, or qualification proof."

    let targetName: String
    let targetAddress: String
    let captureJobId: String
    let captureBrief: String?
    let privacyReminder: String
    let captureState: MetaDisplayHUDState
    let timerText: String
    let durationSeconds: Double
    let frameCount: Int
    let advisoryHint: MetaDisplayAdvisoryHint?
    let deviceWarning: MetaDisplayDeviceWarning?
    let uploadStatus: MetaDisplayUploadStatus?
    let availableActions: [MetaDisplayAction]
    let allowedAdvisoryHints: [MetaDisplayAdvisoryHint]
    let truthBoundary: String
}

struct MetaDisplayInteractionEvent: Sendable {
    let action: MetaDisplayAction
    let capturedAt: Date
    let hudState: MetaDisplayHUDState
    let advisoryHint: MetaDisplayAdvisoryHint?
    let frameCount: Int

    var sidecarPayload: [String: Any] {
        var payload: [String: Any] = [
            "schema_version": "meta_display_ux_telemetry_v1",
            "truth_scope": "ux_telemetry",
            "excluded_from_raw_geometry": true,
            "excluded_from_raw_pose": true,
            "excluded_from_raw_depth": true,
            "excluded_from_coverage_truth": true,
            "excluded_from_rights_truth": true,
            "excluded_from_qualification_truth": true,
            "action": action.rawValue,
            "hud_state": hudState.rawValue,
            "frame_count": frameCount,
            "captured_at": ISO8601DateFormatter().string(from: capturedAt),
            "truth_boundary": MetaDisplayHUDSnapshot.truthBoundary,
        ]
        if let advisoryHint {
            payload["advisory_hint"] = advisoryHint.rawValue
        }
        return payload
    }
}

@MainActor
final class MetaDisplayOverlayController {
    typealias ActionHandler = @Sendable (MetaDisplayAction) -> Void
    typealias SnapshotRenderer = @MainActor (MetaDisplayHUDSnapshot) async -> Void

    var onAction: ActionHandler?
    var onSendError: ((String?) -> Void)?

    private let renderer: SnapshotRenderer?
    private(set) var isDisplayStarted: Bool = false
    private(set) var pendingSnapshotForTesting: MetaDisplayHUDSnapshot?

    init(renderer: SnapshotRenderer? = nil) {
        self.renderer = renderer
    }

    #if canImport(MWDATDisplay) && !targetEnvironment(simulator)
    private var display: MWDATDisplay.Display?

    func attachDisplay(_ display: MWDATDisplay.Display) {
        self.display = display
        isDisplayStarted = false
    }

    func startDisplayIfAvailable() async {
        isDisplayStarted = false
        await display?.start()
    }

    func stopDisplayIfAvailable() async {
        isDisplayStarted = false
        pendingSnapshotForTesting = nil
        await display?.stop()
    }
    #else
    func startDisplayIfAvailable() async {
        isDisplayStarted = false
    }

    func stopDisplayIfAvailable() async {
        isDisplayStarted = false
        pendingSnapshotForTesting = nil
    }
    #endif

    func markDisplayStarted() async {
        isDisplayStarted = true
        guard let pending = pendingSnapshotForTesting else { return }
        pendingSnapshotForTesting = nil
        await render(pending)
    }

    func markDisplayStopped() {
        isDisplayStarted = false
    }

    func render(_ snapshot: MetaDisplayHUDSnapshot) async {
        guard isDisplayStarted else {
            pendingSnapshotForTesting = snapshot
            return
        }

        if let renderer {
            await renderer(snapshot)
            onSendError?(nil)
            return
        }

        #if canImport(MWDATDisplay) && !targetEnvironment(simulator)
        guard let display else {
            pendingSnapshotForTesting = snapshot
            return
        }
        do {
            try await display.send(Self.displayRoot(for: snapshot, onAction: onAction))
            onSendError?(nil)
        } catch {
            let message = error.localizedDescription
            onSendError?(message)
            print("[MetaDisplayOverlay] render failed: \(message)")
        }
        #endif
    }

    nonisolated static func makeSnapshot(target: MetaDisplayTargetMetadata,
                                         captureState: MetaDisplayHUDState,
                                         durationSeconds: Double,
                                         frameCount: Int,
                                         advisoryHint: MetaDisplayAdvisoryHint?,
                                         deviceWarning: MetaDisplayDeviceWarning?,
                                         uploadStatus: MetaDisplayUploadStatus?,
                                         supportsActions: Bool) -> MetaDisplayHUDSnapshot {
        MetaDisplayHUDSnapshot(
            targetName: target.name,
            targetAddress: target.address,
            captureJobId: target.captureJobId,
            captureBrief: target.captureBrief,
            privacyReminder: target.privacyReminder,
            captureState: captureState,
            timerText: formatDuration(durationSeconds),
            durationSeconds: durationSeconds,
            frameCount: frameCount,
            advisoryHint: advisoryHint.flatMap { target.allowedAdvisoryHints.contains($0) ? $0 : nil },
            deviceWarning: deviceWarning,
            uploadStatus: uploadStatus,
            availableActions: availableActions(for: captureState, supportsActions: supportsActions),
            allowedAdvisoryHints: target.allowedAdvisoryHints,
            truthBoundary: MetaDisplayHUDSnapshot.truthBoundary
        )
    }

    nonisolated static func availableActions(for state: MetaDisplayHUDState, supportsActions: Bool) -> [MetaDisplayAction] {
        guard supportsActions else { return [] }
        switch state {
        case .recording:
            return [.pause, .checkpoint, .finish]
        case .paused:
            return [.resume, .checkpoint, .finish]
        default:
            return []
        }
    }

    private nonisolated static func formatDuration(_ seconds: Double) -> String {
        let bounded = max(0, Int(seconds.rounded(.down)))
        return "\(bounded / 60):\(String(format: "%02d", bounded % 60))"
    }

    #if canImport(MWDATDisplay) && !targetEnvironment(simulator)
    private static func displayRoot(for snapshot: MetaDisplayHUDSnapshot,
                                    onAction: ActionHandler?) -> MWDATDisplay.FlexBox {
        MWDATDisplay.FlexBox(direction: .column, spacing: 8, alignment: .start, crossAlignment: .stretch) {
            MWDATDisplay.FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
                MWDATDisplay.Icon(name: snapshot.deviceWarning == nil ? .smartGlasses : .exclamationTriangle)
                MWDATDisplay.Text(snapshot.captureState.displayLabel, style: .heading)
                MWDATDisplay.Text(snapshot.timerText, style: .body, color: .secondary)
            }
            MWDATDisplay.Text(snapshot.targetName, style: .heading)
            MWDATDisplay.Text(snapshot.targetAddress, style: .meta, color: .secondary)
            if let captureBrief = snapshot.captureBrief, !captureBrief.isEmpty {
                MWDATDisplay.Text(captureBrief, style: .meta, color: .secondary)
            }
            MWDATDisplay.Text(snapshot.privacyReminder, style: .meta, color: .secondary)
            MWDATDisplay.Text("\(snapshot.frameCount) frames", style: .meta, color: .secondary)
            if let advisoryHint = snapshot.advisoryHint {
                MWDATDisplay.Text(advisoryHint.displayText, style: .body)
            }
            if let deviceWarning = snapshot.deviceWarning {
                MWDATDisplay.Text(deviceWarning.displayText, style: .body)
                MWDATDisplay.Text(deviceWarning.userActionText, style: .meta, color: .secondary)
            }
            if let uploadStatus = snapshot.uploadStatus {
                MWDATDisplay.Text(uploadStatus.displayText, style: .body)
            }
            if !snapshot.availableActions.isEmpty {
                MWDATDisplay.FlexBox(direction: .row, spacing: 6, alignment: .start, crossAlignment: .center) {
                    for action in snapshot.availableActions {
                        MWDATDisplay.Button(
                            label: action.displayLabel,
                            style: action == .finish ? .primary : .secondary,
                            iconName: iconName(for: action),
                            onClick: {
                                onAction?(action)
                            }
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(.card)
    }

    private static func iconName(for action: MetaDisplayAction) -> MWDATDisplay.IconName? {
        switch action {
        case .pause:
            return .twoLinesParallel
        case .resume:
            return .triangleRight
        case .finish:
            return .checkmark
        case .checkpoint:
            return .plusCircle
        }
    }
    #endif
}
