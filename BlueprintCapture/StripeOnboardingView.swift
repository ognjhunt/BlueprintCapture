import SwiftUI

struct StripeOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = false
    @State private var instantAmount: String = ""
    @State private var showConfirmation = false
    @State private var errorMessage: String?
    @State private var accountState: StripeAccountState?
    @State private var billingInfo: BillingInfo?
    @State private var accountLoadState: PayoutAccountStateLoadState = .idle
    @State private var didOpenOnboarding = false
    private let payoutAvailability = RuntimeConfig.current.availability(for: .payouts)

    private var verificationSummary: PayoutVerificationSummary {
        PayoutVerificationSummary(
            isAuthenticated: UserDeviceService.hasRegisteredAccount(),
            accountState: accountState,
            billingInfo: billingInfo,
            payoutAvailability: payoutAvailability
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header bar
                    HStack {
                        Image(systemName: "b.square.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(BlueprintTheme.body(14, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payouts")
                            .font(BlueprintTheme.display(34, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                        Text("Verify identity and connect payouts")
                            .font(BlueprintTheme.body(14, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // Account status banner (if needed)
                    if payoutAvailability.isEnabled == false, let message = payoutAvailability.message {
                        statusBanner(
                            icon: "lock.shield.fill",
                            title: "Payout setup unavailable",
                            subtitle: message,
                            tone: BlueprintTheme.brandTeal
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    } else if let message = accountLoadState.failureMessage {
                        loadFailureBanner(message: message)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    } else if verificationSummary.overallStatus != .verified {
                        statusBanner(
                            icon: verificationSummary.overallStatus == .pendingReview ? "clock.badge.checkmark" : "exclamationmark.triangle.fill",
                            title: verificationSummary.headline,
                            subtitle: verificationSummary.detail,
                            tone: verificationSummary.overallStatus == .pendingReview ? BlueprintTheme.brandTeal : BP.warnLit
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    } else if let next = accountState?.nextPayout {
                        statusBanner(
                            icon: "calendar.badge.clock",
                            title: "Next payout \(next.estimatedArrival.formatted(.dateTime.month(.abbreviated).day()))",
                            subtitle: next.amount.formatted(.currency(code: "USD")),
                            tone: BP.brass
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }

                    // MARK: Verification
                    sectionLabel("Verification")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    verificationSectionCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // MARK: Payout Schedule
                    sectionLabel("Payout Schedule")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    payoutScheduleCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    sectionLabel("Cashout")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    instantPayCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    Text("We never sell or share your personal information.")
                        .font(BlueprintTheme.body(12, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }

            if isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
                    .tint(BP.brass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .blueprintAppBackground()
        .preferredColorScheme(.dark)
        .alert("Done", isPresented: $showConfirmation) {
            Button("OK") { showConfirmation = false }
        } message: {
            Text("Action completed successfully.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadAccountState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, didOpenOnboarding else { return }
            didOpenOnboarding = false
            Task { await loadAccountState() }
        }
    }

    // MARK: - Verification Card

    @ViewBuilder
    private var verificationSectionCard: some View {
        if let message = accountLoadState.failureMessage {
            accountLoadFailureCard(message: message)
        } else {
            verificationChecklistCard
        }
    }

    private var verificationChecklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(verificationSummary.steps) { step in
                verificationStepRow(step)
                if step.kind != verificationSummary.steps.last?.kind {
                    rowDivider
                }
            }

            if verificationSummary.primaryAction == .continueOnboarding {
                Button(action: openStripeOnboarding) {
                    HStack {
                        Text("Continue in Stripe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(white: 0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private func accountLoadFailureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BP.warnLit)
                    .frame(width: 30, height: 30)
                    .background(Color(white: 0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Payout status unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task { await loadAccountState() }
            } label: {
                HStack {
                    Text("Retry status load")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(white: 0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BP.warnLit.opacity(0.24), lineWidth: 1)
        )
    }

    private func verificationStepRow(_ step: PayoutVerificationStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(step.status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor(step.status))
                .frame(width: 30, height: 30)
                .background(Color(white: 0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Status Banner

    private func statusBanner(icon: String, title: String, subtitle: String, tone: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(tone)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tone.opacity(0.22), lineWidth: 1)
        )
    }

    private func loadFailureBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBanner(
                icon: "exclamationmark.triangle.fill",
                title: "Payout status unavailable",
                subtitle: message,
                tone: BP.warnLit
            )

            Button {
                Task { await loadAccountState() }
            } label: {
                Label("Retry status load", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(white: 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Payout Schedule Card

    private var payoutScheduleCard: some View {
        VStack(spacing: 0) {
            scheduleRow(
                icon: "calendar",
                iconColor: BP.brass,
                title: scheduleTitle,
                subtitle: scheduleSubtitle
            )
            rowDivider
            scheduleRow(
                icon: "building.columns.fill",
                iconColor: BP.brass,
                title: "Standard payouts",
                subtitle: "Available after approved captures and Stripe payout enablement"
            )
            rowDivider
            scheduleRow(
                icon: "bolt.fill",
                iconColor: BP.warnLit,
                title: "Provider-gated cashout",
                subtitle: cashoutSubtitle
            )
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private var scheduleTitle: String {
        if accountLoadState.blocksDefaultPayoutState {
            return "Unavailable"
        }
        return accountState?.payoutSchedule.displayName ?? "Not loaded"
    }

    private var scheduleSubtitle: String {
        if accountLoadState.blocksDefaultPayoutState {
            return "Retry before trusting schedule, bank, or payout readiness."
        }
        return "Schedule comes from your connected Stripe account"
    }

    private var cashoutSubtitle: String {
        if accountLoadState.blocksDefaultPayoutState {
            return "Cashout stays locked until Stripe account state loads successfully."
        }
        return accountState?.instantPayoutEligible == true
            ? "Eligible balance is available for a provider cashout request"
            : "Unlocks only when Stripe marks the account eligible"
    }

    private func scheduleRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Cashout Card

    private var instantPayCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(BP.warnLit.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("Amount in USD", text: $instantAmount)
                    .keyboardType(.numberPad)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Button { triggerInstantPayout() } label: {
                    Text("Request")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canCashOut ? BP.ink : Color(white: 0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(canCashOut ? BP.brass : Color(white: 0.15), in: Capsule())
                }
                .disabled(!canCashOut)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            rowDivider

            HStack {
                Text(
                    cashoutSubtitle
                )
                .font(.caption)
                .foregroundStyle(Color(white: 0.3))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private var canCashOut: Bool {
        accountLoadState == .loaded && verificationSummary.allowsCashout && Int(instantAmount) != nil && !isLoading
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 1)
            .padding(.leading, 66)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }

    // MARK: - Actions

    private func loadAccountState() async {
        guard payoutAvailability.isEnabled else {
            await MainActor.run {
                isLoading = false
                accountLoadState = .idle
            }
            return
        }
        await MainActor.run {
            isLoading = true
            accountLoadState = .loading
        }
        do {
            async let stateTask = StripeConnectService.shared.fetchAccountState()
            async let billingTask = APIService.shared.fetchBillingInfo()
            let (state, billing) = try await (stateTask, billingTask)
            await MainActor.run {
                self.accountState = state
                self.billingInfo = billing
                self.accountLoadState = .loaded
                self.isLoading = false
            }
        } catch {
            let loadState = PayoutAccountStateLoadState.failure(from: error)
            await MainActor.run {
                self.accountState = nil
                self.billingInfo = nil
                self.accountLoadState = loadState
                self.isLoading = false
            }
            print("[PayoutsUI] ✗ \(error)")
        }
    }

    private func openStripeOnboarding() {
        guard UserDeviceService.hasRegisteredAccount() else {
            errorMessage = "Sign in before managing payout verification."
            return
        }
        guard payoutAvailability.isEnabled else {
            errorMessage = payoutAvailability.message
            return
        }
        isLoading = true
        Task {
            do {
                try await PayoutDeviceAuthenticationService.shared.authenticate(
                    reason: "Unlock to open Stripe payout verification."
                )
                let url = try await StripeConnectService.shared.createOnboardingLink()
                await MainActor.run {
                    didOpenOnboarding = true
                    isLoading = false
                    openURL(url)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to open verification."
                }
            }
        }
    }

    private func triggerInstantPayout() {
        guard payoutAvailability.isEnabled else {
            errorMessage = payoutAvailability.message
            return
        }
        guard let dollars = Int(instantAmount) else { return }
        isLoading = true
        Task {
            do {
                try await PayoutDeviceAuthenticationService.shared.authenticate(
                    reason: "Unlock to request provider-gated cashout."
                )
                try await StripeConnectService.shared.triggerInstantPayout(amountCents: dollars * 100)
                await loadAccountState()
                await MainActor.run { isLoading = false; showConfirmation = true; instantAmount = "" }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Cashout request failed."
                }
            }
        }
    }

    private func statusIcon(_ status: PayoutVerificationStatus) -> String {
        switch status {
        case .verified:
            return "checkmark.circle.fill"
        case .pendingReview:
            return "clock.fill"
        case .actionRequired:
            return "exclamationmark.circle.fill"
        case .notStarted:
            return "circle"
        case .unavailable:
            return "lock.circle.fill"
        }
    }

    private func statusColor(_ status: PayoutVerificationStatus) -> Color {
        switch status {
        case .verified:
            return BlueprintTheme.successGreen
        case .pendingReview:
            return BlueprintTheme.brandTeal
        case .actionRequired:
            return BP.warnLit
        case .notStarted:
            return Color(white: 0.44)
        case .unavailable:
            return Color(white: 0.5)
        }
    }
}

#Preview {
    StripeOnboardingView()
}
