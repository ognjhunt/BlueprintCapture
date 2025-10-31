import SwiftUI

struct FilterBar: View {
    @Binding var radius: NearbyTargetsViewModel.RadiusMi
    @Binding var limit: NearbyTargetsViewModel.Limit
    @Binding var sort: NearbyTargetsViewModel.SortOption

    var body: some View {
        VStack(spacing: 16) {
            // Radius chips
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                radiusChip(.half, label: "0.5 mi")
                radiusChip(.one, label: "1 mi")
                radiusChip(.five, label: "5 mi")
                radiusChip(.ten, label: "10 mi")
                Spacer(minLength: 0)
            }

            // Top selector
            Picker("Top", selection: $limit) {
                Text("Top 10").tag(NearbyTargetsViewModel.Limit.top10)
                Text("Top 25").tag(NearbyTargetsViewModel.Limit.top25)
            }
            .pickerStyle(.segmented)
            .tint(BlueprintTheme.accentAqua)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )

            // Sort selector
            Picker("Sort", selection: $sort) {
                Text("Highest Payout").tag(NearbyTargetsViewModel.SortOption.highestPayout)
                Text("Nearest").tag(NearbyTargetsViewModel.SortOption.nearest)
                Text("Highest Demand").tag(NearbyTargetsViewModel.SortOption.highestDemand)
            }
            .pickerStyle(.segmented)
            .tint(BlueprintTheme.accentAqua)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            BlueprintTheme.primary.opacity(0.28),
                            BlueprintTheme.brandTeal.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BlueprintTheme.accentAqua.opacity(0.5), BlueprintTheme.primary.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: BlueprintTheme.primary.opacity(0.22), radius: 28, x: 0, y: 16)
    }

    private func radiusChip(_ value: NearbyTargetsViewModel.RadiusMi, label: String) -> some View {
        Button(action: { radius = value }) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        radius == value
                            ? LinearGradient(colors: [BlueprintTheme.primary, BlueprintTheme.accentAqua], startPoint: .leading, endPoint: .trailing)
                            : Color.white.opacity(0.12)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        radius == value
                            ? Color.white.opacity(0.25)
                            : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(radius == value ? Color.white : Color.white.opacity(0.82))
        }
        .buttonStyle(.plain)
    }
}


