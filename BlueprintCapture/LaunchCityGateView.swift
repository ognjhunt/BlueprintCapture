import SwiftUI
import CoreLocation
import UIKit

// The full-screen legacy gate views (LaunchCityGateRootView/LaunchCityGateView)
// were removed in the 2026-07 audit cleanup: the launch-city gate ships inside
// BPOnboardingFlow's city step. This file keeps the shared recovery-destination
// and layout-metric types that the shipping flow and tests still use.
enum LaunchCityGateRecoveryDestination {
    static let fallbackSupportEmailAddress = CaptureSupportDestination.fallbackSupportEmailAddress

    static func requestURL(
        mainWebsiteURL: URL?,
        helpCenterURL: URL?,
        supportEmailURL: URL?,
        resolvedCity: ResolvedLaunchCity?
    ) -> URL {
        if let mainWebsiteURL,
           var components = URLComponents(
               url: mainWebsiteURL.appendingPathComponent("capture-app/launch-access"),
               resolvingAgainstBaseURL: false
           ) {
            var queryItems = [URLQueryItem(name: "source", value: "ios-capture-app-launch-gate")]
            if let displayName = resolvedCity?.displayName {
                queryItems.append(URLQueryItem(name: "city", value: displayName))
            }
            components.queryItems = queryItems
            if let url = components.url {
                return url
            }
        }

        if let helpCenterURL {
            return helpCenterURL
        }

        if let supportEmailURL {
            return supportEmailURL
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = fallbackSupportEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Request launch access")
        ]
        return components.url ?? URL(string: "mailto:\(fallbackSupportEmailAddress)")!
    }
}

struct LaunchCityGateLayoutMetrics: Equatable {
    let containerWidth: CGFloat

    var isCompactWidth: Bool { containerWidth <= 400 }
    var heroTitleSize: CGFloat { isCompactWidth ? 32 : 38 }
    var statusTitleSize: CGFloat { isCompactWidth ? 20 : 24 }
    var headerTopPadding: CGFloat { isCompactWidth ? 52 : 68 }
    var usesVerticalStatusLayout: Bool { isCompactWidth }
}
