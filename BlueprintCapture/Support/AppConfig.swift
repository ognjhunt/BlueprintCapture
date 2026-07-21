import Foundation

enum AppConfig {
    static let pendingStartScanJobIdKey = "com.blueprint.pendingStartScanJobId"
    static let pendingNotificationRouteKey = "com.blueprint.pendingNotificationRoute"

    static func backendBaseURL() -> URL? {
        RuntimeConfig.current.backendBaseURL
    }

    static func hasBackendBaseURL() -> Bool {
        backendBaseURL() != nil
    }

    static func demandBackendBaseURL() -> URL? {
        RuntimeConfig.current.demandBackendBaseURL
    }

    static func hasDemandBackendBaseURL() -> Bool {
        demandBackendBaseURL() != nil
    }

    static func allowMockJobsFallback() -> Bool {
        RuntimeConfig.current.allowMockJobsFallback
    }

    static func enableInternalTestSpace() -> Bool {
        RuntimeConfig.current.enableInternalTestSpace
    }

    static func enableRemoteNotifications() -> Bool {
        RuntimeConfig.current.enableRemoteNotifications
    }

    static func mainWebsiteURL() -> URL? {
        RuntimeConfig.current.websiteURL
    }

    static func helpCenterURL() -> URL? {
        RuntimeConfig.current.helpCenterURL
    }

    static func bugReportURL() -> URL? {
        RuntimeConfig.current.bugReportURL
    }

    static func termsOfServiceURL() -> URL? {
        RuntimeConfig.current.termsOfServiceURL
    }

    static func privacyPolicyURL() -> URL? {
        RuntimeConfig.current.privacyPolicyURL
    }

    static func capturePolicyURL() -> URL? {
        RuntimeConfig.current.capturePolicyURL
    }

    static func accountDeletionURL() -> URL? {
        RuntimeConfig.current.accountDeletionURL
    }

    static func supportEmailAddress() -> String? {
        RuntimeConfig.current.supportEmailAddress
    }

    static func effectiveSupportEmailAddress() -> String {
        CaptureSupportDestination.supportEmailAddress(configuredAddress: supportEmailAddress())
    }

    static func supportEmailURL(subject: String? = nil) -> URL? {
        CaptureSupportDestination.supportEmailURL(
            configuredAddress: supportEmailAddress(),
            subject: subject
        )
    }

    static func helpCenterOrBetaGuideURL() -> URL {
        CaptureSupportDestination.helpCenterURL(
            configuredURL: helpCenterURL(),
            betaGuideURL: betaCapturerGuideURL()
        )
    }

    static func bugReportOrSupportURL() -> URL {
        CaptureSupportDestination.bugReportURL(
            configuredURL: bugReportURL(),
            configuredSupportEmail: supportEmailAddress()
        )
    }

    static func betaCapturerGuideURL() -> URL {
        BetaCohortGuideDestination.capturerGuideURL(mainWebsiteURL: mainWebsiteURL())
    }

    static func betaBuyerGuideURL() -> URL {
        BetaCohortGuideDestination.buyerGuideURL(mainWebsiteURL: mainWebsiteURL())
    }

    // MARK: - Reservation Guards
    static func maxReservationDriveMinutes() -> Int {
        RuntimeConfig.current.maxReservationDriveMinutes
    }

    static func fallbackMaxReservationAirMiles() -> Double {
        RuntimeConfig.current.fallbackMaxReservationAirMiles
    }

    // MARK: - Testing Overrides
    static func allowOffsiteCheckIn() -> Bool {
        RuntimeConfig.current.allowOffsiteCheckIn
    }
}

struct BetaCohortGuideDestination {
    private static let fallbackWebsiteURL = URL(string: "https://www.tryblueprint.io")!

    static func capturerGuideURL(mainWebsiteURL: URL?) -> URL {
        guideURL(pathComponents: ["beta", "capturer-guide"], mainWebsiteURL: mainWebsiteURL)
    }

