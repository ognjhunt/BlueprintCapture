import Foundation
import Testing

struct ReleaseSupplyGuardTests {

    @Test
    func productionSourcesDoNotDefaultToMockTargetsPricingOrExampleEndpoints() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let guardedFiles = [
            "BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift",
            "BlueprintCapture/Services/TargetsAPI.swift",
            "BlueprintCapture/Services/PricingAPI.swift",
        ]

        var combinedSource = ""
        for relativePath in guardedFiles {
            let url = root.appendingPathComponent(relativePath)
            combinedSource += try String(contentsOf: url, encoding: .utf8)
            combinedSource += "\n"
        }

        #expect(!combinedSource.contains("targetsAPI: TargetsAPIProtocol = MockTargetsAPI()"))
        #expect(!combinedSource.contains("pricingAPI: PricingAPIProtocol = MockPricingAPI()"))
        #expect(!combinedSource.contains("https://api.example.com"))
    }
}
