import Foundation
import Testing
@testable import BlueprintCapture

struct NearbyTargetsLaunchPriorityTests {

    @Test @MainActor
    func mergeLaunchPriorityTargetsPrefersResearchBackedContext() {
        let generic = Target(
            id: "place-1",
            displayName: "Dock One",
            sku: .B,
            lat: 30.2672,
            lng: -97.7431,
            address: nil,
            demandScore: 0.55,
            sizeSqFt: nil,
            category: "warehouse",
            computedDistanceMeters: nil
        )

        let launchPriority = Target(
            id: "place-1",
            displayName: "Dock One",
            sku: .B,
            lat: 30.2672,
            lng: -97.7431,
            address: "100 Logistics Way",
            demandScore: 0.92,
            sizeSqFt: nil,
            category: "warehouse",
            launchContext: LaunchTargetContext(
                city: "Austin, TX",
                citySlug: "austin-tx",
                activationStatus: "activation_ready",
                prospectStatus: "approved",
                sourceBucket: "industrial_warehouse",
                workflowFit: "dock handoff",
                priorityNote: "High exact-site value",
                researchBacked: true
            ),
            computedDistanceMeters: nil
        )

        let merged = NearbyTargetsViewModel.mergeLaunchPriorityTargets(
            baseTargets: [generic],
            launchTargets: [launchPriority]
        )

        #expect(merged.count == 1)
        #expect(merged.first?.address == "100 Logistics Way")
        #expect(merged.first?.demandScore == 0.92)
        #expect(merged.first?.launchContext?.citySlug == "austin-tx")
    }
}
