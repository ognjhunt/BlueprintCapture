import SwiftUI

struct FilterBar: View {
    @Binding var radius: NearbyTargetsViewModel.RadiusMi
    @Binding var limit: NearbyTargetsViewModel.Limit
    @Binding var sort: NearbyTargetsViewModel.SortOption

    var body: some View {
        VStack(spacing: 12) {
            // Radius chips
            HStack(spacing: 8) {
                radiusChip(.half, label: "0.5 mi")
                radiusChip(.one, label: "1 mi")
                radiusChip(.five, label: "5 mi")
                Spacer()
            }

            // Top selector
            Picker("Top", selection: $limit) {
                Text("Top 10").tag(NearbyTargetsViewModel.Limit.top10)
                Text("Top 25").tag(NearbyTargetsViewModel.Limit.top25)
            }
            .pickerStyle(.segmented)

            // Sort selector
            Picker("Sort", selection: $sort) {
                Text("Highest Payout").tag(NearbyTargetsViewModel.SortOption.highestPayout)
                Text("Nearest").tag(NearbyTargetsViewModel.SortOption.nearest)
                Text("Highest Demand").tag(NearbyTargetsViewModel.SortOption.highestDemand)
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BlueprintTheme.surface)
        )
    }

    private func radiusChip(_ value: NearbyTargetsViewModel.RadiusMi, label: String) -> some View {
        Button(action: { radius = value }) {
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(radius == value ? BlueprintTheme.primary.opacity(0.15) : Color(.secondarySystemBackground))
                )
                .overlay(
                    Capsule().stroke(radius == value ? BlueprintTheme.primary : Color.gray.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(radius == value ? BlueprintTheme.primary : .primary)
        }
        .buttonStyle(.plain)
    }
}


