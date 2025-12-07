import SwiftUI

/// Main view for Meta smart glasses video capture.
/// Handles device connection, capture session, and upload.
struct GlassesCaptureView: View {
    @StateObject private var captureManager = GlassesCaptureManager()
    @State private var showingDeviceSelection = false
    @State private var showingCaptureComplete = false

    var body: some View {
        NavigationStack {
            ZStack {
                content
            }
            .navigationTitle("Glasses Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        VStack(spacing: 24) {
            Spacer()

            // Hero illustration
            VStack(spacing: 16) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 80))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Connect Your Glasses")
                    .font(.title2.weight(.bold))
                    .blueprintGradientText()

                Text("Pair your Meta Ray-Ban or Oakley glasses to capture immersive walkthroughs for 3D reconstruction.")
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Features list
            BlueprintGlassCard {
                FeatureRow(icon: "video.fill", title: "720p @ 30fps", description: "High quality video streaming via Bluetooth")
                Divider().opacity(0.3)
                FeatureRow(icon: "infinity", title: "Unlimited Duration", description: "Capture as long as you need")
                Divider().opacity(0.3)
                FeatureRow(icon: "iphone.and.arrow.forward", title: "Hands-Free", description: "Walk naturally while capturing")
            }
            .padding(.horizontal)

            Spacer()

            // Mock device toggle for testing
            VStack(spacing: 12) {
                Toggle(isOn: $captureManager.useMockDevice) {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(BlueprintTheme.warningOrange)
                        Text("Use Mock Device (Testing)")
                            .font(.subheadline)
                            .blueprintPrimaryOnDark()
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: BlueprintTheme.brandTeal))
                .padding(.horizontal, 24)

                if captureManager.useMockDevice {
                    Text("MockDeviceKit enabled - simulates glasses for testing")
                        .font(.caption)
                        .blueprintTertiaryOnDark()
                }
            }

            // Scan button
            Button {
                captureManager.startScanning()
            } label: {
                Label("Scan for Glasses", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
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
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Ready to capture")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    )
                    .padding(.horizontal)

                Text("Video will stream at 720p @ 30fps")
                    .font(.caption)
                    .blueprintTertiaryOnDark()
            }

            Spacer()

            // Capture instructions
            BlueprintGlassCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(BlueprintTheme.warningOrange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capture Tips")
                            .font(.subheadline.weight(.semibold))
                            .blueprintPrimaryOnDark()
                        Text("Walk slowly and steadily. Cover all angles of the space. Include a scale reference (like a door or ruler) in your walkthrough.")
                            .font(.caption)
                            .blueprintSecondaryOnDark()
                    }
                }
            }
            .padding(.horizontal)

            // Start capture button
            Button {
                captureManager.startCapture()
            } label: {
                Label("Start Capture", systemImage: "record.circle")
            }
            .buttonStyle(BlueprintSuccessButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
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
        VStack(spacing: 16) {
            // Live preview
            if let frame = captureManager.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        // Recording indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                            Text("REC")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(12),
                        alignment: .topLeading
                    )
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(ProgressView().tint(.white))
                    .padding(.horizontal)
            }

            // Stats bar
            HStack(spacing: 24) {
                StatItem(icon: "timer", value: formatDuration(info.durationSeconds), label: "Duration")
                StatItem(icon: "film", value: "\(info.frameCount)", label: "Frames")
                StatItem(icon: "speedometer", value: String(format: "%.1f", info.fps), label: "FPS")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
            )
            .padding(.horizontal)

            Spacer()

            // Controls
            HStack(spacing: 20) {
                Button {
                    captureManager.pauseCapture()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(BlueprintTheme.warningOrange))
                }

                Button {
                    captureManager.stopCapture()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.red))
                }
            }
            .padding(.bottom)
        }
        .padding(.top)
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

            // Success icon
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Text("Capture Complete!")
                    .font(.title2.weight(.bold))
                    .blueprintGradientText()
            }

            // Summary card
            BlueprintGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SummaryRow(label: "Duration", value: formatDuration(artifacts.durationSeconds))
                    Divider().opacity(0.3)
                    SummaryRow(label: "Frames", value: "\(artifacts.frameCount)")
                    Divider().opacity(0.3)
                    SummaryRow(label: "Resolution", value: "1280 x 720")
                    Divider().opacity(0.3)
                    SummaryRow(label: "File Size", value: fileSize(for: artifacts.videoURL))
                }
            }
            .padding(.horizontal)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    // TODO: Trigger upload
                } label: {
                    Label("Upload to Pipeline", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                Button {
                    captureManager.reset()
                } label: {
                    Text("Start New Capture")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom)
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
                    .blueprintPrimaryOnDark()

                Text(message)
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                captureManager.startCapture()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Helper Views

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

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .blueprintPrimaryOnDark()
                Text(description)
                    .font(.caption)
                    .blueprintSecondaryOnDark()
            }

            Spacer()
        }
    }
}

private struct DeviceRow: View {
    let device: GlassesCaptureManager.DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 14) {
                Image(systemName: device.isMock ? "wrench.and.screwdriver" : "eyeglasses")
                    .font(.title3)
                    .foregroundStyle(device.isMock ? BlueprintTheme.warningOrange : BlueprintTheme.brandTeal)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill((device.isMock ? BlueprintTheme.warningOrange : BlueprintTheme.brandTeal).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .blueprintPrimaryOnDark()
                    Text(device.isMock ? "Mock Device" : "Ready to connect")
                        .font(.caption)
                        .blueprintSecondaryOnDark()
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

private struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            .blueprintPrimaryOnDark()

            Text(label)
                .font(.caption2)
                .blueprintTertiaryOnDark()
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .blueprintSecondaryOnDark()
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .blueprintPrimaryOnDark()
        }
    }
}

#Preview {
    GlassesCaptureView()
}
