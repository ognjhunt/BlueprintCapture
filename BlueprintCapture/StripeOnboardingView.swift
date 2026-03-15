import SwiftUI

struct StripeOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isLoading = false
    @State private var instantAmount: String = ""
    @State private var showConfirmation = false
    @State private var errorMessage: String?
    @State private var accountState: StripeAccountState?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header bar
                    HStack {
                        Image(systemName: "b.square.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.brandTeal)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stripe Payouts")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Connect your bank and manage earnings")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // Account Status
                    if let state = accountState {
                        sectionLabel("Account Status")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        statusCard(state: state)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                    }

                    // KYC
                    sectionLabel("Onboarding")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    kycCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // Payout Schedule
                    sectionLabel("Payout Schedule")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    payoutScheduleCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // Instant Pay
                    sectionLabel("Instant Pay")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    instantPayCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }

            // Loading overlay
            if isLoading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView()
                    .tint(BlueprintTheme.brandTeal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
            isLoading = true
            await loadAccountState()
            isLoading = false
        }
    }

    // MARK: - Status Card

    private func statusCard(state: StripeAccountState) -> some View {
        VStack(spacing: 0) {
            statusRow(
                icon: state.isReadyForTransfers ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                iconColor: state.isReadyForTransfers ? BlueprintTheme.successGreen : Color(red: 0.9, green: 0.55, blue: 0.1),
                title: state.isReadyForTransfers ? "Account Ready" : "Setup Incomplete",
                subtitle: state.isReadyForTransfers ? "You're cleared for payouts" : "Complete onboarding to receive earnings"
            )

            if let next = state.nextPayout {
                kledRowDivider
                let amountStr = next.amount.formatted(.currency(code: "USD"))
                statusRow(
                    icon: "calendar.badge.clock",
                    iconColor: BlueprintTheme.brandTeal,
                    title: "Next Payout",
                    subtitle: "\(next.estimatedArrival.formatted(.dateTime.month(.abbreviated).day().year())) · \(amountStr)"
                )
            }

            if let requirements = state.requirementsDue, !requirements.isEmpty {
                kledRowDivider
                statusRow(
                    icon: "doc.badge.clock",
                    iconColor: Color(red: 0.9, green: 0.55, blue: 0.1),
                    title: "Pending Items",
                    subtitle: requirements.joined(separator: ", ")
                )
            }
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - KYC Card

    private var kycCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(BlueprintTheme.brandTeal.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify Identity (KYC)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Required to enable payouts")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                }

                Spacer()

                Button {
                    openStripeOnboarding()
                } label: {
                    Text(isLoading ? "Loading..." : "Start")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(BlueprintTheme.brandTeal.opacity(0.12), in: Capsule())
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Payout Schedule Card

    private var payoutScheduleCard: some View {
        VStack(spacing: 0) {
            statusRow(
                icon: "calendar",
                iconColor: Color(red: 0.2, green: 0.6, blue: 1.0),
                title: "Weekly Default",
                subtitle: "Mon–Sun earnings paid Wed–Thu"
            )
            kledRowDivider
            statusRow(
                icon: "creditcard.fill",
                iconColor: BlueprintTheme.brandTeal,
                title: "Blueprint Card",
                subtitle: "Auto-deposit after each capture (no fee)"
            )
            kledRowDivider
            statusRow(
                icon: "bolt.fill",
                iconColor: Color(red: 0.9, green: 0.55, blue: 0.1),
                title: "Instant Pay",
                subtitle: "Same-day to debit card (fee applies)"
            )
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Instant Pay Card

    private var instantPayCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.9, green: 0.55, blue: 0.1).opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("Amount in USD", text: $instantAmount)
                    .keyboardType(.numberPad)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Button {
                    triggerInstantPayout()
                } label: {
                    Text("Cash Out")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            (accountState?.instantPayoutEligible == true && Int(instantAmount) != nil && !isLoading)
                                ? .white : Color(white: 0.4)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            (accountState?.instantPayoutEligible == true && Int(instantAmount) != nil && !isLoading)
                                ? BlueprintTheme.successGreen : Color(white: 0.15),
                            in: Capsule()
                        )
                }
                .disabled(isLoading || Int(instantAmount) == nil || !(accountState?.instantPayoutEligible ?? false))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            kledRowDivider

            HStack {
                Text(
                    accountState?.instantPayoutEligible == true
                        ? "Funds arrive within minutes. Bank timing may vary."
                        : "Unlocks after Stripe approves your account."
                )
                .font(.caption)
                .foregroundStyle(Color(white: 0.35))
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

    // MARK: - Row Helpers

    private func statusRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
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
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var kledRowDivider: some View {
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
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            await MainActor.run { self.accountState = state }
        } catch {
            print("[StripeUI] ✗ Error loading account state: \(error)")
            await MainActor.run {
                if self.accountState == nil {
                    self.errorMessage = "Unable to load Stripe account status."
                }
            }
        }
    }

    private func openStripeOnboarding() {
        isLoading = true
        Task {
            do {
                let url = try await StripeConnectService.shared.createOnboardingLink()
                await MainActor.run {
                    isLoading = false
                    _ = openURL(url)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Failed to open onboarding." }
            }
        }
    }

    private func triggerInstantPayout() {
        guard let dollars = Int(instantAmount) else { return }
        let cents = dollars * 100
        isLoading = true
        Task {
            do {
                try await StripeConnectService.shared.triggerInstantPayout(amountCents: cents)
                await loadAccountState()
                await MainActor.run { isLoading = false; showConfirmation = true; instantAmount = "" }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Instant payout failed." }
            }
        }
    }
}

#Preview {
    StripeOnboardingView()
}
