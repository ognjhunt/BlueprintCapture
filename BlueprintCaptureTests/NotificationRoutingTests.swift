import Foundation
import Testing
@testable import BlueprintCapture

struct NotificationRoutingTests {

    @Test func blueprintRouteParsesSupportedRoutes() async throws {
        let scanURL = try #require(URL(string: "blueprint://scan/jobs/job_123"))
        let captureId = UUID()
        let captureURL = try #require(URL(string: "blueprint://wallet/captures/\(captureId.uuidString.lowercased())"))
        let payoutId = UUID()
        let payoutURL = try #require(URL(string: "blueprint://wallet/payouts/\(payoutId.uuidString.lowercased())"))
        let setupURL = try #require(URL(string: "blueprint://wallet/payout-setup"))

        #expect(BlueprintRoute(url: scanURL) == .scanJob(jobId: "job_123"))
        #expect(BlueprintRoute(url: captureURL) == .walletCapture(captureId: captureId))
        #expect(BlueprintRoute(url: payoutURL) == .walletPayout(ledgerEntryId: payoutId))
        #expect(BlueprintRoute(url: setupURL) == .walletPayoutSetup)
    }

    @Test func payloadRoundTripsThroughUserInfo() async throws {
        let captureId = UUID()
        let payload = BlueprintNotificationPayload(
            notificationId: "notification_123",
            type: .captureApproved,
            entityType: .capture,
            entityId: captureId.uuidString.lowercased(),
            route: BlueprintRoute.walletCapture(captureId: captureId).url.absoluteString,
            title: "Capture approved",
            body: "Your capture passed review.",
            metadata: ["foo": "bar"]
        )

        let decoded = try #require(BlueprintNotificationPayload(userInfo: payload.userInfo))
        #expect(decoded.notificationId == payload.notificationId)
        #expect(decoded.type == .captureApproved)
        #expect(decoded.entityType == .capture)
        #expect(decoded.entityId == captureId.uuidString.lowercased())
        #expect(decoded.route == payload.route)
        #expect(decoded.metadata["foo"] == "bar")
    }
}
