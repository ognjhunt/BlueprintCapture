import SwiftUI

struct AchievementsView: View {
    @StateObject private var viewModel = LevelViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                HStack {
                    Text("\(viewModel.unlockedCount) of \(viewModel.totalCount) unlocked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.achievements) { achievement in
                        achievementCard(achievement)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load() }
        .blueprintAppBackground()
    }

    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(spacing: 8) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundStyle(achievement.isUnlocked ? BlueprintTheme.brandTeal : .secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(achievement.isUnlocked
                              ? BlueprintTheme.brandTeal.opacity(0.15)
                              : Color(.tertiarySystemFill))
                )

            Text(achievement.title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
                .lineLimit(2)

            if let date = achievement.unlockedAt {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .opacity(achievement.isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    NavigationStack {
        AchievementsView()
    }
    .preferredColorScheme(.dark)
}
