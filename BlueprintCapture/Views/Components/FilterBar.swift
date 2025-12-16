import SwiftUI

struct FilterBar: View {
    @Binding var radius: NearbyTargetsViewModel.RadiusMi
    @Binding var limit: NearbyTargetsViewModel.Limit
    @Binding var sort: NearbyTargetsViewModel.SortOption
    @Binding var policyFilter: RecordingPolicyFilter

    var body: some View {
        BlueprintGlassCard {
            VStack(spacing: 12) {
                // Radius chips
                HStack(spacing: 8) {
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
                .tint(BlueprintTheme.brandTeal)

                // Sort selector
                Picker("Sort", selection: $sort) {
                    Text("Highest Payout").tag(NearbyTargetsViewModel.SortOption.highestPayout)
                    Text("Nearest").tag(NearbyTargetsViewModel.SortOption.nearest)
                    Text("Highest Demand").tag(NearbyTargetsViewModel.SortOption.highestDemand)
                }
                .pickerStyle(.segmented)
                .tint(BlueprintTheme.brandTeal)

                // Recording Policy Filter
                HStack(spacing: 8) {
                    Text("Capture Safety:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    policyFilterChip(.all, label: "All")
                    policyFilterChip(.excludeRestricted, label: "Hide Restricted")
                    policyFilterChip(.safeOnly, label: "Safe Only")
                }
            }
        }
    }

    private func policyFilterChip(_ value: RecordingPolicyFilter, label: String) -> some View {
        Button(action: { policyFilter = value }) {
            Text(label)
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule().fill(policyFilter == value ? policyColor(for: value).opacity(0.15) : Color(.systemFill))
                )
                .overlay(
                    Capsule().stroke(policyFilter == value ? policyColor(for: value).opacity(0.5) : Color(.separator).opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(policyFilter == value ? policyColor(for: value) : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func policyColor(for filter: RecordingPolicyFilter) -> Color {
        switch filter {
        case .all: return .secondary
        case .excludeRestricted: return .orange
        case .safeOnly: return .green
        }
    }

    private func radiusChip(_ value: NearbyTargetsViewModel.RadiusMi, label: String) -> some View {
        Button(action: { radius = value }) {
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(radius == value ? BlueprintTheme.primary.opacity(0.12) : Color(.systemFill))
                )
                .overlay(
                    Capsule().stroke(radius == value ? BlueprintTheme.primary.opacity(0.45) : Color(.separator).opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(radius == value ? BlueprintTheme.primary : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

