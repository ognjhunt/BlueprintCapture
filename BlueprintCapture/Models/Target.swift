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


