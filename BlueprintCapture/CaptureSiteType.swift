import Foundation

enum CaptureSiteType: String, CaseIterable, Codable, Identifiable {
    case warehouse
    case manufacturing
    case fulfillment
    case kitchen
    case retail
    case lab
    case hospital
    case office
    case other
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warehouse:
            return "Warehouse"
        case .manufacturing:
            return "Factory / manufacturing"
        case .fulfillment:
            return "Fulfillment / distribution"
        case .kitchen:
            return "Kitchen"
        case .retail:
            return "Retail / grocery"
        case .lab:
            return "Lab"
        case .hospital:
            return "Hospital / care"
        case .office:
            return "Office"
        case .other:
            return "Other"
        case .unknown:
            return "Unknown"
        }
    }

    var manifestValue: String {
        switch self {
        case .manufacturing:
            return "manufacturing"
        case .fulfillment:
            return "fulfillment"
        case .unknown:
            return "unknown"
        default:
            return rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .warehouse, .fulfillment:
            return "shippingbox"
        case .manufacturing:
            return "gearshape.2"
        case .kitchen:
            return "sink"
        case .retail:
            return "storefront"
        case .lab:
            return "testtube.2"
        case .hospital:
            return "cross.case"
        case .office:
            return "building.2"
        case .other:
            return "square.grid.2x2"
        case .unknown:
            return "questionmark.circle"
        }
    }

    static func inferred(from text: String) -> CaptureSiteType? {
        let normalized = text.lowercased()
        if normalized.contains("distribution") || normalized.contains("fulfillment") || normalized.contains("3pl") {
            return .fulfillment
        }
        if normalized.contains("factory") || normalized.contains("manufactur") || normalized.contains("assembly") || normalized.contains("plant") {
            return .manufacturing
        }
        if normalized.contains("warehouse") || normalized.contains("dock") || normalized.contains("pallet") {
            return .warehouse
        }
        if normalized.contains("kitchen") || normalized.contains("restaurant") {
            return .kitchen
        }
        if normalized.contains("grocery") || normalized.contains("retail") || normalized.contains("store") {
            return .retail
        }
        if normalized.contains("lab") || normalized.contains("laboratory") {
            return .lab
        }
        if normalized.contains("hospital") || normalized.contains("clinic") || normalized.contains("care") {
            return .hospital
        }
        if normalized.contains("office") || normalized.contains("workspace") {
            return .office
        }
        return nil
    }
}
