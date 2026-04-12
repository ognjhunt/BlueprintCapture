import Foundation
import CoreLocation
import Combine

enum SKU: String, Codable, CaseIterable {
    case A, B, C
}

struct Target: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let sku: SKU
    let lat: Double
    let lng: Double
    let address: String?
    let demandScore: Double?
    let sizeSqFt: Int?
    let category: String?
    let launchContext: LaunchTargetContext?

    // Transient values (not part of API) – compute in ViewModel
    var computedDistanceMeters: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case sku
        case lat
        case lng
        case address
        case demandScore
        case sizeSqFt
        case category
        case launchContext
    }

    init(
        id: String,
        displayName: String,
        sku: SKU,
        lat: Double,
        lng: Double,
        address: String?,
        demandScore: Double?,
        sizeSqFt: Int?,
        category: String?,
        launchContext: LaunchTargetContext? = nil,
        computedDistanceMeters: Double?
    ) {
        self.id = id
        self.displayName = displayName
        self.sku = sku
        self.lat = lat
        self.lng = lng
        self.address = address
        self.demandScore = demandScore
        self.sizeSqFt = sizeSqFt
        self.category = category
        self.launchContext = launchContext
        self.computedDistanceMeters = computedDistanceMeters
    }
}

struct LaunchTargetContext: Codable, Equatable {
    let city: String
    let citySlug: String
    let activationStatus: String
    let prospectStatus: String
    let sourceBucket: String
    let workflowFit: String?
    let priorityNote: String?
    let researchBacked: Bool

    var badgeLabel: String {
        switch prospectStatus {
        case "capturing":
            return "Launch Live"
        case "onboarded":
            return "Launch Ready"
        default:
            return "Launch Priority"
        }
    }
}

extension Target {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Recording Policy Conformance

extension Target: PlaceWithPolicy {
    var policyName: String { displayName }
    var policyTypes: [String] { category.map { [$0] } ?? [] }
    var policyPlaceId: String? { id }
}
