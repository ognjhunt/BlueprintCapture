import SwiftUI

struct CaptureQualityOverlayView: View {
    @ObservedObject var monitor: CaptureQualityMonitor

    var body: some View {
        VStack(spacing: 8) {
            // Top stats strip
            topStatsBar

            // Tracking warning banner
            if let warning = monitor.trackingQuality.warningMessage {
                trackingWarningBanner(warning)
            }
        }
    }

    // MARK: - Top Stats Bar

    private var topStatsBar: some View {
        HStack(spacing: 0) {
            // Recording indicator + timer
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(monitor.elapsedFormatted)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            divider

            // Frame counter
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(monitor.frameCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            divider

            // Data size
            HStack(spacing: 4) {
                Image(systemName: "externaldrive")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(monitor.dataSizeFormatted)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            divider

            // Steadiness indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(steadinessColor)
                    .frame(width: 8, height: 8)
                Text(monitor.steadiness.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }

    private var steadinessColor: Color {
        switch monitor.steadiness {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    // MARK: - Bottom Info Strip

    // MARK: - Tracking Warning Banner

    private func trackingWarningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.black)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.black)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.9))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - LiDAR + Coverage Badge (optional bottom strip)

struct CaptureInfoBadgesView: View {
    @ObservedObject var monitor: CaptureQualityMonitor

    var body: some View {
        HStack(spacing: 12) {
            // LiDAR badge
            if monitor.hasLiDAR {
                HStack(spacing: 4) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.caption2)
                    Text("LiDAR Active")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.7))
                )
            }

            // Coverage estimate (only meaningful with LiDAR/mesh)
            if monitor.meshAnchorCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.caption2)
                    Text("\(Int(monitor.estimatedCoveragePercent))% coverage")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
            }

            // Depth frame count
            if monitor.depthFrameCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                    Text("\(monitor.depthFrameCount) depth")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
            }

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            CaptureQualityOverlayView(monitor: CaptureQualityMonitor())
                .padding()
            Spacer()
            CaptureInfoBadgesView(monitor: CaptureQualityMonitor())
                .padding()
        }
    }
}
