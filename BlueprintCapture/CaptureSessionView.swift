import SwiftUI
import AVFoundation
import UIKit

struct CaptureSessionView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    let targetId: String?
    let reservationId: String?

    var body: some View {
        VStack(spacing: 16) {
            CameraPreview(session: viewModel.captureManager.session)
                .overlay(alignment: .topLeading) {
                    CaptureOverlay()
                        .padding()
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)

            captureControls

            if !viewModel.uploadStatuses.isEmpty {
                uploadStatusList
            }

            if case .error(let message) = viewModel.captureManager.captureState {
                Label(message, systemImage: "exclamationmark.octagon")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onReceive(viewModel.captureManager.$captureState) { state in
            switch state {
            case .finished(let url):
                viewModel.handleRecordingFinished(fileURL: url, targetId: targetId, reservationId: reservationId)
            default:
                break
            }
        }
    }

    private var captureControls: some View {
        VStack(spacing: 12) {
            Text("When you're ready, tap record and walk each room twice: once at waist height and once at eye level.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                RecordButton(isRecording: viewModel.captureManager.captureState.isRecording) {
                    toggleRecording()
                }

                Button {
                    viewModel.captureManager.stopSession()
                } label: {
                    Label("End Session", systemImage: "stop.fill")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            }
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

    private func toggleRecording() {
        switch viewModel.captureManager.captureState {
        case .recording:
            viewModel.captureManager.stopRecording()
        default:
            viewModel.captureManager.startRecording()
        }
    }
}

private struct CaptureOverlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Capturing video", systemImage: "video.fill")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Text("Ensure AprilTag or IMU pose marker is visible briefly to lock scale.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(12)
        .background(
            BlueprintTheme.heroGradient.opacity(0.25),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .foregroundStyle(isRecording ? BlueprintTheme.errorRed : Color.red.opacity(0.85))
                .symbolRenderingMode(.palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
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
        if case .recording = self {
            return true
        }
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
