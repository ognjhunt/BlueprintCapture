import SwiftUI

struct ReferralDashboardView: View {
    @StateObject private var viewModel = ReferralViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero card
                heroCard

                // Stats
                statsRow

                // Share section
                shareSection

                // Referral list
                referralListCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Referrals")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .blueprintAppBackground()
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(BlueprintTheme.brandTeal)

            Text("Earn 10% of their captures, forever")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Invite friends to Blueprint Capture. You earn 10% of every capture they get paid for — no cap, no expiry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BlueprintTheme.brandTeal.opacity(0.1))
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(viewModel.stats.invitesSent)", label: "Invited")
            Divider().frame(height: 36)
            statCell(value: "\(viewModel.stats.signUps)", label: "Signed Up")
            Divider().frame(height: 36)
            statCell(value: "\(viewModel.stats.activeCapturers)", label: "Active")
            Divider().frame(height: 36)
            VStack(spacing: 4) {
                Text(viewModel.stats.lifetimeEarnings, format: .currency(code: "USD"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("Earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Share Section

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Referral Code", systemImage: "qrcode")
                .font(.headline)

            // Code display + copy
            HStack {
                Text(viewModel.referralCode)
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Spacer()

                Button {
                    UIPasteboard.general.string = viewModel.referralCode
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(BlueprintTheme.brandTeal)
            }

            // Share button
            ShareLink(
                item: viewModel.shareMessage,
                subject: Text("Join Blueprint Capture"),
                message: Text("Scan spaces and earn money!")
            ) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Invite Link")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Referral List

    private var referralListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your Referrals", systemImage: "person.3.fill")
                .font(.headline)

            if viewModel.isLoading && viewModel.referrals.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(BlueprintTheme.brandTeal)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.referrals.isEmpty {
                Text("No referrals yet. Share your code to start earning!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.referrals) { referral in
                    referralRow(referral)
                    if referral.id != viewModel.referrals.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func referralRow(_ referral: Referral) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(referral.referredUserName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    statusBadge(referral.status)
                    Text(referral.referredAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if referral.lifetimeEarningsCents > 0 {
                Text(referral.lifetimeEarnings, format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }
        }
    }

    private func statusBadge(_ status: ReferralStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(statusColor(status).opacity(0.15))
            )
    }

    private func statusColor(_ status: ReferralStatus) -> Color {
        switch status {
        case .invited: return .secondary
        case .signedUp: return BlueprintTheme.brandTeal
        case .firstCapture: return .orange
        case .active: return BlueprintTheme.successGreen
        }
    }
}

#Preview {
    NavigationStack {
        ReferralDashboardView()
    }
    .preferredColorScheme(.dark)
}
