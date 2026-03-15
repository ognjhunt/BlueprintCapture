import SwiftUI

struct ReferralDashboardView: View {
    @StateObject private var viewModel = ReferralViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    // Info banner
                    infoBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // Share & Earn grid
                    sectionLabel("Share & Earn 10%")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    statsGrid
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // Referral History
                    sectionLabel("Referral History")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    referralHistory
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color(white: 0.6))
            }
            .padding(.bottom, 16)

            Text("Affiliate Center")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Track your referral earnings")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Info Banner (Kled left-border style)

    private var infoBanner: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(white: 0.45))
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("10% kickback on referrals")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.85))
                    Text("Share your code. When friends complete their first payout, you get 10% and they get 10% extra.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(white: 0.14), lineWidth: 1)
        )
    }

    // MARK: - Stats Grid (2x2 like Kled Affiliate Center)

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // Total Commissions
            statCard(
                title: "Total Commissions",
                value: viewModel.stats.lifetimeEarnings.formatted(.currency(code: "USD")),
                subtitle: "\(viewModel.stats.activeCapturers) active",
                color: BlueprintTheme.successGreen,
                highlight: false
            )

            // Total Referrals
            statCard(
                title: "Total Referrals",
                value: "\(viewModel.stats.signUps)",
                subtitle: "\(viewModel.stats.invitesSent) invited",
                color: Color(white: 0.55),
                highlight: false
            )

            // Invite Code (teal highlight, Kled green card style)
            inviteCodeCard

            // Invite Friends
            inviteFriendsCard
        }
    }

    private func statCard(title: String, value: String, subtitle: String, color: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(white: 0.45))
                .lineLimit(1)

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(highlight ? color : .white)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private var inviteCodeCard: some View {
        Button {
            UIPasteboard.general.string = viewModel.referralCode
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Invite Code")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.brandTeal.opacity(0.8))
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }

                Text(viewModel.referralCode.isEmpty ? "Loading…" : viewModel.referralCode)
                    .font(.title3.weight(.bold).monospaced())
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .lineLimit(1)

                Text(copied ? "Copied!" : "Tap to copy")
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.brandTeal.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(BlueprintTheme.brandTeal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BlueprintTheme.brandTeal.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var inviteFriendsCard: some View {
        ShareLink(
            item: viewModel.shareMessage,
            subject: Text("Join Blueprint Capture"),
            message: Text("Scan spaces and earn money!")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Invite Friends")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.45))
                }

                Image(systemName: "person.2.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.3))

                Text("Share your code")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(white: 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Referral History

    @ViewBuilder
    private var referralHistory: some View {
        if viewModel.isLoading && viewModel.referrals.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(Color(white: 0.4))
                Spacer()
            }
            .padding(.vertical, 48)
        } else if viewModel.referrals.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "gift")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(white: 0.2))
                Text("No commissions yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.4))
                Text("Invite friends to earn referral commissions")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.3))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            VStack(spacing: 1) {
                ForEach(viewModel.referrals) { referral in
                    referralRow(referral)
                }
            }
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func referralRow(_ referral: Referral) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(referral.referredUserName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    statusBadge(referral.status)
                    Text(referral.referredAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            Spacer()
            if referral.lifetimeEarningsCents > 0 {
                Text(referral.lifetimeEarnings, format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func statusBadge(_ status: ReferralStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.14), in: Capsule())
    }

    private func statusColor(_ status: ReferralStatus) -> Color {
        switch status {
        case .invited: return Color(white: 0.5)
        case .signedUp: return BlueprintTheme.brandTeal
        case .firstCapture: return Color(red: 0.9, green: 0.55, blue: 0.1)
        case .active: return BlueprintTheme.successGreen
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }
}

#Preview {
    NavigationStack {
        ReferralDashboardView()
    }
    .preferredColorScheme(.dark)
}
