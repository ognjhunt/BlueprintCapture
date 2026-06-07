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

    @Test func captureHandoffRouteParsesOnlyOpaqueHandoffIds() throws {
        let universalLink = try #require(URL(string: "https://tryblueprint.io/capture/open?handoff=opaque-token"))
        let customScheme = try #require(URL(string: "blueprintcapture://capture?handoff=opaque-token"))
        let unsafeDetails = try #require(URL(string: "blueprintcapture://capture?targetName=Dock%20A&captureJobId=job-1"))

        #expect(CaptureHandoffRoute.parse(url: universalLink) == CaptureHandoffRoute(
            handoff: "opaque-token",
            source: .universalLink,
            sourceURL: universalLink
        ))
        #expect(CaptureHandoffRoute.parse(url: customScheme) == CaptureHandoffRoute(
            handoff: "opaque-token",
            source: .customScheme,
            sourceURL: customScheme
        ))
        #expect(CaptureHandoffRoute.parse(url: unsafeDetails) == nil)
    }

    @Test func captureHandoffMetadataDecodesServerAuthority() throws {
        let json = """
        {
          "request_id": "req_123",
          "capture_job_id": "job_456",
          "buyer_request_id": "buyer_789",
          "site_submission_id": "site_101",
          "region_id": "durham-nc",
          "rights_profile": "documented_permission",
          "requested_outputs": ["qualification", "robot_eval_dataset", "task_evaluation_run"],
          "target_name": "Dock A",
          "address_label": "11 Warehouse Way",
          "capture_brief": "Capture approved dock approach and threshold.",
          "privacy_reminder": "Capture only approved areas.",
          "allowed_advisory_hints": ["hold_steady", "slow_down"],
          "truth_boundary": "Display HUD and scan coaching are advisory UX telemetry."
        }
        """

        let metadata = try JSONDecoder().decode(CaptureHandoffMetadata.self, from: Data(json.utf8))

        #expect(metadata.requestId == "req_123")
        #expect(metadata.captureJobId == "job_456")
        #expect(metadata.buyerRequestId == "buyer_789")
        #expect(metadata.siteSubmissionId == "site_101")
        #expect(metadata.regionId == "durham-nc")
        #expect(metadata.rightsProfile == "documented_permission")
        #expect(metadata.requestedOutputs == ["qualification", "robot_eval_dataset", "task_evaluation_run"])
        #expect(metadata.targetName == "Dock A")
        #expect(metadata.addressLabel == "11 Warehouse Way")
        #expect(metadata.allowedAdvisoryHints == ["hold_steady", "slow_down"])
    }
}
