import SwiftUI
import FirebaseAuth

struct ProfileTabView: View {
    private let device = DeviceCapabilityService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // User info card
                    userInfoCard

                    // Navigation links
                    VStack(spacing: 0) {
                        navigationRow(
                            icon: "person.2.fill",
                            title: "Referrals",
                            subtitle: "Earn 10% of friends' captures",
                            tint: BlueprintTheme.brandTeal
                        ) {
                            ReferralDashboardView()
                        }

                        Divider().padding(.leading, 52)

                        navigationRow(
                            icon: "star.circle.fill",
                            title: "Level & Achievements",
                            subtitle: "Track your progress and badges",
                            tint: .orange
                        ) {
                            LevelProgressView()
                        }

                        Divider().padding(.leading, 52)

                        navigationRow(
                            icon: "gearshape.fill",
                            title: "Settings",
                            subtitle: "Account, payouts, preferences",
                            tint: .gray
                        ) {
                            SettingsView()
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // Device info card
                    deviceInfoCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .blueprintAppBackground()
    }

    // MARK: - User Info Card

    private var userInfoCard: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(BlueprintTheme.brandTeal.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(BlueprintTheme.brandTeal)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let user = Auth.auth().currentUser {
                    Text(user.displayName ?? user.email ?? "Capturer")
                        .font(.headline)
                    Text(user.email ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not signed in")
                        .font(.headline)
                    Text("Sign in to track earnings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Device Info Card

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your Device", systemImage: "iphone")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceModel)
                        .font(.subheadline.weight(.medium))
                    Text(device.capabilityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(device.multiplierLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Navigation Row

    private func navigationRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

#Preview {
    ProfileTabView()
        .preferredColorScheme(.dark)
}
