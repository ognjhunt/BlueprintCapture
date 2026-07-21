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

enum OnboardingCaptureUXCopy {
    static func completionTitle(glassesConnected: Bool) -> String {
        glassesConnected ? "Capture Setup Complete" : "Start with iPhone Capture"
    }

    static func completionMessage(glassesConnected: Bool) -> String {
        glassesConnected
        ? "We'll show assigned-site work, approved opportunities, and review-gated submissions separately. Payout and downstream use depend on backend review."
        : "You can capture assigned or operator-approved facility sites with your iPhone now. Connect glasses later for supported hands-free capture."
    }

    static let disconnectedGlassesSubtitle = "Optional for supported hands-free capture. Assigned-site work, approved jobs, and review submissions can still start with iPhone."
}
