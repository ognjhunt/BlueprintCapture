import SwiftUI
import CoreLocation
import UIKit

/// Full-screen scan experience: preflight -> record -> auto-upload.
struct ScanRecordingView: View {
    let job: ScanJob
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel

    private let targetStateService: TargetStateServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @State private var showConnectSheet = false
    @State private var phase: Phase = .preparing("Preparing…")
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case preparing(String)
        case recording
        case uploading
        case finished
        case error
    }

    init(job: ScanJob,
         glassesManager: GlassesCaptureManager,
         uploadQueue: UploadQueueViewModel,
         targetStateService: TargetStateServiceProtocol = TargetStateService()) {
        self.job = job
        self.glassesManager = glassesManager
        self.uploadQueue = uploadQueue
        self.targetStateService = targetStateService
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                topBar

                Spacer()

                mainContent

                Spacer()

                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showConnectSheet) {
            GlassesConnectSheet(glassesManager: glassesManager) {
                showConnectSheet = false
                Task { await beginIfPossible() }
            }
        }
        .onAppear {
            Task { await beginIfPossible() }
        }
        .onChange(of: glassesManager.captureState) { _, newValue in
            switch newValue {
            case .streaming:
                phase = .recording
            case .finished(let artifacts):
                uploadQueue.enqueueGlassesCapture(artifacts: artifacts, job: job)
                phase = .uploading
            case .error(let message):
                errorMessage = message
                phase = .error
            default:
                break
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(job.address)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                endAndDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch phase {
        case .preparing(let text):
            VStack(spacing: 14) {
                ProgressView().tint(BlueprintTheme.brandTeal)
                Text(text)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Keep your glasses on. We’ll start automatically.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

        case .recording:
            VStack(spacing: 14) {
                Text(formatDuration(glassesManager.streamingInfo?.durationSeconds ?? 0))
                    .font(.system(size: 64, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)

                Text("Recording")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }

        case .uploading:
            VStack(spacing: 14) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 40))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Uploading")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("You can leave this screen. Upload progress stays in the overlay.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

        case .finished:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

        case .error:
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(BlueprintTheme.warningOrange)

                Text("Couldn’t start capture")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(errorMessage ?? "Please try again.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch phase {
        case .recording:
            Button {
                glassesManager.stopCapture()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.red))
            }

        case .uploading:
            Button {
                dismiss()
            } label: {
                Text("Back to capture feed")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())

        case .error:
            VStack(spacing: 10) {
                Button {
                    openDirections()
                } label: {
                    Text("Directions")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())

                Button {
                    Task { await beginIfPossible() }
                } label: {
                    Text("Try again")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
            }

        default:
            EmptyView()
        }
    }

    private func beginIfPossible() async {
        // Ensure connected
        if case .connected = glassesManager.connectionState {
            // continue
        } else {
            // If we have a last device, try reconnect first; otherwise show connect sheet.
            if glassesManager.lastConnectedDevice != nil {
                glassesManager.reconnectLastDevice()
                phase = .preparing("Reconnecting…")
                // Give the connection attempt a moment before showing UI.
                try? await Task.sleep(nanoseconds: 800_000_000)
                if case .connected = glassesManager.connectionState {
                    await beginIfPossible()
                    return
                }
            }
            showConnectSheet = true
            phase = .preparing("Connect your glasses…")
            return
        }

        // On-site check (best-effort)
        phase = .preparing("Checking location…")
        let coord = await OneShotLocationFetcher.fetch()
        if !AppConfig.allowOffsiteCheckIn() {
            guard let coord else {
                errorMessage = "We couldn’t confirm your location. Enable Location Services and try again."
                phase = .error
                return
            }
            let dist = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: CLLocation(latitude: job.lat, longitude: job.lng))
            if dist > Double(job.checkinRadiusM) {
                errorMessage = "Move closer to start scanning (within \(job.checkinRadiusM)m)."
                phase = .error
                return
            }
        }

        // Reserve + check-in right before recording starts.
        phase = .preparing("Reserving job…")
        do {
            let target = Target(
                id: job.id,
                displayName: job.title,
                sku: .B,
                lat: job.lat,
                lng: job.lng,
                address: job.address,
                demandScore: nil,
                sizeSqFt: nil,
                category: job.category,
                computedDistanceMeters: nil
            )
            _ = try await targetStateService.reserve(target: target, for: 60 * 60)
            try await targetStateService.checkIn(targetId: job.id)
        } catch {
            errorMessage = "This job is already reserved or in progress."
            phase = .error
            return
        }

        // Start recording
        phase = .preparing("Starting recording…")
        glassesManager.startCapture(jobId: job.id)
    }

    private func endAndDismiss() {
        if glassesManager.captureState.isActive {
            glassesManager.stopCapture()
        }
        dismiss()
    }

    private func openDirections() {
        let lat = job.lat
        let lng = job.lng
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
