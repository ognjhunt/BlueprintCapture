import Foundation

enum PayoutVerificationStatus: String, Equatable {
    case unavailable
    case notStarted
    case actionRequired
    case pendingReview
    case verified
}

enum PayoutVerificationPrimaryAction: Equatable {
    case signIn
    case continueOnboarding
    case refresh
}

enum PayoutVerificationStepKind: String, CaseIterable, Identifiable {
    case account
    case identity
    case tax
    case payoutMethod
    case payoutActivation

    var id: String { rawValue }
}

struct PayoutVerificationStep: Identifiable, Equatable {
    let kind: PayoutVerificationStepKind
    let title: String
    let detail: String
    let status: PayoutVerificationStatus

    var id: PayoutVerificationStepKind { kind }
}

struct PayoutVerificationSummary: Equatable {
    let overallStatus: PayoutVerificationStatus
    let headline: String
    let detail: String
    let primaryAction: PayoutVerificationPrimaryAction?
    let allowsCashout: Bool
    let steps: [PayoutVerificationStep]

    init(
        isAuthenticated: Bool,
        accountState: StripeAccountState?,
        billingInfo: BillingInfo?,
        payoutAvailability: FeatureAvailability
    ) {
        guard payoutAvailability.isEnabled else {
            let message = payoutAvailability.message ?? "Payout setup is not enabled for this build."
            self.steps = PayoutVerificationSummary.lockedSteps(message: message)
            self.overallStatus = .unavailable
            self.headline = "Payout setup unavailable"
            self.detail = message
            self.primaryAction = nil
            self.allowsCashout = false
            return
        }

        guard isAuthenticated else {
            self.steps = [
                .init(kind: .account, title: "Account", detail: "Sign in before managing payout information.", status: .actionRequired),
                .init(kind: .identity, title: "Identity", detail: "Government ID and selfie checks happen in Stripe when required.", status: .notStarted),
                .init(kind: .tax, title: "Tax details", detail: "Stripe collects tax details when they are required for payouts.", status: .notStarted),
                .init(kind: .payoutMethod, title: "Payout method", detail: "Add a bank account or debit card in Stripe.", status: .notStarted),
                .init(kind: .payoutActivation, title: "Payouts", detail: "Payouts unlock after verification is complete.", status: .notStarted)
            ]
            self.overallStatus = .actionRequired
            self.headline = "Sign in to set up payouts"
            self.detail = "Your payout information is tied to your authenticated Blueprint account."
            self.primaryAction = .signIn
            self.allowsCashout = false
            return
        }

        guard let accountState else {
            self.steps = [
                .init(kind: .account, title: "Account", detail: "Signed in.", status: .verified),
                .init(kind: .identity, title: "Identity", detail: "Start Stripe onboarding to verify identity when required.", status: .notStarted),
                .init(kind: .tax, title: "Tax details", detail: "Start Stripe onboarding to provide required tax information.", status: .notStarted),
                .init(kind: .payoutMethod, title: "Payout method", detail: "Add a payout method in Stripe.", status: .notStarted),
                .init(kind: .payoutActivation, title: "Payouts", detail: "Payouts unlock after Stripe enables transfers.", status: .notStarted)
            ]
            self.overallStatus = .actionRequired
            self.headline = "Set up identity and payouts"
            self.detail = "Blueprint uses Stripe-hosted onboarding so sensitive documents and bank details stay with Stripe."
            self.primaryAction = .continueOnboarding
            self.allowsCashout = false
            return
        }

        let due = Set(accountState.currentlyDueRequirements.map { $0.lowercased() })
        let pendingVerification = Set((accountState.requirementsPendingVerification ?? []).map { $0.lowercased() })

        let identityStatus = Self.status(
            due: due,
            pending: pendingVerification,
            accountState: accountState,
            matcher: Self.isIdentityRequirement
        )
        let taxStatus = Self.status(
            due: due,
            pending: pendingVerification,
            accountState: accountState,
            matcher: Self.isTaxRequirement
        )
        let payoutMethodStatus: PayoutVerificationStatus
        if due.contains(where: Self.isPayoutMethodRequirement) {
            payoutMethodStatus = .actionRequired
        } else if billingInfo != nil {
            payoutMethodStatus = .verified
        } else if accountState.onboardingComplete {
            payoutMethodStatus = .actionRequired
        } else {
            payoutMethodStatus = .notStarted
        }

        let payoutActivationStatus: PayoutVerificationStatus
        if accountState.payoutsEnabled && accountState.isReadyForTransfers && payoutMethodStatus == .verified {
            payoutActivationStatus = .verified
        } else if accountState.hasBlockingRequirements {
            payoutActivationStatus = .actionRequired
        } else if accountState.onboardingComplete {
            payoutActivationStatus = .pendingReview
        } else {
            payoutActivationStatus = .actionRequired
        }

        let resolvedSteps: [PayoutVerificationStep] = [
            .init(kind: .account, title: "Account", detail: "Signed in.", status: .verified),
            .init(kind: .identity, title: "Identity", detail: identityStatus.detail(defaultVerified: "Identity details are submitted."), status: identityStatus),
            .init(kind: .tax, title: "Tax details", detail: taxStatus.detail(defaultVerified: "Tax details are submitted."), status: taxStatus),
            .init(kind: .payoutMethod, title: "Payout method", detail: payoutMethodStatus.detail(defaultVerified: billingInfo.map { "\($0.bankName) ending \($0.lastFour)" } ?? "Payout method connected."), status: payoutMethodStatus),
            .init(kind: .payoutActivation, title: "Payouts", detail: payoutActivationStatus.detail(defaultVerified: "Stripe payouts are enabled."), status: payoutActivationStatus)
        ]

        self.steps = resolvedSteps
        let resolvedOverallStatus: PayoutVerificationStatus
        if resolvedSteps.allSatisfy({ $0.status == .verified }) {
            resolvedOverallStatus = .verified
            self.headline = "Payouts ready"
            self.detail = "Approved captures can be paid out through your verified Stripe account."
            self.primaryAction = nil
        } else if resolvedSteps.contains(where: { $0.status == .actionRequired }) {
            resolvedOverallStatus = .actionRequired
            self.headline = "Verification needed"
            self.detail = "Continue Stripe onboarding to finish the requirements needed before payouts."
            self.primaryAction = .continueOnboarding
        } else {
            resolvedOverallStatus = .pendingReview
            self.headline = "Verification in review"
            self.detail = "Stripe has your submitted information and is checking whether payouts can be enabled."
            self.primaryAction = .refresh
        }
        self.overallStatus = resolvedOverallStatus
        self.allowsCashout = resolvedOverallStatus == .verified && accountState.instantPayoutEligible
    }

