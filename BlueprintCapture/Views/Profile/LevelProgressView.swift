import SwiftUI

struct LevelProgressView: View {
    @StateObject private var viewModel = LevelViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Current level card
                levelCard

                // Progress to next level
                if viewModel.currentLevel.nextLevel != nil {
                    progressCard
                }

                // Current benefits
                benefitsCard

                // Next level preview
                if let next = viewModel.currentLevel.nextLevel {
                    nextLevelCard(next)
                }

                // Achievements link
                NavigationLink {
                    AchievementsView()
                } label: {
                    HStack {
                        Label("Achievements", systemImage: "trophy.fill")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.unlockedCount)/\(viewModel.totalCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .blueprintAppBackground()
    }

    // MARK: - Level Card

    private var levelCard: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.currentLevel.icon)
                .font(.system(size: 48))
                .foregroundStyle(levelColor)

            Text(viewModel.currentLevel.displayName)
                .font(.title.weight(.bold))

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(viewModel.captureCount)")
                        .font(.title3.weight(.bold))
                    Text("Captures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", viewModel.avgQualityScore))
                        .font(.title3.weight(.bold))
                    Text("Avg Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(levelColor.opacity(0.1))
        )
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress to \(viewModel.currentLevel.nextLevel?.displayName ?? "")")
                    .font(.headline)
                Spacer()
                Text("\(Int(viewModel.progressToNext * 100))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(levelColor)
            }

            ProgressView(value: viewModel.progressToNext)
                .tint(levelColor)

            if let next = viewModel.currentLevel.nextLevel {
                HStack {
                    Text("\(next.requiredCaptures) captures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(next.requiredAvgQuality))% avg quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Current Benefits", systemImage: "gift.fill")
                .font(.headline)

            ForEach(viewModel.currentLevel.benefits, id: \.self) { benefit in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.successGreen)
                    Text(benefit)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Next Level Preview

    private func nextLevelCard(_ next: CapturerLevel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: next.icon)
                    .foregroundStyle(.secondary)
                Text("Next: \(next.displayName)")
                    .font(.headline)
            }

            Text("Unlocks:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(next.benefits, id: \.self) { benefit in
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(benefit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var levelColor: Color {
        switch viewModel.currentLevel {
        case .novice: return .gray
        case .verified: return BlueprintTheme.brandTeal
        case .expert: return .orange
        case .master: return .purple
        }
    }
}

#Preview {
    NavigationStack {
        LevelProgressView()
    }
    .preferredColorScheme(.dark)
}
