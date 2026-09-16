import Foundation

enum OnboardingFirstCaptureGoal: String, CaseIterable, Identifiable {
    static let storageKey = "com.blueprint.firstCaptureGoal"

    case assignedOrApprovedSite = "current_place_raw_capture"
    case nearbyOpportunity = "nearby_approved_opportunity"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assignedOrApprovedSite:
            return "Capture an assigned or approved facility site"
        case .nearbyOpportunity:
            return "Review nearby opportunities before recording"
        }
    }

    var subtitle: String {
        switch self {
        case .assignedOrApprovedSite:
            return "Use a Blueprint assignment or a site/operator-approved industrial, logistics, warehouse, lab, retail backroom, or facility task area."
        case .nearbyOpportunity:
            return "Use the feed only when an opportunity is approved or explicitly review-gated, not as a payout promise."
        }
    }

    var icon: String {
        switch self {
        case .assignedOrApprovedSite:
            return "building.2.crop.circle"
        case .nearbyOpportunity:
            return "location.viewfinder"
        }
    }
}
