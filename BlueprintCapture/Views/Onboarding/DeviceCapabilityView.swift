import SwiftUI

struct DeviceCapabilityView: View {
    let onContinue: () -> Void

    private let device = DeviceCapabilityService.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: device.hasLiDAR ? "sensor.tag.radiowaves.forward.fill" : "iphone")
                    .font(.system(size: 56))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Your Device")
                    .font(.title2.weight(.bold))

                Text(device.deviceModel)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Capability badges
            VStack(spacing: 12) {
                capabilityRow(
                    icon: "camera.fill",
                    title: "ARKit",
                    supported: device.supportsARKit,
                    detail: device.supportsARKit ? "Spatial tracking enabled" : "Not supported"
                )

                capabilityRow(
                    icon: "sensor.tag.radiowaves.forward.fill",
                    title: "LiDAR",
                    supported: device.hasLiDAR,
                    detail: device.hasLiDAR ? "High-quality depth capture" : "Standard capture mode"
                )

                // Multiplier highlight
                HStack(spacing: 14) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.body)
                        .foregroundStyle(BlueprintTheme.successGreen)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earnings Multiplier")
                            .font(.body.weight(.medium))
                        Text("\(device.multiplierLabel) on every capture")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(device.multiplierLabel)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BlueprintTheme.successGreen.opacity(0.1))
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private func capabilityRow(icon: String, title: String, supported: Bool, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(supported ? BlueprintTheme.successGreen : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(supported ? BlueprintTheme.successGreen : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    DeviceCapabilityView { }
        .preferredColorScheme(.dark)
}
