import Foundation

enum AlphaFeature: String, CaseIterable {
    case payouts
    case nearbyDiscovery
    case streetView
    case captureIntakeAI
    case recordingPolicyAI
}

enum NearbyDiscoveryProvider: String, Equatable {
    case placesNearby = "places_nearby"
    case geminiMapsGrounding = "gemini_maps_grounding"
}

enum FeatureAvailability: Equatable {
    case enabled
    case disabledForAlpha(String)
    case unavailable(String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .enabled:
            return nil
        case .disabledForAlpha(let message), .unavailable(let message):
            return message
        }
    }
}

struct RuntimeConfig: Equatable {
    enum UITestScenario: String, Equatable {
        case disabled
        case onboarding
        case corePath
        case wallet
    }

    let backendBaseURL: URL?
    let demandBackendBaseURL: URL?
    let isUITesting: Bool
    let uiTestScenario: UITestScenario
    let allowOffsiteCheckIn: Bool
    let maxReservationDriveMinutes: Int
    let fallbackMaxReservationAirMiles: Double
    let enableNearbyDiscovery: Bool
    let nearbyDiscoveryProvider: NearbyDiscoveryProvider
    let enableGeminiMapsGroundingFallback: Bool
    let enableDirectProviderFeatures: Bool
    let allowMockJobsFallback: Bool
    let enableInternalTestSpace: Bool
    let enableOpenCaptureHere: Bool
    let enableRemoteNotifications: Bool
    let websiteURL: URL?
    let helpCenterURL: URL?
    let bugReportURL: URL?
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?
    let capturePolicyURL: URL?
    let accountDeletionURL: URL?
    let supportEmailAddress: String?

    static var current: RuntimeConfig {
        load()
    }

