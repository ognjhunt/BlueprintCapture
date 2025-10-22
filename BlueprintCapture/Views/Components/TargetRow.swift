import SwiftUI

struct TargetRow: View {
    let item: NearbyTargetsViewModel.NearbyItem
    let reservationSecondsRemaining: Int?

    var body: some View {
        let isReserved = reservationSecondsRemaining != nil
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 96, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.target.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .blueprintPrimaryOnDark()

                        if let seconds = reservationSecondsRemaining {
                            reservedPill(seconds: seconds)
                        }
                    }

                    Text(item.target.address ?? "Address pending…")
                        .font(.subheadline)
                        .blueprintSecondaryOnDark()
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                            .font(.caption)
                            .blueprintTertiaryOnDark()

                        timeBadge()

                        Spacer()

                        Text("Est. $\(formatCurrency(item.estimatedPayoutUsd))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(BlueprintTheme.brandTeal)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            if isReserved {
                // Corner ribbon accent for reserved state
                Text("Reserved")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill(BlueprintTheme.primary)
                    )
                    .foregroundStyle(.white)
                    .offset(x: -4, y: -4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isReserved ? BlueprintTheme.primary.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isReserved ? BlueprintTheme.primary.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = item.streetImageURL, item.hasStreetView {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .failure(_): placeholder
                case .empty: ProgressView()
                @unknown default: placeholder
                }
            }
        } else {
            MapSnapshotView(coordinate: item.target.coordinate)
        }
    }

    private func timeBadge() -> some View {
        let minutes = estimatedScanTimeMinutes(for: item.target)
        let timeText = formatDuration(minutes)
        return Text(timeText)
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(BlueprintTheme.primary.opacity(0.12)))
            .overlay(Capsule().stroke(BlueprintTheme.primary.opacity(0.5), lineWidth: 1))
            .foregroundStyle(BlueprintTheme.primary)
    }

    private func reservedPill(seconds: Int) -> some View {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        let text = String(format: "%02d:%02d", mins, secs)
        return HStack(spacing: 4) {
            Image(systemName: "clock.badge.checkmark")
            Text(text)
                .monospacedDigit()
        }
        .font(.caption2).fontWeight(.bold)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(BlueprintTheme.primary.opacity(0.15)))
        .overlay(Capsule().stroke(BlueprintTheme.primary.opacity(0.4), lineWidth: 1))
        .foregroundStyle(BlueprintTheme.primary)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.1)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func formatCurrency(_ value: Int) -> String {
        let number = NSNumber(value: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: number) ?? "\(value)"
    }
}


