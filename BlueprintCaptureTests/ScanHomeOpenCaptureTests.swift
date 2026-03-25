import Foundation
import Testing
@testable import BlueprintCapture

struct ScanHomeOpenCaptureTests {

    private func makeJobItem(id: String) -> ScanHomeViewModel.JobItem {
        let job = ScanJob(
            id: id,
            title: id,
            address: "123 Main St",
            lat: 35.0,
            lng: -78.0,
            payoutCents: 1000,
            estMinutes: 10,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: [],
            restrictedAreas: [],
            permissionDocURL: nil,
            checkinRadiusM: 100,
            alertRadiusM: 100,
            priority: 1,
            priorityWeight: 1.0,
            regionId: nil,
            jobType: .curatedNearby,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
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
        return ScanHomeViewModel.JobItem(
            job: job,
            distanceMeters: 0,
            distanceMiles: 0,
            targetState: nil,
            permissionTier: .approved,
            opportunityKind: .nearby,
            previewURL: nil,
            previewSource: .mapSnapshot
        )
    }

    @Test
    func nearbyItemsWithOpenCapturePrependsExplicitOpenCaptureItem() {
        let openCapture = makeJobItem(id: ScanHomeViewModel.alphaCurrentLocationJobID)
        let dynamic = [makeJobItem(id: "job-1"), makeJobItem(id: "job-2")]

        let items = ScanHomeViewModel.nearbyItemsWithOpenCapture(
            nearbyDynamic: dynamic,
            openCaptureItem: openCapture
        )

        #expect(items.map(\.id) == [ScanHomeViewModel.alphaCurrentLocationJobID, "job-1", "job-2"])
    }

    @Test
    func nearbyItemsWithOpenCaptureLeavesMarketplaceFeedUntouchedWhenDisabled() {
        let dynamic = [makeJobItem(id: "job-1"), makeJobItem(id: "job-2")]

        let items = ScanHomeViewModel.nearbyItemsWithOpenCapture(
            nearbyDynamic: dynamic,
            openCaptureItem: nil
        )

        #expect(items.map(\.id) == ["job-1", "job-2"])
    }
}
