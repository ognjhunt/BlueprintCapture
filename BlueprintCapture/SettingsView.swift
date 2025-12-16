import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingStripeOnboarding = false
    @State private var showingEditProfile = false
    @State private var showingAuth = false
    @State private var showingGlassesCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile & Earnings Card
                    profileEarningsCard

                    // Bank Account Card
                    bankAccountCard

                    // Quick Actions
                    quickActionsCard

                    // Account Settings
                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .blueprintAppBackground()
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showingStripeOnboarding) {
            StripeOnboardingView()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .sheet(isPresented: $showingGlassesCapture) {
            GlassesCaptureView()
        }
        .task {
            await viewModel.loadUserData()
        }
    }

    // MARK: - Profile & Earnings

    private var profileEarningsCard: some View {
        VStack(spacing: 16) {
            // Profile header
            HStack(spacing: 14) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.profile.fullName.isEmpty ? "Welcome" : viewModel.profile.fullName)
                        .font(.title3.weight(.semibold))

                    if !viewModel.profile.email.isEmpty {
                        Text(viewModel.profile.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if viewModel.isAuthenticated {
                    Button {
                        viewModel.startEditingProfile()
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Earnings summary
            HStack(spacing: 0) {
                earningsStat(
                    value: viewModel.totalEarnings,
                    label: "Total Earned",
                    color: BlueprintTheme.successGreen
                )

                Divider()
                    .frame(height: 40)

                earningsStat(
                    value: viewModel.pendingPayout,
                    label: "Pending",
                    color: BlueprintTheme.primary
                )

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("\(viewModel.scansCompleted)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Scans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func earningsStat(value: Decimal, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .currency(code: "USD"))
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bank Account

    private var bankAccountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Payouts", systemImage: "creditcard.fill")
                .font(.headline)

            if let billingInfo = viewModel.billingInfo {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BlueprintTheme.successGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(billingInfo.bankName) ••••\(billingInfo.lastFour)")
                            .font(.subheadline.weight(.medium))
                        Text("Weekly payouts enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Change") {
                        showingStripeOnboarding = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BlueprintTheme.primary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BlueprintTheme.successGreen.opacity(0.1))
                )
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(BlueprintTheme.warningOrange)
                        Text("Connect a bank account to receive payouts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Button {
                        showingStripeOnboarding = true
                    } label: {
                        Text("Connect Bank Account")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Quick Actions

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Capture Modes", systemImage: "camera.fill")
                .font(.headline)

            Button {
                showingGlassesCapture = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "eyeglasses")
                        .font(.title2)
                        .foregroundStyle(BlueprintTheme.brandTeal)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meta Glasses")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Hands-free capture with smart glasses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Account Settings

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isAuthenticated {
                settingsRow(icon: "person.crop.circle", title: "Edit Profile") {
                    viewModel.startEditingProfile()
                    showingEditProfile = true
                }

                Divider().padding(.leading, 52)

                settingsRow(icon: "lock.shield", title: "Privacy & Security") {
                    // Future: Privacy settings
                }

                Divider().padding(.leading, 52)

                settingsRow(icon: "arrow.right.square", title: "Sign Out", isDestructive: true) {
                    Task { await viewModel.signOut() }
                }
            } else {
                settingsRow(icon: "person.crop.circle.badge.plus", title: "Sign Up / Log In") {
                    showingAuth = true
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func settingsRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(isDestructive ? BlueprintTheme.errorRed : .secondary)

                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? BlueprintTheme.errorRed : .primary)

                Spacer()

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
