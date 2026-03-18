import SwiftUI
import AVFoundation
import UIKit
import ARKit
import RealityKit

struct CaptureSessionView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @ObservedObject private var captureManager: VideoCaptureManager
    @State private var didAutoStart = false
    @State private var isEnding = false
    @State private var captureNotes = ""
    @Environment(\.dismiss) private var dismiss
    let targetId: String?
    let reservationId: String?

    // Venue permission for this capture (would be set when user selects a location)
    @State private var venuePermission: VenuePermission? = .demo

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    init(viewModel: CaptureFlowViewModel, targetId: String?, reservationId: String?) {
        self.viewModel = viewModel
        self._captureManager = ObservedObject(initialValue: viewModel.captureManager)
        self.targetId = targetId
        self.reservationId = reservationId
    }

    var body: some View {
        ZStack {
            // Use ARView when ARSession is active, otherwise use AVCaptureSession preview
            if captureManager.usesARSessionForCapture {
                ARCameraPreview(session: captureManager.arSession)
                    .ignoresSafeArea()
            } else {
                CameraPreview(session: captureManager.session)
                    .ignoresSafeArea()
            }

            VStack(spacing: 8) {
                // Top bar with permission badge and quality overlay
                HStack {
                    Spacer()
                    VenuePermissionBadge(permission: venuePermission)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Real-time quality overlay (when recording)
                if captureManager.captureState.isRecording {
                    CaptureQualityOverlayView(monitor: captureManager.qualityMonitor)
                        .padding(.horizontal)

                    CaptureInfoBadgesView(monitor: captureManager.qualityMonitor)
                        .padding(.horizontal)
                }

                // Upload progress overlay (if any)
                if !viewModel.uploadStatuses.isEmpty {
                    uploadStatusList
                        .padding(.horizontal)
                }

                Spacer()

                // Error banner + retry control when recording fails
                if case .error(let reason) = captureManager.captureState {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Recording failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)

                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.red)

                        Button {
                            retryRecording()
                        } label: {
                            Label("Retry Recording", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                        .disabled(captureManager.captureState.isRecording)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.15))
                    )
                    .padding(.horizontal)
                }

                // Post-capture summary
                if case .finished = captureManager.captureState {
                    let monitor = captureManager.qualityMonitor
                    PostCaptureSummaryView(
                        duration: monitor.elapsedSeconds,
                        frameCount: monitor.frameCount,
                        depthFrameCount: monitor.depthFrameCount,
                        estimatedDataSizeMB: monitor.estimatedDataSizeMB,
                        estimatedCoveragePercent: monitor.estimatedCoveragePercent,
                        hasLiDAR: monitor.hasLiDAR,
                        capturePolicyLabel: capturePolicyLabel,
                        rightsSummary: rightsSummary,
                        onUploadNow: {
                            viewModel.updatePendingCaptureNotes(captureNotes)
                            viewModel.startPendingCaptureUpload()
                        },
                        onUploadLater: {
                            viewModel.updatePendingCaptureNotes(captureNotes)
                            completeAndDismiss()
                        },
                        userNotes: $captureNotes
                    )
                    .padding(.horizontal)
                }

                if case .finished = captureManager.captureState,
                   viewModel.pendingCaptureRequest != nil || viewModel.finishedCaptureActionState != .idle {
                    finishedCaptureCard
                        .padding(.horizontal)
                }

                HStack {
                    Spacer()
                    Button {
                        handleEndTapped()
                    } label: {
                        Label(buttonTitle, systemImage: buttonIcon)
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                    .disabled(isEnding)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .onReceive(captureManager.$captureState) { state in
            switch state {
            case .idle:
                print("📥 [CaptureSessionView] captureState → idle")
            case .recording(_):
                print("📥 [CaptureSessionView] captureState → recording")
            case .finished(_):
                print("📥 [CaptureSessionView] captureState → finished")
            case .error(let message):
                print("📥 [CaptureSessionView] captureState → error (\(message))")
            }
            switch state {
            case .finished(let artifacts):
                viewModel.handleRecordingFinished(artifacts: artifacts, targetId: targetId, reservationId: reservationId)
                isEnding = false
            case .idle:
                isEnding = false
            case .error:
                isEnding = false
                didAutoStart = false
            default:
                break
            }
        }
        .onChange(of: captureManager.qualityMonitor.steadiness) { oldValue, newValue in
            if oldValue != newValue {
                hapticFeedback.impactOccurred()
            }
        }
        .onChange(of: captureNotes) { _, newValue in
            viewModel.updatePendingCaptureNotes(newValue)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            autoStartRecordingIfNeeded()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(item: $viewModel.manualIntakeDraft) { draft in
            ManualIntakeSheetView(title: draft.reviewTitle, draft: draft) { updatedDraft in
                viewModel.submitManualIntake(updatedDraft)
            }
        }
        .sheet(item: $viewModel.shareSheetItem) { shareItem in
            ShareSheet(items: [shareItem.url])
        }
    }

    private var capturePolicyLabel: String {
        switch viewModel.pendingCaptureRequest?.metadata.rightsProfile?.lowercased() {
        case "documented_permission":
            return "Approved capture"
        case "policy_only":
            return "Permission required"
        case "blocked":
            return "Not allowed"
        default:
            return "Review required"
        }
    }

    private var rightsSummary: String {
        switch viewModel.pendingCaptureRequest?.metadata.rightsProfile?.lowercased() {
        case "documented_permission":
            return "This submission appears to have documented permission for the approved scope. Blueprint will still verify rights and restricted-zone handling."
        case "policy_only":
            return "Capture only what site policy clearly allows. Be ready to stop if staff object and keep restricted areas out of frame."
        case "blocked":
            return "This space is currently marked not allowed. Do not submit unless Blueprint clears the restriction."
        default:
            return "This space will be review-gated before reuse. Capture common areas only and keep faces, screens, paperwork, and restricted zones out of frame."
        }
    }

    private func handleEndTapped() {
        guard !isEnding else { return }
        endSession()
    }

    private func autoStartRecordingIfNeeded() {
        guard !didAutoStart else { return }
        didAutoStart = true
        print("🎬 [Capture] View appeared — auto start flow")
        // Ensure the session is configured and running, then start recording automatically
        if !captureManager.session.isRunning {
            print("🎥 [Capture] Starting AVCaptureSession…")
            captureManager.configureSession()
            captureManager.startSession()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("⏺️ [Capture] Auto-start recording…")
            captureManager.startRecording()
        }
    }

    private func retryRecording() {
        guard !captureManager.captureState.isRecording else { return }
        print("🔄 [Capture] Retry Recording tapped")
        didAutoStart = true
        captureManager.configureSession()

        if !captureManager.session.isRunning {
            captureManager.startSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                captureManager.startRecording()
            }
        } else {
            captureManager.startRecording()
        }
    }

    private var uploadStatusList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uploads")
                .font(.headline)
            ForEach(viewModel.uploadStatuses) { status in
                UploadStatusRow(
                    status: status,
                    retry: { viewModel.retryUpload(id: status.id) },
                    dismiss: { viewModel.dismissUpload(id: status.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var finishedCaptureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture Ready")
                .font(.headline)

            if let targetName = viewModel.pendingCaptureTargetName {
                Text(targetName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch viewModel.finishedCaptureActionState {
            case .idle:
                Text("Upload the finalized bundle or export it for local pipeline testing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .generatingIntake:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Generating intake from the video…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .exporting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finalizing export bundle…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.startPendingCaptureUpload()
                } label: {
                    Text("Upload")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .disabled(isWorking)

                Button {
                    viewModel.startPendingCaptureExport()
                } label: {
                    Text("Export for Testing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
                .disabled(isWorking)
            }

            Button("Done", action: completeAndDismiss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var isWorking: Bool {
        switch viewModel.finishedCaptureActionState {
        case .generatingIntake, .exporting:
            return true
        case .idle, .failed:
            return false
        }
    }

    private var buttonTitle: String {
        if case .finished = captureManager.captureState {
            return "Done"
        }
        return isEnding ? "Ending…" : "End Session"
    }

    private var buttonIcon: String {
        if case .finished = captureManager.captureState {
            return "checkmark.circle"
        }
        return isEnding ? "hourglass" : "stop.fill"
    }

    private func endSession() {
        guard !isEnding else { return }
        isEnding = true
        print("🛑 [Capture] End Session tapped — stopping recording & session")
        if case .finished = captureManager.captureState {
            completeAndDismiss()
            return
        }
        if captureManager.captureState.isRecording {
            captureManager.stopRecording()
        } else {
            print("ℹ️ [Capture] No active recording when ending session")
            viewModel.step = .confirmLocation
            dismiss()
        }
        captureManager.stopSession()
    }

    private func completeAndDismiss() {
        captureManager.stopSession()
        viewModel.clearFinishedCapture()
        viewModel.step = .confirmLocation
        dismiss()
    }
}

// (Removed old CaptureOverlay, RecordButton and share sheet for the simplified UX)

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

// MARK: - ARView Camera Preview

private struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
        // Use camera rendering only - no virtual content
        arView.environment.background = .cameraFeed()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Session is managed externally by VideoCaptureManager
    }
}

// MARK: - Capture Guidance View

private struct CaptureGuidanceView: View {
    @State private var currentTipIndex = 0
    @State private var showTip = true

    private let tips = [
        CaptureGuidanceTip(icon: "arrow.left.and.right", text: "Move slowly and steadily"),
        CaptureGuidanceTip(icon: "cube.transparent", text: "Scan corners and edges"),
        CaptureGuidanceTip(icon: "lightbulb", text: "Ensure good lighting"),
        CaptureGuidanceTip(icon: "hand.raised", text: "Keep phone upright"),
        CaptureGuidanceTip(icon: "arrow.triangle.2.circlepath", text: "Overlap scanned areas")
    ]

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(showTip ? 1.5 : 1.0)
                            .opacity(showTip ? 0 : 1)
                    )
                Text("REC")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Divider()
                .frame(height: 20)

            // Rotating tips
            if currentTipIndex < tips.count {
                let tip = tips[currentTipIndex]
                HStack(spacing: 8) {
                    Image(systemName: tip.icon)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(tip.text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .onAppear {
            startTipRotation()
        }
        .animation(.easeInOut(duration: 0.5), value: currentTipIndex)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: showTip)
    }

    private func startTipRotation() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation {
                currentTipIndex = (currentTipIndex + 1) % tips.count
            }
        }
    }
}

private struct CaptureGuidanceTip {
    let icon: String
    let text: String
}

private extension VideoCaptureManager.CaptureState {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

#Preview {
    CaptureSessionView(
        viewModel: CaptureFlowViewModel(),
        targetId: "target-123",
        reservationId: "reservation-456"
    )
}

private struct UploadStatusRow: View {
    let status: CaptureFlowViewModel.UploadStatus
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.metadata.jobId)
                        .font(.subheadline.weight(.semibold))
                    if let targetId = status.metadata.targetId {
                        Text("Target: \(targetId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let reservationId = status.metadata.reservationId {
                        Text("Reservation: \(reservationId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(status.metadata.capturedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch status.state {
            case .queued:
                Label("Waiting to upload…", systemImage: "tray.full")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .uploading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                    Text("Uploading… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .completed:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Upload complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let uploadedAt = status.metadata.uploadedAt {
                        Text("Uploaded \(uploadedAt, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Upload failed", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Retry", action: retry)
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Button("Dismiss", action: dismiss)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}
