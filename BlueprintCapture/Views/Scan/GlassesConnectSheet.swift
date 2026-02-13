import SwiftUI

/// Minimal device connect UI for Meta smart glasses.
struct GlassesConnectSheet: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    let onConnected: (() -> Void)?

    init(glassesManager: GlassesCaptureManager, onConnected: (() -> Void)? = nil) {
        self.glassesManager = glassesManager
        self.onConnected = onConnected
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 16) {
                    header

                    switch glassesManager.connectionState {
                    case .connected(let name):
                        connectedCard(deviceName: name)
                    case .connecting:
                        connectingCard
                    case .scanning:
                        scanningCard
                    case .error(let message):
                        errorCard(message: message)
                    case .disconnected:
                        disconnectedCard
                    }

                    if glassesManager.connectionState == .scanning, !glassesManager.discoveredDevices.isEmpty {
                        devicesList
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .navigationTitle("Connect Glasses")
            .navigationBarTitleDisplayMode(.inline)
        }
        .blueprintAppBackground()
        .onChange(of: glassesManager.connectionState) { _, newValue in
            if case .connected = newValue {
                onConnected?()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 44))
                .foregroundStyle(BlueprintTheme.brandTeal)

            Text("Meta smart glasses")
                .font(.title3.weight(.semibold))
                .blueprintPrimaryOnDark()

            Text("Connect once. Then one-tap scans.")
                .font(.subheadline)
                .blueprintSecondaryOnDark()
        }
        .padding(.top, 8)
    }

    private var disconnectedCard: some View {
        VStack(spacing: 12) {
            if let last = glassesManager.lastConnectedDevice {
                Button {
                    glassesManager.reconnectLastDevice()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconnect")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(last.name)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BlueprintTheme.primary)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                glassesManager.startScanning()
            } label: {
                Text("Scan for Glasses")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
        }
        .padding(.top, 10)
    }

    private var scanningCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView().tint(BlueprintTheme.brandTeal)
                Text("Scanning…")
                    .font(.headline)
                    .blueprintPrimaryOnDark()
                Spacer()
                Button("Cancel") { glassesManager.stopScanning() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private var connectingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(BlueprintTheme.brandTeal)
            Text("Connecting…")
                .font(.headline)
                .blueprintPrimaryOnDark()
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func connectedCard(deviceName: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BlueprintTheme.successGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.headline)
                        .blueprintPrimaryOnDark()
                    Text(deviceName)
                        .font(.caption)
                        .blueprintSecondaryOnDark()
                        .lineLimit(1)
                }
                Spacer()
                Button("Disconnect") { glassesManager.disconnect() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlueprintTheme.successGreen.opacity(0.12))
            )
        }
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BlueprintTheme.warningOrange)
                Text("Connection error")
                    .font(.headline)
                    .blueprintPrimaryOnDark()
                Spacer()
            }
            Text(message)
                .font(.caption)
                .blueprintSecondaryOnDark()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Try again") { glassesManager.startScanning() }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                Button("Close") { glassesManager.disconnect() }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BlueprintTheme.warningOrange.opacity(0.10))
        )
    }

    private var devicesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Found")
                .font(.headline)
                .blueprintPrimaryOnDark()
                .padding(.top, 10)

            ForEach(glassesManager.discoveredDevices) { device in
                Button {
                    glassesManager.connect(to: device)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eyeglasses")
                            .foregroundStyle(BlueprintTheme.brandTeal)
                        Text(device.name)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