    func step(_ kind: PayoutVerificationStepKind) -> PayoutVerificationStep? {
        steps.first { $0.kind == kind }
    }

    private static func lockedSteps(message: String) -> [PayoutVerificationStep] {
        PayoutVerificationStepKind.allCases.map { kind in
            PayoutVerificationStep(
                kind: kind,
                title: kind.defaultTitle,
                detail: message,
                status: .unavailable
            )
        }
    }

    nonisolated private static func status(
        due: Set<String>,
        pending: Set<String>,
        accountState: StripeAccountState,
        matcher: (String) -> Bool
    ) -> PayoutVerificationStatus {
        if due.contains(where: matcher) {
            return .actionRequired
        }
        if pending.contains(where: matcher) {
            return .pendingReview
        }
        return accountState.onboardingComplete ? .verified : .notStarted
    }

    nonisolated private static func isIdentityRequirement(_ field: String) -> Bool {
        field.contains("verification")
            || field.contains("individual.first_name")
            || field.contains("individual.last_name")
            || field.contains("individual.dob")
            || field.contains("individual.address")
            || field.contains("individual.phone")
            || field.contains("individual.email")
            || field.contains("representative")
            || field.contains("owners")
    }

    nonisolated private static func isTaxRequirement(_ field: String) -> Bool {
        field.contains("ssn")
            || field.contains("id_number")
            || field.contains("tax_id")
            || field.contains("ein")
            || field.contains("verification.tax")
    }

    nonisolated private static func isPayoutMethodRequirement(_ field: String) -> Bool {
        field == "external_account"
            || field.contains("external_account")
            || field.contains("bank_account")
            || field.contains("debit_card")
    }
}

private extension PayoutVerificationStatus {
    func detail(defaultVerified: String) -> String {
        switch self {
        case .unavailable:
            return "Unavailable in this build."
        case .notStarted:
            return "Not started."
        case .actionRequired:
            return "Action required in Stripe."
        case .pendingReview:
            return "Submitted and waiting on review."
        case .verified:
            return defaultVerified
        }
    }
}

private extension PayoutVerificationStepKind {
    var defaultTitle: String {
        switch self {
        case .account: return "Account"
        case .identity: return "Identity"
        case .tax: return "Tax details"
        case .payoutMethod: return "Payout method"
        case .payoutActivation: return "Payouts"
        }
    }
}
