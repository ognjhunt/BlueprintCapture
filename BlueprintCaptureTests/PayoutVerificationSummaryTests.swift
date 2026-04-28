import Foundation
import Testing
@testable import BlueprintCapture

struct PayoutVerificationSummaryTests {

    @Test
    func summaryRequiresSignedInAccountBeforePayoutVerification() {
        let summary = PayoutVerificationSummary(
            isAuthenticated: false,
            accountState: nil,
            billingInfo: nil,
            payoutAvailability: .enabled
        )

        #expect(summary.overallStatus == .actionRequired)
        #expect(summary.primaryAction == .signIn)
        #expect(summary.allowsCashout == false)
        #expect(summary.step(.account)?.status == .actionRequired)
        #expect(summary.step(.identity)?.status == .notStarted)
    }

    @Test
    func summaryMapsStripeRequirementsToIdentityTaxAndBankSteps() throws {
        let state = try decodeState(
            """
            {
              "onboarding_complete": false,
              "payouts_enabled": false,
              "payout_schedule": "manual",
              "instant_payout_eligible": false,
              "next_payout": null,
              "requirements_due": [
                "individual.verification.document",
                "individual.ssn_last_4",
                "external_account"
              ],
              "requirements_past_due": ["external_account"],
              "disabled_reason": "requirements.past_due"
            }
            """
        )

        let summary = PayoutVerificationSummary(
            isAuthenticated: true,
            accountState: state,
            billingInfo: nil,
            payoutAvailability: .enabled
        )

        #expect(summary.overallStatus == .actionRequired)
        #expect(summary.primaryAction == .continueOnboarding)
        #expect(summary.allowsCashout == false)
        #expect(summary.step(.account)?.status == .verified)
        #expect(summary.step(.identity)?.status == .actionRequired)
        #expect(summary.step(.tax)?.status == .actionRequired)
        #expect(summary.step(.payoutMethod)?.status == .actionRequired)
        #expect(summary.step(.payoutActivation)?.status == .actionRequired)
    }

    @Test
    func summaryTreatsSubmittedStripeAccountWithoutDueFieldsAsPendingReview() throws {
        let state = try decodeState(
            """
            {
              "onboarding_complete": true,
              "payouts_enabled": false,
              "payout_schedule": "weekly",
              "instant_payout_eligible": false,
              "next_payout": null,
              "requirements_due": null
            }
            """
        )
        let billingInfo = BillingInfo(
            bankName: "Test Bank",
            lastFour: "6789",
            accountHolderName: "A Capturer",
            stripeAccountId: "acct_test"
        )

        let summary = PayoutVerificationSummary(
            isAuthenticated: true,
            accountState: state,
            billingInfo: billingInfo,
            payoutAvailability: .enabled
        )

        #expect(summary.overallStatus == .pendingReview)
        #expect(summary.primaryAction == .refresh)
        #expect(summary.allowsCashout == false)
        #expect(summary.step(.identity)?.status == .verified)
        #expect(summary.step(.tax)?.status == .verified)
        #expect(summary.step(.payoutMethod)?.status == .verified)
        #expect(summary.step(.payoutActivation)?.status == .pendingReview)
    }

    @Test
    func summaryOnlyMarksReadyWhenStripePayoutsAndBankAreVerified() throws {
        let state = try decodeState(
            """
            {
              "onboarding_complete": true,
              "payouts_enabled": true,
              "payout_schedule": "manual",
              "instant_payout_eligible": true,
              "next_payout": null,
              "requirements_due": []
            }
            """
        )
        let billingInfo = BillingInfo(
            bankName: "Test Bank",
            lastFour: "6789",
            accountHolderName: "A Capturer",
            stripeAccountId: "acct_test"
        )

        let summary = PayoutVerificationSummary(
            isAuthenticated: true,
            accountState: state,
            billingInfo: billingInfo,
            payoutAvailability: .enabled
        )

        #expect(summary.overallStatus == .verified)
        #expect(summary.primaryAction == nil)
        #expect(summary.allowsCashout == true)
        #expect(summary.steps.allSatisfy { $0.status == .verified })
    }

    private func decodeState(_ json: String) throws -> StripeAccountState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StripeAccountState.self, from: Data(json.utf8))
    }
}
