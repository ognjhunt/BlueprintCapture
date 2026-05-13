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

    @Test @MainActor
    func nearbyItemAccessibilityDoesNotPresentEstimatedPayoutAsQuotedTruth() {
        let target = Target(
            id: "place-2",
            displayName: "Dock Two",
            sku: .B,
            lat: 35.99,
            lng: -78.90,
            address: "200 Logistics Way",
            demandScore: 0.7,
            sizeSqFt: nil,
            category: "warehouse",
            computedDistanceMeters: nil
        )

        let item = NearbyTargetsViewModel.NearbyItem(
            id: target.id,
            target: target,
            distanceMiles: 1.2,
            estimatedPayoutUsd: 85,
            recordingPolicy: .unknown
        )

        #expect(item.accessibilityLabel.contains("review gated"))
        #expect(!item.accessibilityLabel.contains("$85"))
        #expect(!item.accessibilityLabel.localizedCaseInsensitiveContains("payout"))
    }
}