    static func buyerGuideURL(mainWebsiteURL: URL?) -> URL {
        guideURL(pathComponents: ["beta", "buyer-guide"], mainWebsiteURL: mainWebsiteURL)
    }

    private static func guideURL(pathComponents: [String], mainWebsiteURL: URL?) -> URL {
        let baseURL = mainWebsiteURL ?? fallbackWebsiteURL
        return pathComponents.reduce(baseURL) { url, pathComponent in
            url.appendingPathComponent(pathComponent)
        }
    }
}

struct CaptureSupportDestination {
    static let fallbackSupportEmailAddress = "support@tryblueprint.io"

    static func supportEmailAddress(configuredAddress: String?) -> String {
        let trimmed = configuredAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallbackSupportEmailAddress : trimmed
    }

    static func supportEmailURL(configuredAddress: String?, subject: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmailAddress(configuredAddress: configuredAddress)
        if let subject, subject.isEmpty == false {
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        }
        return components.url
    }

    static func helpCenterURL(configuredURL: URL?, betaGuideURL: URL) -> URL {
        configuredURL ?? betaGuideURL
    }

    static func bugReportURL(configuredURL: URL?, configuredSupportEmail: String?) -> URL {
        configuredURL ?? supportEmailURL(
            configuredAddress: configuredSupportEmail,
            subject: "Blueprint Capture Bug Report"
        ) ?? URL(string: "mailto:\(fallbackSupportEmailAddress)")!
    }
}

struct CaptureLegalConsentPolicy: Equatable {
    struct RequiredLink: Equatable {
        let title: String
        let url: URL?
    }

    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?
    let capturePolicyURL: URL?

    /// Bump when the acknowledgement text or the linked policies materially
    /// change — a stored acceptance of an older version means re-consent is due.
    static let consentVersion = "2026-07-21"

    static let acknowledgementText = "I confirm I have permission to capture this site, will avoid restricted or private areas, and agree to Blueprint's Terms of Service, Privacy Policy, and Capture Policy before recording or uploading evidence."

    static let missingLegalLinksMessage = "Capture consent is unavailable until Terms of Service, Privacy Policy, and Capture Policy links are configured for this build."

    static func current() -> CaptureLegalConsentPolicy {
        CaptureLegalConsentPolicy(
            termsOfServiceURL: AppConfig.termsOfServiceURL(),
            privacyPolicyURL: AppConfig.privacyPolicyURL(),
            capturePolicyURL: AppConfig.capturePolicyURL()
        )
    }

    var requiredLinks: [RequiredLink] {
        [
            RequiredLink(title: "Terms of Service", url: termsOfServiceURL),
            RequiredLink(title: "Privacy Policy", url: privacyPolicyURL),
            RequiredLink(title: "Capture Policy", url: capturePolicyURL)
        ]
    }

    var missingRequiredLinkTitles: [String] {
        requiredLinks.compactMap { link in
            link.url == nil ? link.title : nil
        }
    }

    var hasRequiredLegalLinks: Bool {
        missingRequiredLinkTitles.isEmpty
    }

    func canContinue(hasAcknowledged: Bool, isBusy: Bool = false) -> Bool {
        hasAcknowledged && hasRequiredLegalLinks && !isBusy
    }
}

extension Notification.Name {
    static let blueprintNotificationAction = Notification.Name("Blueprint.NotificationAction")
    static let AuthStateDidChange = Notification.Name("Blueprint.AuthStateDidChange")
    static let FirebaseGuestBootstrapStateDidChange = Notification.Name("Blueprint.FirebaseGuestBootstrapStateDidChange")
    static let blueprintOpenTab = Notification.Name("Blueprint.OpenTab")
    static let blueprintOpenScanJobDetail = Notification.Name("Blueprint.OpenScanJobDetail")
    static let blueprintOpenCaptureDetail = Notification.Name("Blueprint.OpenCaptureDetail")
    static let blueprintOpenPayoutEntry = Notification.Name("Blueprint.OpenPayoutEntry")
    static let blueprintOpenPayoutSetup = Notification.Name("Blueprint.OpenPayoutSetup")
}
