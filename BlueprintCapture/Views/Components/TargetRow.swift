import SwiftUI

struct TargetRow: View {
    let item: NearbyTargetsViewModel.NearbyItem
    let reservationSecondsRemaining: Int?
    let isOnSite: Bool
    let reservedByMe: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            thumbnail
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Name
                Text(item.target.displayName)
                    .font(.headline)
                    .lineLimit(1)

                // Address
                Text(item.target.address ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Distance and status
                HStack(spacing: 12) {
                    if isOnSite {
                        Label("Here", systemImage: "location.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BlueprintTheme.successGreen)
                    } else {
                        Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let seconds = reservationSecondsRemaining, reservedByMe {
                        Label(formatCountdown(seconds), systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BlueprintTheme.brandTeal)
                    }
                }
            }

            Spacer()

            // Payout
            VStack(alignment: .trailing, spacing: 4) {
                Text("$\(item.estimatedPayoutUsd)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Text("Est. payout")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(reservedByMe ? BlueprintTheme.brandTeal : Color.clear, lineWidth: 2)
        )
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = item.streetImageURL, item.hasStreetView {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure(_):
                    placeholder
                case .empty:
                    placeholder.overlay(ProgressView().controlSize(.small))
                @unknown default:
                    placeholder
                }
            }
        } else {
            MapSnapshotView(coordinate: item.target.coordinate)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: "building.2")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatCountdown(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
