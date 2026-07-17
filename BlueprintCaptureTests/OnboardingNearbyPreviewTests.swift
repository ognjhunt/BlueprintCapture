import Foundation
import CoreLocation
import Testing
@testable import BlueprintCapture

struct OnboardingNearbyPreviewTests {

    private let userLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
    private let radius = 10.0 * 1609.34

    @Test @MainActor func preview_showsQuotedPayoutsAndNeverFabricatesOne() async throws {
        let quoted = makeJob(
            id: "quoted",
            title: "Mission Market",
            lat: 37.7755,
            lng: -122.4190,
            payoutCents: 4500,
            quotedPayoutCents: 4500
        )
        // Legacy payout_cents with no real quote must NOT surface a payout on the
        // pre-auth preview — quoted-only is the rule for this public surface.
        let unquoted = makeJob(
            id: "unquoted",
            title: "Valencia Hardware",
            lat: 37.7760,
            lng: -122.4185,
            payoutCents: 3000,
            quotedPayoutCents: nil
        )

        let items = OnboardingNearbyPreviewViewModel.buildPreviewItems(
            jobs: [quoted, unquoted],
            candidatePlaces: [],
            userLocation: userLocation,
            feedRadiusMeters: radius
        )

        #expect(items.count == 2)
        let quotedItem = try #require(items.first { $0.id == "job-quoted" })
        #expect(quotedItem.payoutLabel?.contains("45") == true)
        #expect(quotedItem.tier == .approved)
        #expect(quotedItem.isCandidate == false)

        let unquotedItem = try #require(items.first { $0.id == "job-unquoted" })
        #expect(unquotedItem.payoutLabel == nil)
    }

    @Test @MainActor func preview_excludesBlockedJobs() async throws {
        let blocked = makeJob(
            id: "job-blocked",
            title: "Restricted Facility",
            lat: 37.7750,
            lng: -122.4195,
            payoutCents: 9000,
            quotedPayoutCents: 9000,
            restrictedAreas: ["No capture allowed anywhere on site"]
        )

        let items = OnboardingNearbyPreviewViewModel.buildPreviewItems(
            jobs: [blocked],
            candidatePlaces: [],
            userLocation: userLocation,
            feedRadiusMeters: radius
        )

        #expect(items.isEmpty)
    }

    @Test @MainActor func preview_appendsCandidatesDedupedByNameFilteredByRadiusSortedByDistance() async throws {
        let job = makeJob(
            id: "job-1",
            title: "Mission Market",
            lat: 37.7755,
            lng: -122.4190,
            payoutCents: 4500,
            quotedPayoutCents: 4500
        )
        let duplicateOfJob = place(id: "p-dup", name: "Mission Market", lat: 37.7756, lng: -122.4191)
        let farAway = place(id: "p-far", name: "Distant Depot", lat: 38.5000, lng: -122.4194)
        let nearer = place(id: "p-near", name: "Corner Grocery", lat: 37.7752, lng: -122.4194)
        let further = place(id: "p-mid", name: "Ocean Hardware", lat: 37.8100, lng: -122.4194)

        let items = OnboardingNearbyPreviewViewModel.buildPreviewItems(
            jobs: [job],
            candidatePlaces: [duplicateOfJob, farAway, further, nearer],
            userLocation: userLocation,
            feedRadiusMeters: radius
        )

        // Published job first, then candidates by distance; the duplicate and the
        // out-of-radius place never appear.
        #expect(items.map(\.id) == ["job-job-1", "place-p-near", "place-p-mid"])

        let candidate = try #require(items.first { $0.id == "place-p-near" })
        #expect(candidate.isCandidate)
        #expect(candidate.payoutLabel == nil)
        #expect(candidate.tier == nil)
    }

    // MARK: - Factories

    private func place(id: String, name: String, lat: Double, lng: Double) -> PlaceDetailsLite {
        PlaceDetailsLite(
            placeId: id,
            displayName: name,
            formattedAddress: "123 Test St, San Francisco, CA",
            lat: lat,
            lng: lng,
            types: ["supermarket"]
        )
    }

    private func makeJob(
        id: String,
        title: String,
        lat: Double,
        lng: Double,
        payoutCents: Int,
        quotedPayoutCents: Int?,
        restrictedAreas: [String] = ["Back office"]
    ) -> ScanJob {
        ScanJob(
            id: id,
            title: title,
            address: "123 Test St",
            lat: lat,
            lng: lng,
            payoutCents: payoutCents,
            estMinutes: 10,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: ["Sales floor"],
            restrictedAreas: restrictedAreas,
            permissionDocURL: URL(string: "https://example.com/permit.pdf"),
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: "bay-area",
            jobType: .buyerRequestedSpecialTask,
            buyerRequestId: "req-\(id)",
            siteSubmissionId: id,
            quotedPayoutCents: quotedPayoutCents,
            dueWindow: "managed",
            approvalRequirements: ["ops_review"],
            recaptureReason: nil,
            rightsChecklist: ["permission doc"],
            rightsProfile: "documented_permission",
            requestedOutputs: ["qualification", "preview_simulation"],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )
    }
}
