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
                        Text("Payouts")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Set up identity verification and payouts")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // Account status banner (if needed)
                    if let state = accountState {
                        if !state.isReadyForTransfers {
                            statusBanner(
                                icon: "exclamationmark.triangle.fill",
                                title: "Setup incomplete",
                                subtitle: "Complete verification to receive payouts.",
                                tone: Color(red: 0.9, green: 0.55, blue: 0.1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        } else if let next = state.nextPayout {
                            statusBanner(
                                icon: "calendar.badge.clock",
                                title: "Next payout \(next.estimatedArrival.formatted(.dateTime.month(.abbreviated).day()))",
                                subtitle: next.amount.formatted(.currency(code: "USD")),
                                tone: BlueprintTheme.brandTeal
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }

                    // MARK: Identity Verification
                    sectionLabel("Identity")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    kycStepCard(
                        icon: "person.badge.shield.checkmark",
                        title: "ID Verification",
                        bullets: ["Government-issued photo ID", "Passport, driver's license, or national ID"],
                        isVerified: accountState?.isReadyForTransfers == true,
                        actionTitle: "Start Verification",
                        action: openStripeOnboarding
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    kycStepCard(
                        icon: "faceid",
                        title: "Liveness & Face Match",
                        bullets: ["Quick selfie for face match", "Completed automatically with Step 1"],
                        isVerified: accountState?.isReadyForTransfers == true,
                        actionTitle: nil,
                        action: {}
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    kycStepCard(
                        icon: "doc.plaintext",
                        title: "Tax Information",
                        bullets: ["Required for payments over $600/year", "US citizens: W-9 · International: W-8BEN"],
                        isVerified: accountState?.isReadyForTransfers == true,
                        actionTitle: "Submit Tax Info",
                        action: openStripeOnboarding
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // MARK: Payout Schedule
                    sectionLabel("Payout Schedule")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    payoutScheduleCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // MARK: Instant Pay
                    sectionLabel("Instant Pay")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    instantPayCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    Text("We never sell or share your personal information.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.3))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }

            if isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
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

    // MARK: - KYC Step Card (Kled-style separate cards with UNVERIFIED badge)

    private func kycStepCard(
        icon: String,
        title: String,
        bullets: [String],
        isVerified: Bool,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.14), in: Circle())

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Text(isVerified ? "VERIFIED" : "UNVERIFIED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(isVerified ? BlueprintTheme.successGreen : Color(red: 0.9, green: 0.55, blue: 0.1))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (isVerified ? BlueprintTheme.successGreen : Color(red: 0.9, green: 0.55, blue: 0.1)).opacity(0.15),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Bullets
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color(white: 0.35))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, actionTitle != nil ? 12 : 16)

            // Action button (inside card, Kled style)
            if let actionTitle, !isVerified {
                Button(action: action) {
                    HStack {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.right")
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

    // MARK: - Payout Schedule Card

    private var payoutScheduleCard: some View {
        VStack(spacing: 0) {
            scheduleRow(
                icon: "calendar",
                iconColor: Color(red: 0.2, green: 0.6, blue: 1.0),
                title: "Weekly Default",
                subtitle: "Mon–Sun earnings paid Wed–Thu"
            )
            rowDivider
            scheduleRow(
                icon: "creditcard.fill",
                iconColor: BlueprintTheme.brandTeal,
                title: "Blueprint Card",
                subtitle: "Auto-deposit after each capture (no fee)"
            )
            rowDivider
            scheduleRow(
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

                Button { triggerInstantPayout() } label: {
                    Text("Cash Out")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canCashOut ? .white : Color(white: 0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(canCashOut ? BlueprintTheme.successGreen : Color(white: 0.15), in: Capsule())
                }
                .disabled(!canCashOut)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            rowDivider

            HStack {
                Text(
                    accountState?.instantPayoutEligible == true
                        ? "Funds arrive within minutes. Bank timing may vary."
                        : "Unlocks after your account is verified."
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
        accountState?.instantPayoutEligible == true && Int(instantAmount) != nil && !isLoading
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
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            await MainActor.run { self.accountState = state }
        } catch {
            print("[PayoutsUI] ✗ \(error)")
        }
    }

    private func openStripeOnboarding() {
        isLoading = true
        Task {
            do {
                let url = try await StripeConnectService.shared.createOnboardingLink()
                await MainActor.run { isLoading = false; _ = openURL(url) }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Failed to open verification." }
            }
        }
    }

    private func triggerInstantPayout() {
        guard let dollars = Int(instantAmount) else { return }
        isLoading = true
        Task {
            do {
                try await StripeConnectService.shared.triggerInstantPayout(amountCents: dollars * 100)
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
