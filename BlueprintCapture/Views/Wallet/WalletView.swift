import SwiftUI

struct WalletView: View {
    private struct CaptureRouteSelection: Identifiable {
        let id = UUID()
        let captureId: UUID
    }

    @ObservedObject var glassesManager: GlassesCaptureManager
    @StateObject private var viewModel: WalletViewModel
    private let shouldAutoload: Bool

    @State private var showingStripeOnboarding = false
    @State private var showingAuth = false
    @State private var selectedLedgerTab = 0
    @State private var earningsInsight: String? = nil
    @State private var isLoadingInsight = false
    @State private var selectedCaptureRoute: CaptureRouteSelection?
    @State private var highlightedPayoutId: UUID?
    @State private var routeBanner: String?

    private let ledgerTabs = ["Payouts", "Cashouts", "History"]

    init(glassesManager: GlassesCaptureManager, viewModel: WalletViewModel? = nil, shouldAutoload: Bool = true) {
        self.glassesManager = glassesManager
        self.shouldAutoload = shouldAutoload
        _viewModel = StateObject(wrappedValue: viewModel ?? WalletViewModel())
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    // Status banner
                    if let banner = statusBannerInfo {
                        kledBanner(banner)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    } else if let routeBanner {
                        kledBanner(
                            BannerInfo(
                                icon: "bell.badge.fill",
                                title: "Notification",
                                subtitle: routeBanner,
                                tone: .info,
                                actionTitle: nil,
                                action: {}
                            )
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }

                    // Dark credit card
                    earningsCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    // Pending + cashout row
                    pendingRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // AI Earnings Insight
                    if isLoadingInsight || earningsInsight != nil {
                        aiEarningsInsightCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }

                    // Segmented ledger picker
                    ledgerPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // Ledger content
                    ledgerContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .blueprintAppBackground()
        .sheet(isPresented: $showingStripeOnboarding) { StripeOnboardingView() }
        .sheet(isPresented: $showingAuth) { AuthView() }
        .sheet(item: $selectedCaptureRoute) { selection in
            CaptureDetailView(captureId: selection.captureId)
        }
        .task {
            if shouldAutoload {
                await viewModel.load()
            }
        }
        .onChange(of: viewModel.scansCompleted) { _, count in
            guard count > 0, earningsInsight == nil else { return }
            Task { await generateInsight() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenCaptureDetail)) { note in
            guard let rawId = note.userInfo?["captureId"] as? String,
                  let captureId = UUID(uuidString: rawId) else { return }
            selectedLedgerTab = 2
            routeBanner = nil
            selectedCaptureRoute = CaptureRouteSelection(captureId: captureId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenPayoutEntry)) { note in
            guard let rawId = note.userInfo?["ledgerEntryId"] as? String,
                  let payoutId = UUID(uuidString: rawId) else { return }
            selectedLedgerTab = 0
            highlightedPayoutId = payoutId
            routeBanner = "Showing payout update"
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenPayoutSetup)) { note in
            selectedLedgerTab = 0
            showingStripeOnboarding = true
            if let payload = note.userInfo?["payload"] as? BlueprintNotificationPayload, !payload.body.isEmpty {
                routeBanner = payload.body
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    // MARK: - AI Earnings Insight

    @MainActor
    private func generateInsight() async {
        guard SpaceDraftGenerator.shared.isAvailable, earningsInsight == nil else { return }
        isLoadingInsight = true
        let approved = viewModel.captureHistory.filter { $0.status == .approved || $0.status == .paid }.count
        let pending = viewModel.captureHistory.filter { $0.status == .underReview || $0.status == .submitted }.count
        let fmt = NumberFormatter(); fmt.numberStyle = .currency; fmt.currencyCode = "USD"
        let earningsString = fmt.string(from: NSDecimalNumber(decimal: viewModel.totalEarnings)) ?? "$0.00"
        let result = await SpaceDraftGenerator.shared.streamEarningsInsight(
            totalCaptures: viewModel.scansCompleted,
            approvedCaptures: approved,
            totalEarnings: earningsString,
            pendingCount: pending
        ) { partial in
            Task { @MainActor in self.earningsInsight = partial }
        }
        if let r = result { earningsInsight = r }
        isLoadingInsight = false
    }

    private var aiEarningsInsightCard: some View {
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

                if isLoadingInsight && earningsInsight == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Color(white: 0.5))
                        Text("Generating earnings insight…")
                            .font(BlueprintTheme.body(13, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                } else {
                    Text(earningsInsight ?? "")
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
                Text("Blueprint")
                    .font(BlueprintTheme.display(20, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Text("Wallet")
                    .font(BlueprintTheme.display(36, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Text("Your earnings and payout history")
                    .font(BlueprintTheme.body(14, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
            }
            Spacer()
            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: viewModel.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.isLoading ? BlueprintTheme.textPrimary : BlueprintTheme.textSecondary)
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                    .frame(width: 38, height: 38)
                    .background(BlueprintTheme.panelStrong, in: Circle())
            }
        }
    }

    // MARK: - Status Banner

    private struct BannerInfo {
        let icon: String
        let title: String
        let subtitle: String
        let tone: BannerTone
        let actionTitle: String?
        let action: () -> Void
    }

    private enum BannerTone {
        case warning, error, info
        var color: Color {
            switch self {
            case .warning: return Color(red: 0.9, green: 0.55, blue: 0.1)
            case .error: return Color(red: 0.85, green: 0.25, blue: 0.25)
            case .info: return BlueprintTheme.brandTeal
            }
        }
    }

    private var statusBannerInfo: BannerInfo? {
        if let qc = viewModel.qcStatus, qc.needsFixCount > 0 {
            return BannerInfo(
                icon: "exclamationmark.triangle.fill",
                title: "Quality issues detected",
                subtitle: "\(qc.needsFixCount) capture\(qc.needsFixCount == 1 ? "" : "s") need attention before payout.",
                tone: .error,
                actionTitle: nil,
                action: {}
            )
        }
        let payoutsAvailability = RuntimeConfig.current.availability(for: .payouts)
        if payoutsAvailability.isEnabled == false, let message = payoutsAvailability.message {
            return BannerInfo(
                icon: "lock.shield.fill",
                title: "Payout setup unavailable",
                subtitle: message,
                tone: .info,
                actionTitle: nil,
                action: {}
            )
        }
        if viewModel.stripeAccountState == nil || viewModel.stripeAccountState?.isReadyForTransfers == false {
            return BannerInfo(
                icon: "exclamationmark.circle.fill",
                title: "No payout method connected",
                subtitle: "Connect a payout method to receive earnings.",
                tone: .warning,
                actionTitle: "Connect",
                action: { showingStripeOnboarding = true }
            )
        }
        return nil
    }

    private func kledBanner(_ info: BannerInfo) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(info.tone.color)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: info.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(info.tone.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(info.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(2)
                }

                Spacer()

                if let actionTitle = info.actionTitle {
                    Button(actionTitle, action: info.action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(info.tone.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(info.tone.color.opacity(0.14)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(info.tone.color.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Earnings Card (Kled dark credit card style)

    private var earningsCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Card background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(white: 0.2), lineWidth: 1)
                )

            // Decorative circle
            Circle()
                .fill(BlueprintTheme.brandTeal.opacity(0.07))
                .frame(width: 220, height: 220)
                .offset(x: 160, y: -40)

            Circle()
                .fill(BlueprintTheme.successGreen.opacity(0.05))
                .frame(width: 160, height: 160)
                .offset(x: 200, y: 40)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Top row: logo + subtitle
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "b.square.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BlueprintTheme.brandTeal)
                        Text("Blueprint Cash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.65))
                    }
                    Spacer()
                }
                .padding(.bottom, 24)

                // Balance
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.totalEarnings, format: .currency(code: "USD"))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        balanceStat(label: "Pending", value: viewModel.totalPending, color: BlueprintTheme.brandTeal)
                        balanceStat(label: "Scans", value: nil, intValue: viewModel.scansCompleted, color: Color(white: 0.55))
                        if viewModel.referralEarningsCents > 0 || viewModel.referralBonusCents > 0 {
                            let totalReferralCents = viewModel.referralEarningsCents + viewModel.referralBonusCents
                            balanceStat(
                                label: "Referrals",
                                value: Decimal(totalReferralCents) / 100,
                                color: BlueprintTheme.successGreen
                            )
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(height: 180)
        .clipped()
    }

    private func balanceStat(label: String, value: Decimal?, intValue: Int? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let value {
                Text(value, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            } else if let intValue {
                Text("\(intValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.4))
        }
    }

    // MARK: - Pending / Cashout Row

    private var pendingRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                Text("\(viewModel.scansCompleted) captures • \(viewModel.captureHistory.filter { $0.status == .underReview || $0.status == .submitted }.count) pending review")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            Button {
                showingStripeOnboarding = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption.weight(.semibold))
                    Text("Cashout")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color(white: 0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(white: 0.13), in: Capsule())
                .overlay(Capsule().stroke(Color(white: 0.2), lineWidth: 1))
            }
        }
    }

    // MARK: - Segmented Picker (Kled-style)

    private var ledgerPicker: some View {
        HStack(spacing: 2) {
            ForEach(Array(ledgerTabs.enumerated()), id: \.offset) { idx, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedLedgerTab = idx }
                } label: {
                    Text(tab)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedLedgerTab == idx ? .white : Color(white: 0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedLedgerTab == idx
                                ? Color(white: 0.18)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ledger Content

    @ViewBuilder
    private var ledgerContent: some View {
        switch selectedLedgerTab {
        case 0:
            payoutsTab
        case 1:
            cashoutsTab
        default:
            historyTab
        }
    }

    @ViewBuilder
    private var payoutsTab: some View {
        if payoutEntries.isEmpty {
            emptyState(icon: "banknote", message: "No payouts yet", subtitle: "Approved captures will appear here.")
        } else {
            VStack(spacing: 1) {
                ForEach(payoutEntries.prefix(12)) { entry in
                    ledgerRow(
                        title: entry.scheduledFor.formatted(.dateTime.month().day().year()),
                        subtitle: entry.statusLabel,
                        amount: entry.amount,
                        isPositive: entry.status == .paid
                    )
                }
            }
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var payoutEntries: [PayoutLedgerEntry] {
        if let highlightedPayoutId {
            let filtered = viewModel.payoutLedger.filter { $0.id == highlightedPayoutId }
            return filtered.isEmpty ? viewModel.payoutLedger : filtered
        }
        return viewModel.payoutLedger
    }

    private var cashoutsTab: some View {
        emptyState(icon: "arrow.up.circle", message: "No cashouts yet", subtitle: "Cashouts will appear here once processed.")
    }

    private var historyTab: some View {
        Group {
            if viewModel.captureHistory.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    message: viewModel.isAuthenticated ? "No captures yet." : "Log in to see your history.",
                    subtitle: nil
                )
            } else {
                VStack(spacing: 1) {
                    ForEach(viewModel.captureHistory.prefix(12)) { entry in
                        NavigationLink {
                            CaptureDetailView(entry: entry)
                        } label: {
                            ledgerRowContent(
                                title: entry.targetAddress,
                                subtitle: entry.statusLabel,
                                amount: entry.estimatedPayout,
                                isPositive: entry.status == .paid,
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Row helpers

    private func ledgerRow(title: String, subtitle: String, amount: Decimal, isPositive: Bool) -> some View {
        ledgerRowContent(
            title: title,
            subtitle: subtitle,
            amount: amount,
            isPositive: isPositive,
            showChevron: false
        )
    }

    private func ledgerRowContent(title: String, subtitle: String, amount: Decimal?, isPositive: Bool, showChevron: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()

            if let amount {
                Text(amount, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPositive ? BlueprintTheme.successGreen : Color(white: 0.7))
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func emptyState(icon: String, message: String, subtitle: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color(white: 0.2))

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(white: 0.4))

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Extensions

private extension CaptureHistoryEntry {
    var statusLabel: String {
        switch status {
        case .draft: return "Draft"
        case .readyToSubmit: return "Ready to submit"
        case .submitted: return "Submitted"
        case .underReview: return "Under review"
        case .processing: return "Processing"
        case .qc: return "Quality check"
        case .approved: return "Approved"
        case .needsRecapture: return "Needs recapture"
        case .needsFix: return "Needs fix"
        case .rejected: return "Rejected"
        case .paid: return "Paid"
        }
    }
}

private extension PayoutLedgerEntry {
    var statusLabel: String {
        switch status {
        case .pending: return "Pending"
        case .inTransit: return "In transit"
        case .paid: return "Paid"
        case .failed: return "Failed"
        }
    }
}