    init(
        backendBaseURL: URL? = nil,
        demandBackendBaseURL: URL? = nil,
        isUITesting: Bool = false,
        uiTestScenario: UITestScenario = .disabled,
        allowOffsiteCheckIn: Bool = false,
        maxReservationDriveMinutes: Int = 60,
        fallbackMaxReservationAirMiles: Double = 35.0,
        enableNearbyDiscovery: Bool = true,
        nearbyDiscoveryProvider: NearbyDiscoveryProvider = .placesNearby,
        enableGeminiMapsGroundingFallback: Bool = false,
        enableDirectProviderFeatures: Bool = false,
        allowMockJobsFallback: Bool = false,
        enableInternalTestSpace: Bool = false,
        enableOpenCaptureHere: Bool = true,
        enableRemoteNotifications: Bool = false,
        websiteURL: URL? = nil,
        helpCenterURL: URL? = nil,
        bugReportURL: URL? = nil,
        termsOfServiceURL: URL? = nil,
        privacyPolicyURL: URL? = nil,
        capturePolicyURL: URL? = nil,
        accountDeletionURL: URL? = nil,
        supportEmailAddress: String? = nil
    ) {
        self.backendBaseURL = backendBaseURL
        self.demandBackendBaseURL = demandBackendBaseURL
        self.isUITesting = isUITesting
        self.uiTestScenario = uiTestScenario
        self.allowOffsiteCheckIn = allowOffsiteCheckIn
        self.maxReservationDriveMinutes = maxReservationDriveMinutes
        self.fallbackMaxReservationAirMiles = fallbackMaxReservationAirMiles
        self.enableNearbyDiscovery = enableNearbyDiscovery
        self.nearbyDiscoveryProvider = nearbyDiscoveryProvider
        self.enableGeminiMapsGroundingFallback = enableGeminiMapsGroundingFallback
        self.enableDirectProviderFeatures = enableDirectProviderFeatures
        self.allowMockJobsFallback = allowMockJobsFallback
        self.enableInternalTestSpace = enableInternalTestSpace
        self.enableOpenCaptureHere = enableOpenCaptureHere
        self.enableRemoteNotifications = enableRemoteNotifications
        self.websiteURL = websiteURL
        self.helpCenterURL = helpCenterURL
        self.bugReportURL = bugReportURL
        self.termsOfServiceURL = termsOfServiceURL
        self.privacyPolicyURL = privacyPolicyURL
        self.capturePolicyURL = capturePolicyURL
        self.accountDeletionURL = accountDeletionURL
        self.supportEmailAddress = supportEmailAddress
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> RuntimeConfig {
        let isUITesting = boolValue(
            environment["BLUEPRINT_UI_TEST_MODE"],
            defaultValue: ProcessInfo.processInfo.arguments.contains("BLUEPRINT_UI_TEST_MODE")
        )
        let scenario = UITestScenario(rawValue: normalized(environment["BLUEPRINT_UI_TEST_SCENARIO"]) ?? "") ?? (isUITesting ? .corePath : .disabled)

        let backendBaseURL = urlValue(
            environment["BACKEND_BASE_URL"] ??
            environment["BLUEPRINT_BACKEND_BASE_URL"] ??
            (infoDictionary["BLUEPRINT_BACKEND_BASE_URL"] as? String)
        )
        let demandBackendBaseURL = urlValue(
            environment["BLUEPRINT_DEMAND_BACKEND_BASE_URL"] ??
            (infoDictionary["BLUEPRINT_DEMAND_BACKEND_BASE_URL"] as? String)
        ) ?? backendBaseURL

        return RuntimeConfig(
            backendBaseURL: backendBaseURL,
            demandBackendBaseURL: demandBackendBaseURL,
            isUITesting: isUITesting,
            uiTestScenario: scenario,
            allowOffsiteCheckIn: isUITesting || boolValue(environment["BLUEPRINT_ALLOW_OFFSITE_CHECKIN"], defaultValue: false),
            maxReservationDriveMinutes: intValue(environment["BLUEPRINT_MAX_RESERVATION_DRIVE_MINUTES"], defaultValue: 60),
            fallbackMaxReservationAirMiles: doubleValue(environment["BLUEPRINT_FALLBACK_MAX_RESERVATION_AIR_MILES"], defaultValue: 35.0),
            enableNearbyDiscovery: boolValue(environment["BLUEPRINT_ENABLE_NEARBY_DISCOVERY"], defaultValue: true),
            nearbyDiscoveryProvider: nearbyDiscoveryProviderValue(
                environment["BLUEPRINT_NEARBY_DISCOVERY_PROVIDER"] ??
                (infoDictionary["BLUEPRINT_NEARBY_DISCOVERY_PROVIDER"] as? String),
                defaultValue: .placesNearby
            ),
            enableGeminiMapsGroundingFallback: boolValue(
                environment["BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK"] ??
                infoDictionary["BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK"],
                defaultValue: false
            ),
            enableDirectProviderFeatures: boolValue(environment["BLUEPRINT_ENABLE_DIRECT_PROVIDER_FEATURES"], defaultValue: false),
            allowMockJobsFallback: boolValue(
                environment["BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK"] ??
                infoDictionary["BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK"],
                defaultValue: false
            ),
            enableInternalTestSpace: boolValue(
                environment["BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE"] ??
                infoDictionary["BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE"],
                defaultValue: isUITesting
            ),
            enableOpenCaptureHere: boolValue(
                environment["BLUEPRINT_ENABLE_OPEN_CAPTURE_HERE"] ??
                infoDictionary["BLUEPRINT_ENABLE_OPEN_CAPTURE_HERE"],
                defaultValue: true
            ),
            enableRemoteNotifications: boolValue(
                environment["BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS"] ??
                infoDictionary["BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS"],
                defaultValue: false
            ),
            websiteURL: urlValue(
                environment["BLUEPRINT_MAIN_WEBSITE_URL"] ??
                (infoDictionary["BLUEPRINT_MAIN_WEBSITE_URL"] as? String)
            ),
            helpCenterURL: urlValue(
                environment["BLUEPRINT_HELP_CENTER_URL"] ??
                (infoDictionary["BLUEPRINT_HELP_CENTER_URL"] as? String)
            ),
            bugReportURL: urlValue(
                environment["BLUEPRINT_BUG_REPORT_URL"] ??
                (infoDictionary["BLUEPRINT_BUG_REPORT_URL"] as? String)
            ),
            termsOfServiceURL: urlValue(
                environment["BLUEPRINT_TERMS_OF_SERVICE_URL"] ??
                (infoDictionary["BLUEPRINT_TERMS_OF_SERVICE_URL"] as? String)
            ),
            privacyPolicyURL: urlValue(
                environment["BLUEPRINT_PRIVACY_POLICY_URL"] ??
                (infoDictionary["BLUEPRINT_PRIVACY_POLICY_URL"] as? String)
            ),
            capturePolicyURL: urlValue(
                environment["BLUEPRINT_CAPTURE_POLICY_URL"] ??
                (infoDictionary["BLUEPRINT_CAPTURE_POLICY_URL"] as? String)
            ),
            accountDeletionURL: urlValue(
                environment["BLUEPRINT_ACCOUNT_DELETION_URL"] ??
                (infoDictionary["BLUEPRINT_ACCOUNT_DELETION_URL"] as? String)
            ),
            supportEmailAddress: stringValue(
                environment["BLUEPRINT_SUPPORT_EMAIL_ADDRESS"] ??
                (infoDictionary["BLUEPRINT_SUPPORT_EMAIL_ADDRESS"] as? String)
            )
        )
    }

    func availability(for feature: AlphaFeature) -> FeatureAvailability {
        switch feature {
        case .payouts:
            guard backendBaseURL != nil else {
                return .unavailable("Payout setup is not enabled for this alpha build.")
            }
            return .enabled

        case .nearbyDiscovery:
            guard enableNearbyDiscovery else {
                return .disabledForAlpha("Live nearby discovery is disabled for this alpha build.")
            }
            return .enabled

        case .streetView:
            guard enableDirectProviderFeatures else {
                return .disabledForAlpha("Street View previews are disabled for this alpha build.")
            }
            return .enabled

        case .captureIntakeAI:
            guard enableDirectProviderFeatures else {
                return .disabledForAlpha("AI intake generation is disabled for this alpha build.")
            }
            return .enabled

        case .recordingPolicyAI:
            guard enableDirectProviderFeatures else {
                return .disabledForAlpha("AI recording policy checks are disabled for this alpha build.")
            }
            return .enabled
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func boolValue(_ raw: String?, defaultValue: Bool) -> Bool {
        guard let raw = normalized(raw) else { return defaultValue }
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func boolValue(_ raw: Any?, defaultValue: Bool) -> Bool {
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return boolValue(value, defaultValue: defaultValue)
        default:
            return defaultValue
        }
    }

    private static func intValue(_ raw: String?, defaultValue: Int) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(raw) else {
            return defaultValue
        }
        return value
    }

    private static func doubleValue(_ raw: String?, defaultValue: Double) -> Double {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(raw) else {
            return defaultValue
        }
        return value
    }

    private static func urlValue(_ raw: String?) -> URL? {
        guard let trimmed = stringValue(raw),
              trimmed.isEmpty == false else {
            return nil
        }
        return URL(string: trimmed)
    }

    private static func stringValue(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private static func nearbyDiscoveryProviderValue(_ raw: String?, defaultValue: NearbyDiscoveryProvider) -> NearbyDiscoveryProvider {
        guard let normalized = normalized(raw),
              let provider = NearbyDiscoveryProvider(rawValue: normalized) else {
            return defaultValue
        }
        return provider
    }
}

enum DeveloperProviderOverrides {
    static func value(
        for keys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String? {
        for key in keys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.isEmpty == false else {
                if let bundled = infoDictionary[key] as? String {
                    let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty == false {
                        return trimmed
                    }
                }
                continue
            }
            return raw
        }
        return nil
    }
}
