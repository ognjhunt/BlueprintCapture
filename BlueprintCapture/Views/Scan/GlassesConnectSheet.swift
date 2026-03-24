import SwiftUI

/// Minimal device connect UI for Meta smart glasses — Kled AI style.
struct GlassesConnectSheet: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    let onConnected: (() -> Void)?

    init(glassesManager: GlassesCaptureManager, onConnected: (() -> Void)? = nil) {
        self.glassesManager = glassesManager
        self.onConnected = onConnected
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color(white: 0.25))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 28)

                // Icon + title
                VStack(spacing: 10) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 48))
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    Text("Smart Glasses")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Connect once. Then one-tap scans.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)
                .padding(.horizontal, 20)

                // State card
                stateCard
                    .padding(.horizontal, 20)

                // Discovered devices (scanning)
                if glassesManager.connectionState == .waitingForDevice,
                   !glassesManager.discoveredDevices.isEmpty {
                    devicesList
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Spacer()

                // Primary action (connected state)
                if case .connected = glassesManager.connectionState {
                    Button {
                        onConnected?()
                    } label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: glassesManager.connectionState) { _, newValue in
            if case .connected = newValue { onConnected?() }
        }
    }

    // MARK: - State card

    @ViewBuilder
    private var stateCard: some View {
        switch glassesManager.connectionState {
        case .connected(let name):
            connectedCard(deviceName: name)
        case .connecting:
            connectingCard
        case .registering:
            registeringCard
        case .waitingForDevice:
            scanningCard
        case .permissionRequired(let deviceName):
            permissionRequiredCard(deviceName: deviceName)
        case .error(let message):
            errorCard(message: message)
        case .disconnected:
            disconnectedCard
        }
    }

    // MARK: - Disconnected

    private var disconnectedCard: some View {
        VStack(spacing: 12) {
            if let last = glassesManager.lastConnectedDevice {
                Button {
                    glassesManager.reconnectLastDevice()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(white: 0.65))
                            .frame(width: 36, height: 36)
                            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconnect")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(last.name)
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.45))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.25))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(white: 0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                glassesManager.startScanning()
            } label: {
                Text("Connect with Meta AI")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Registering

    private var registeringCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(BlueprintTheme.brandTeal)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Finishing Meta setup…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Approve Blueprint in Meta AI, then return here.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()

            Button("Cancel") { glassesManager.stopScanning() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Waiting

    private var scanningCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(BlueprintTheme.brandTeal)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for glasses…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Keep your glasses connected in Meta AI and nearby.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()

            Button("Cancel") { glassesManager.stopScanning() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private func permissionRequiredCard(deviceName: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .frame(width: 36, height: 36)
                    .background(BlueprintTheme.brandTeal.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera permission required")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Grant camera access in Meta AI for \(deviceName).")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button {
                if let device = glassesManager.discoveredDevices.first(where: { $0.name == deviceName }) ?? glassesManager.lastConnectedDevice {
                    glassesManager.connect(to: device)
                } else {
                    glassesManager.startScanning()
                }
            } label: {
                Text("Open Meta Permission Flow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Connecting

    private var connectingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(BlueprintTheme.brandTeal)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connecting…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Establishing connection")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Connected

    private func connectedCard(deviceName: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.successGreen)
                .frame(width: 36, height: 36)
                .background(BlueprintTheme.successGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(1)
            }

            Spacer()

            Button("Disconnect") { glassesManager.disconnect() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BlueprintTheme.successGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BlueprintTheme.successGreen.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Error

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.9, green: 0.55, blue: 0.1))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.9, green: 0.55, blue: 0.1).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection failed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button {
                glassesManager.startScanning()
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.9, green: 0.55, blue: 0.1).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.9, green: 0.55, blue: 0.1).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Devices list

    private var devicesList: some View {
        VStack(spacing: 1) {
            ForEach(glassesManager.discoveredDevices) { device in
                Button { glassesManager.connect(to: device) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "eyeglasses")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.brandTeal)
                            .frame(width: 36, height: 36)
                            .background(BlueprintTheme.brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(device.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.25))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }
}
