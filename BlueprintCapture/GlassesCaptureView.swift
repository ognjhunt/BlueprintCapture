import Combine
import SwiftUI
import UIKit

/// Main view for Meta smart glasses video capture.
struct GlassesCaptureView: View {
    @StateObject private var captureManager = GlassesCaptureManager()
    @StateObject private var uploadViewModel = GlassesUploadViewModel()
    @State private var locationId: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                content
            }
            .navigationTitle("Meta Glasses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .blueprintAppBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch captureManager.connectionState {
        case .disconnected:
            disconnectedView

        case .scanning:
            scanningView

        case .connecting:
            connectingView

        case .connected(let deviceName):
            connectedView(deviceName: deviceName)

        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Hero
            VStack(spacing: 20) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 72))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Connect Your Glasses")
                    .font(.title2.weight(.bold))

                Text("Pair your Meta Ray-Ban glasses to capture hands-free.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Features
            VStack(spacing: 16) {
                featureItem(icon: "video.fill", text: "720p video capture")
                featureItem(icon: "figure.walk", text: "Walk naturally while recording")
                featureItem(icon: "icloud.and.arrow.up", text: "Auto-upload when done")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Scan button
            Button {
                captureManager.startScanning()
            } label: {
                Text("Scan for Glasses")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Scanning State

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Scanning animation
            VStack(spacing: 20) {
                ZStack {
                    // Animated rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(BlueprintTheme.brandTeal.opacity(0.3), lineWidth: 2)
                            .frame(width: 100 + CGFloat(i * 40), height: 100 + CGFloat(i * 40))
                            .scaleEffect(1.0)
                            .opacity(0.8 - Double(i) * 0.2)
                    }

                    Image(systemName: "eyeglasses")
                        .font(.system(size: 40))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }
                .frame(height: 200)

                Text("Scanning for devices...")
                    .font(.headline)
                    .blueprintPrimaryOnDark()

                ProgressView()
                    .tint(BlueprintTheme.brandTeal)
            }

            Spacer()

            // Discovered devices list
            if !captureManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Found Devices")
                        .font(.headline)
                        .blueprintPrimaryOnDark()
                        .padding(.horizontal)

                    ForEach(captureManager.discoveredDevices) { device in
                        DeviceRow(device: device) {
                            captureManager.connect(to: device)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Cancel button
            Button {
                captureManager.stopScanning()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(BlueprintSecondaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Connecting State

    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(BlueprintTheme.brandTeal)

                Text("Connecting...")
                    .font(.headline)
                    .blueprintPrimaryOnDark()

                Text("Please ensure your glasses are nearby and Bluetooth is enabled.")
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Connected State

    private func connectedView(deviceName: String) -> some View {
        VStack(spacing: 0) {
            // Connected device header
            connectedHeader(deviceName: deviceName)

            // Capture content based on state
            captureContent
        }
    }

    private func connectedHeader(deviceName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eyeglasses")
                .font(.title3)
                .foregroundStyle(BlueprintTheme.successGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(.subheadline.weight(.semibold))
                    .blueprintPrimaryOnDark()

                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.successGreen)
            }

            Spacer()

            Button {
                captureManager.disconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BlueprintTheme.successGreen.opacity(0.15))
        )
        .padding(.horizontal)
        .padding(.top)
    }

    @ViewBuilder
    private var captureContent: some View {
        switch captureManager.captureState {
        case .idle:
            idleCaptureView

        case .preparing:
            preparingView

        case .streaming(let info):
            streamingView(info: info)

        case .paused:
            pausedView

        case .finished(let artifacts):
            finishedView(artifacts: artifacts)

        case .error(let message):
            captureErrorView(message: message)
        }
    }

    // MARK: - Idle Capture State

    private var idleCaptureView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Preview placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Ready to capture")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                )
                .padding(.horizontal, 24)

            Spacer()

            // Tips
            VStack(alignment: .leading, spacing: 12) {
                Label("Walk slowly and cover all angles", systemImage: "figure.walk")
                Label("Include doorways for scale reference", systemImage: "door.left.hand.open")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)

            Spacer()

            // Start button
            Button {
                captureManager.startCapture()
            } label: {
                Text("Start Recording")
            }
            .buttonStyle(BlueprintSuccessButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Preparing State

    private var preparingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(BlueprintTheme.brandTeal)

                Text("Preparing capture...")
                    .font(.headline)
                    .blueprintPrimaryOnDark()
            }

            Spacer()
        }
    }

    // MARK: - Streaming State

    private func streamingView(info: GlassesCaptureManager.StreamingInfo) -> some View {
        VStack(spacing: 20) {
            // Live preview
            if let frame = captureManager.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("REC")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(12)
                    }
                    .padding(.horizontal, 24)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(ProgressView().tint(.white))
                    .padding(.horizontal, 24)
            }

            // Duration display
            Text(formatDuration(info.durationSeconds))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()

            // Stop button
            Button {
                captureManager.stopCapture()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(Color.red))
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 16)
    }

    // MARK: - Paused State

    private var pausedView: some View {
        VStack(spacing: 24) {
            // Paused preview
            if let frame = captureManager.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        Text("PAUSED")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .padding(.horizontal)
            }

            Spacer()

            // Resume/Stop controls
            HStack(spacing: 20) {
                Button {
                    captureManager.resumeCapture()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(BlueprintSuccessButtonStyle())

                Button {
                    captureManager.stopCapture()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
    }

    // MARK: - Finished State

    private func finishedView(artifacts: GlassesCaptureManager.CaptureArtifacts) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Success
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Text("Capture Complete")
                    .font(.title2.weight(.bold))

                Text("\(formatDuration(artifacts.durationSeconds)) recorded")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Upload status
            VStack(spacing: 16) {
                if case .uploading(let progress) = uploadViewModel.state {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(BlueprintTheme.brandTeal)
                        Text("Uploading... \(Int(progress * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                } else if case .completed = uploadViewModel.state {
                    Label("Upload complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(BlueprintTheme.successGreen)
                } else if case .failed(let message) = uploadViewModel.state {
                    VStack(spacing: 8) {
                        Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(BlueprintTheme.errorRed)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .completed = uploadViewModel.state {
                    Button {
                        uploadViewModel.reset()
                        captureManager.reset()
                    } label: {
                        Text("Done")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                } else if case .failed = uploadViewModel.state {
                    Button {
                        uploadViewModel.upload(artifacts: artifacts, locationId: locationId)
                    } label: {
                        Text("Retry Upload")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                } else if case .idle = uploadViewModel.state {
                    Button {
                        uploadViewModel.upload(artifacts: artifacts, locationId: locationId)
                    } label: {
                        Text("Upload")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Error Views

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(BlueprintTheme.errorRed)

                Text("Connection Error")
                    .font(.title2.weight(.bold))
                    .blueprintPrimaryOnDark()

                Text(message)
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button {
                captureManager.startScanning()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func captureErrorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(BlueprintTheme.errorRed)

                Text("Capture Error")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                captureManager.startCapture()
            } label: {
                Text("Try Again")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func fileSize(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

final class GlassesUploadViewModel: ObservableObject {
    enum UploadState: Equatable {
        case idle
        case uploading(Double)
        case completed
        case failed(String)
    }

    @Published var state: UploadState = .idle

    private let uploadService: CaptureUploadServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var activeUploadId: UUID?

    init(uploadService: CaptureUploadServiceProtocol = CaptureUploadService()) {
        self.uploadService = uploadService

        uploadService.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)
    }

    var isUploading: Bool {
        if case .uploading = state { return true }
        return false
    }

    func upload(artifacts: GlassesCaptureManager.CaptureArtifacts, locationId: String) {
        let trimmed = locationId.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetId = trimmed.isEmpty ? nil : trimmed
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: targetId,
            reservationId: nil,
            jobId: targetId ?? UUID().uuidString,
            creatorId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown_device",
            capturedAt: artifacts.startedAt,
            uploadedAt: nil,
            captureSource: .metaGlasses
        )

        activeUploadId = metadata.id
        state = .uploading(0)
        let request = CaptureUploadRequest(packageURL: artifacts.packageURL, metadata: metadata)
        uploadService.enqueue(request)
    }

    func reset() {
        state = .idle
        activeUploadId = nil
    }

    private func handle(_ event: CaptureUploadService.Event) {
        switch event {
        case .queued(let request):
            guard request.metadata.id == activeUploadId else { return }
            state = .uploading(0)
        case .progress(let id, let progress):
            guard id == activeUploadId else { return }
            state = .uploading(progress)
        case .completed(let request):
            guard request.metadata.id == activeUploadId else { return }
            state = .completed
        case .failed(let request, let error):
            guard request.metadata.id == activeUploadId else { return }
            state = .failed(error.errorDescription ?? "Upload failed")
        }
    }
}

// MARK: - Supporting Views

private struct DeviceRow: View {
    let device: GlassesCaptureManager.DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 14) {
                Image(systemName: "eyeglasses")
                    .font(.title3)
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(BlueprintTheme.brandTeal.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Tap to connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GlassesCaptureView()
}
