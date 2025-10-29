import SwiftUI
import AVFoundation
import UIKit

struct CaptureSessionView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var didAutoStart = false
    @State private var isEnding = false
    let targetId: String?
    let reservationId: String?

    var body: some View {
        ZStack {
            // Full-screen camera preview
            CameraPreview(session: viewModel.captureManager.session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Upload progress overlay (if any)
                if !viewModel.uploadStatuses.isEmpty {
                    uploadStatusList
                        .padding(.horizontal)
                }

                Spacer()

                // Error banner (if camera unavailable)
                if case .error(let message) = viewModel.captureManager.captureState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.15))
                        )
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // End Session button only
                HStack {
                    Spacer()
                    Button {
                        endSession()
                    } label: {
                        Label(isEnding ? "Ending…" : "End Session", systemImage: isEnding ? "hourglass" : "stop.fill")
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
                viewModel.handleRecordingFinished(artifacts: artifacts, targetId: targetId, reservationId: reservationId)
                isEnding = false
            case .idle, .error:
                isEnding = false
            default:
                break
            }
        }
        .onAppear {
            autoStartRecordingIfNeeded()
        }
    }

    private func autoStartRecordingIfNeeded() {
        guard !didAutoStart else { return }
        didAutoStart = true
        print("🎬 [Capture] View appeared — auto start flow")
        // Ensure the session is configured and running, then start recording automatically
        if !viewModel.captureManager.session.isRunning {
            print("🎥 [Capture] Starting AVCaptureSession…")
            viewModel.captureManager.configureSession()
            viewModel.captureManager.startSession()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("⏺️ [Capture] Auto-start recording…")
            viewModel.captureManager.startRecording()
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

    private func endSession() {
        guard !isEnding else { return }
        isEnding = true
        print("🛑 [Capture] End Session tapped — stopping recording & session")
        // Stop recording (if active) and the camera session
        if viewModel.captureManager.captureState.isRecording {
            viewModel.captureManager.stopRecording()
        } else {
            print("ℹ️ [Capture] No active recording when ending session")
        }
        viewModel.captureManager.stopSession()
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
