import SwiftUI
import Combine
import FirebaseAuth

struct ProfileTabView: View {
    private let device = DeviceCapabilityService.shared
    @StateObject private var vm = ProfileTabViewModel()

    @State private var profileDigest: String? = nil
    @State private var isLoadingDigest = false
    @State private var activationSnapshot = ActivationFunnelStore.shared.snapshot()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        pageHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 24)

                        // Tier badge card
                        tierBadgeCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)

                        // AI Personalized Digest
                        if isLoadingDigest || profileDigest != nil {
                            aiDigestCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        }

                        // Statistics grid
                        sectionLabel("Statistics")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        statsGrid
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        // Quick nav
                        sectionLabel("Account")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        navLinksCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        sectionLabel("Activation Funnel")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        activationFunnelCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        // Device
                        sectionLabel("Device")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        deviceCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 48)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .blueprintAppBackground()
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: ActivationFunnelStore.changedNotification)) { _ in
            activationSnapshot = ActivationFunnelStore.shared.snapshot()
        }
        .onChange(of: vm.totalCaptures) { _, count in
            guard count > 0, profileDigest == nil else { return }
            Task { await generateDigest() }
        }
    }

    @MainActor
    private func generateDigest() async {
        guard SpaceDraftGenerator.shared.isAvailable, profileDigest == nil else { return }
        isLoadingDigest = true
        let result = await SpaceDraftGenerator.shared.streamProfileDigest(
            tier: vm.tierLabel,
            totalCaptures: vm.totalCaptures,
            approvedCaptures: vm.approvedCaptures
        ) { partial in
            Task { @MainActor in self.profileDigest = partial }
        }
        if let r = result { profileDigest = r }
        isLoadingDigest = false
    }

    // MARK: - AI Digest Card

    private var aiDigestCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(BlueprintTheme.textPrimary)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                    .frame(width: 22)

                if isLoadingDigest && profileDigest == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Color(white: 0.5))
                        Text("Generating your digest…")
                            .font(BlueprintTheme.body(13, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                } else {
                    Text(profileDigest ?? "")
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .blueprintEditorialCard(radius: 14, fill: BlueprintTheme.panel)
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Profile")
                    .font(BlueprintTheme.body(12, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(BlueprintTheme.textTertiary)
                Text("My Account")
                    .font(BlueprintTheme.display(36, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                if let email = Auth.auth().currentUser?.email {
                    Text(email)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                } else {
                    Text("Not signed in")
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
            }
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(BlueprintTheme.panelStrong, in: Circle())
            }
        }
    }

    // MARK: - Tier Badge (Kled-style hexagonal badge)

    private var tierBadgeCard: some View {
        HStack(spacing: 0) {
            // Badge
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "hexagon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(white: 0.22))

                Image(systemName: "b.square.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(BlueprintTheme.brandTeal)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CONTRIBUTOR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(white: 0.4))
                    .tracking(1.5)
                Text(Auth.auth().currentUser?.displayName ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first ?? "Capturer")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(vm.tierLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(vm.tierColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(vm.tierColor.opacity(0.14), in: Capsule())

                    if vm.totalCaptures > 0 {
                        Text("#\(vm.contributorRank)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
            }
            .padding(.leading, 16)

            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(white: 0.14), lineWidth: 1)
        )
    }

    // MARK: - Stats Grid (2x2 like Kled)

    private var statsGrid: some View {
        let items: [(String, String, String, Color)] = [
            ("Total Captures", "\(vm.totalCaptures)", "location.viewfinder", BlueprintTheme.brandTeal),
            ("Earnings", vm.earningsFormatted, "dollarsign.circle.fill", BlueprintTheme.successGreen),
            ("Referrals", "\(vm.referralCount)", "person.2.fill", Color(red: 0.9, green: 0.55, blue: 0.1)),
            ("Approved", "\(vm.approvedCaptures)", "checkmark.shield.fill", Color(white: 0.55))
        ]

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.0) { item in
                statCard(title: item.0, value: item.1, icon: item.2, color: item.3)
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color(white: 0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Nav Links Card

    private var navLinksCard: some View {
        VStack(spacing: 0) {
            accountNavRow(icon: "star.circle.fill", iconBg: Color.orange, title: "Level & Achievements", subtitle: "Track progress and badges") {
                LevelProgressView()
            }

            rowDivider

            accountNavRow(icon: "person.2.fill", iconBg: BlueprintTheme.brandTeal, title: "Referrals", subtitle: "Earn 10% of friends' captures") {
                ReferralDashboardView()
            }

            rowDivider

            accountNavRow(icon: "gearshape.fill", iconBg: Color(white: 0.3), title: "Settings", subtitle: "Account, payouts, preferences") {
                SettingsView()
            }
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private func accountNavRow<Destination: View>(
        icon: String,
        iconBg: Color,
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(iconBg.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 1)
            .padding(.leading, 66)
    }

    // MARK: - Activation Funnel

    private var activationFunnelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activationSnapshot.activationCompleted ? "First capture activated" : "First capture not complete")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(activationSnapshot.dropOffStep.map { "Current drop-off: \($0.rawValue)" } ?? "All tracked steps have at least one event.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.48))
                }
                Spacer()
                Text("\(activationSnapshot.totalEvents)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .accessibilityIdentifier("activation-funnel-total")
            }

            VStack(spacing: 8) {
                ForEach(activationSnapshot.summaries) { summary in
                    HStack(spacing: 10) {
                        Image(systemName: summary.count > 0 ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(summary.count > 0 ? BlueprintTheme.successGreen : Color(white: 0.32))
                            .frame(width: 18)

                        Text(summary.step.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(white: 0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Spacer()

                        Text("\(summary.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("activation-funnel-card")
    }

    // MARK: - Device Card

    private var deviceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceModel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(device.capabilityDescription)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            Text(device.multiplierLabel)
                .font(.headline.weight(.bold))
                .foregroundStyle(BlueprintTheme.successGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Section Label (Kled "STATISTICS" style)

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }
}

// MARK: - View Model

@MainActor
final class ProfileTabViewModel: ObservableObject {
    @Published var totalCaptures: Int = 0
    @Published var approvedCaptures: Int = 0
    @Published var referralCount: Int = 0
    @Published var earningsFormatted: String = "$0.00"
    @Published var contributorRank: Int = 0
    @Published var tierLabel: String = "IRON"
    @Published var tierColor: Color = Color(white: 0.55)

    func load() async {
        guard let history = try? await APIService.shared.fetchCaptureHistory() else { return }
        totalCaptures = history.count
        approvedCaptures = history.filter { $0.status == .approved || $0.status == .paid }.count
        let totalCents = history.compactMap { $0.estimatedPayout }.reduce(Decimal(0), +)
        let dollars = NSDecimalNumber(decimal: totalCents)
        earningsFormatted = NumberFormatter.currency.string(from: dollars) ?? "$0.00"
        updateTier()
    }

    private func updateTier() {
        switch totalCaptures {
        case 0..<5:
            tierLabel = "IRON"
            tierColor = Color(white: 0.55)
        case 5..<20:
            tierLabel = "BRONZE"
            tierColor = Color(red: 0.7, green: 0.45, blue: 0.25)
        case 20..<50:
            tierLabel = "SILVER"
            tierColor = Color(white: 0.7)
        default:
            tierLabel = "GOLD"
            tierColor = Color(red: 0.85, green: 0.72, blue: 0.2)
        }
    }
}

private extension NumberFormatter {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()
}

#Preview {
    ProfileTabView()
        .preferredColorScheme(.dark)
}
