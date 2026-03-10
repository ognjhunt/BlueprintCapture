import SwiftUI
import AVFoundation
import UIKit

struct CaptureSessionView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var didAutoStart = false
    @State private var isEnding = false
    let captureContext: TaskCaptureContext

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.captureManager.session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                headerCard
                    .padding(.horizontal)
                    .padding(.top)

                if !viewModel.uploadStatuses.isEmpty {
                    uploadStatusList
                        .padding(.horizontal)
                }

                Spacer()

                if case .error(let reason) = viewModel.captureManager.captureState {
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
                            Label("Retry recording", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                        .disabled(viewModel.captureManager.captureState.isRecording)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.15))
                    )
                    .padding(.horizontal)
                }

                HStack {
                    Button {
                        viewModel.cancelActiveCapture()
                    } label: {
                        Label("Back to review", systemImage: "chevron.left")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())

                    Spacer()

                    Button {
                        endSession()
                    } label: {
                        Label(isEnding ? "Ending…" : "End session", systemImage: isEnding ? "hourglass" : "stop.fill")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                    .disabled(isEnding)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .onReceive(viewModel.captureManager.$captureState) { state in
            switch state {
            case .finished(let artifacts):
                viewModel.handleRecordingFinished(artifacts: artifacts)
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
        .onAppear {
            viewModel.captureManager.configureCaptureContext(captureContext)
            autoStartRecordingIfNeeded()
        }
        .onDisappear {
            viewModel.captureManager.stopSession()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(captureContext.siteName)
                .font(.headline)
            Text(captureContext.taskStatement)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("Phone capture", systemImage: "iphone")
                Label("ARKit optional", systemImage: "arkit")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Pass \(captureContext.capturePass.capturePassId)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.92))
        )
    }

    private func autoStartRecordingIfNeeded() {
        guard !didAutoStart else { return }
        didAutoStart = true
        let manager = viewModel.captureManager
        if !manager.session.isRunning {
            manager.configureSession()
            manager.startSession()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            manager.startRecording()
        }
    }

    private func retryRecording() {
        guard !viewModel.captureManager.captureState.isRecording else { return }
        didAutoStart = true
        let manager = viewModel.captureManager
        manager.configureSession()
        if !manager.session.isRunning {
            manager.startSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                manager.startRecording()
            }
        } else {
            manager.startRecording()
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
                .fill(Color(.secondarySystemBackground).opacity(0.92))
        )
    }

    private func endSession() {
        guard !isEnding else { return }
        isEnding = true
        if viewModel.captureManager.captureState.isRecording {
            viewModel.captureManager.stopRecording()
        } else {
            viewModel.cancelActiveCapture()
            isEnding = false
        }
    }
}

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

private extension VideoCaptureManager.CaptureState {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

#Preview {
    CaptureSessionView(
        viewModel: CaptureFlowViewModel(),
        captureContext: SiteSubmissionDraft(
            siteName: "Pilot bakery",
            siteLocation: "Durham, NC",
            taskStatement: "Capture the packaging handoff zone.",
            workflowContext: "Operators bag finished goods and place them onto a cart.",
            taskZoneBoundaryNotes: "Counter edge to outbound cart."
        ).makeTaskCaptureContext(
            checklist: TaskCaptureContext.defaultChecklist().map {
                var item = $0
                item.isCompleted = true
                return item
            },
            coverage: TaskCaptureContext.defaultCoverageDeclarations().map {
                var item = $0
                item.isCovered = true
                return item
            }
        )
    )
}

private struct UploadStatusRow: View {
    let status: CaptureFlowViewModel.UploadStatus
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.metadata.capturePassId)
                        .font(.subheadline.weight(.semibold))
                    Text("Submission \(status.metadata.submissionId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Site \(status.metadata.siteId) • Task \(status.metadata.taskId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry", action: retry)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
    }
}
