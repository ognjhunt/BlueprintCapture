import SwiftUI
import AVFoundation
import UIKit

struct CaptureSessionView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var showingShareSheet = false
    @State private var recordedURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            CameraPreview(session: viewModel.captureManager.session)
                .overlay(alignment: .topLeading) {
                    CaptureOverlay()
                        .padding()
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(radius: 4)

            captureControls

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
                recordedURL = url
                showingShareSheet = true
            default:
                break
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = recordedURL {
                ShareSheet(activityItems: [url])
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
                .buttonStyle(.bordered)
            }
        }
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .foregroundStyle(isRecording ? Color.red : Color.red.opacity(0.85))
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

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    CaptureSessionView(viewModel: CaptureFlowViewModel())
}
