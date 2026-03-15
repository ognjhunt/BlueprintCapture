import SwiftUI

struct PostCaptureSummaryView: View {
    let duration: TimeInterval
    let frameCount: Int
    let depthFrameCount: Int
    let estimatedDataSizeMB: Double
    let estimatedCoveragePercent: Double
    let hasLiDAR: Bool
    let onUploadNow: () -> Void
    let onUploadLater: () -> Void
    @Binding var userNotes: String

    private let device = DeviceCapabilityService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("Capture Complete")
                    .font(.headline)
                Spacer()
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                statCell(label: "Duration", value: formattedDuration)
                statCell(label: "Frames", value: "\(frameCount)")
                statCell(label: "Depth Frames", value: "\(depthFrameCount)")
                statCell(label: "Data Size", value: formattedDataSize)
            }

            // Device multiplier badge
            HStack(spacing: 8) {
                Image(systemName: hasLiDAR ? "sensor.tag.radiowaves.forward.fill" : "iphone")
                    .foregroundStyle(BlueprintTheme.brandTeal)
                Text(device.deviceModel)
                    .font(.subheadline)
                Spacer()
                Text(device.multiplierLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("multiplier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(BlueprintTheme.brandTeal.opacity(0.1))
            )

            // Estimated earnings
            HStack {
                Text("Estimated earnings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(estimatedEarningsRange)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Submission readiness")
                    .font(.subheadline.weight(.semibold))

                readinessRow(label: "Coverage", value: "\(Int(estimatedCoveragePercent))%", tone: estimatedCoveragePercent >= 70 ? .good : .warning)
                readinessRow(label: "Device score", value: device.capabilityDescription, tone: hasLiDAR ? .good : .warning)
                readinessRow(label: "Expected review", value: expectedReviewSLA, tone: .neutral)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
            )

            // Notes
            TextField("Add notes about this space (optional)", text: $userNotes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                )

            // Upload buttons
            VStack(spacing: 8) {
                Button(action: onUploadNow) {
                    Text("Upload Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                Button(action: onUploadLater) {
                    Text("Upload Later (WiFi)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Computed Properties

    private var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var formattedDataSize: String {
        if estimatedDataSizeMB < 1.0 {
            return String(format: "%.0f KB", estimatedDataSizeMB * 1024)
        }
        if estimatedDataSizeMB < 1024 {
            return String(format: "%.1f MB", estimatedDataSizeMB)
        }
        return String(format: "%.1f GB", estimatedDataSizeMB / 1024)
    }

    private var estimatedEarningsRange: String {
        // Base estimate: $20-60 range scaled by multiplier and duration
        let multiplier = device.captureMultiplier
        let durationMinutes = duration / 60.0
        let durationFactor = min(1.0, durationMinutes / 15.0) // Full rate at 15+ min

        let baseLow = 20.0
        let baseHigh = 60.0

        let low = Int(baseLow * durationFactor * (multiplier / 2.0))
        let high = Int(baseHigh * durationFactor * (multiplier / 2.0))

        return "$\(max(low, 5))–$\(max(high, 10))"
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var expectedReviewSLA: String {
        if estimatedCoveragePercent >= 80 {
            return "Usually reviewed within 24h"
        }
        if estimatedCoveragePercent >= 60 {
            return "Review likely within 24-48h"
        }
        return "May require recapture review"
    }

    private enum ReadinessTone {
        case good
        case warning
        case neutral
    }

    private func readinessRow(label: String, value: String, tone: ReadinessTone) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(readinessColor(tone))
        }
    }

    private func readinessColor(_ tone: ReadinessTone) -> Color {
        switch tone {
        case .good:
            return BlueprintTheme.successGreen
        case .warning:
            return .orange
        case .neutral:
            return .primary
        }
    }
}

#Preview {
    PostCaptureSummaryView(
        duration: 1245,
        frameCount: 18720,
        depthFrameCount: 9360,
        estimatedDataSizeMB: 485.3,
        estimatedCoveragePercent: 72,
        hasLiDAR: true,
        onUploadNow: {},
        onUploadLater: {},
        userNotes: .constant("")
    )
    .padding()
    .preferredColorScheme(.dark)
}
