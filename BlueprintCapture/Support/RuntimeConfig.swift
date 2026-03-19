import Foundation

enum AlphaFeature: String, CaseIterable {
    case payouts
    case nearbyDiscovery
    case streetView
    case captureIntakeAI
    case recordingPolicyAI
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
    let isUITesting: Bool
    let uiTestScenario: UITestScenario
    let allowOffsiteCheckIn: Bool
    let maxReservationDriveMinutes: Int
    let fallbackMaxReservationAirMiles: Double
    let enableDirectProviderFeatures: Bool
    let allowMockJobsFallback: Bool

    static var current: RuntimeConfig {
        load()
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

        return RuntimeConfig(
            backendBaseURL: backendBaseURL,
            isUITesting: isUITesting,
            uiTestScenario: scenario,
            allowOffsiteCheckIn: isUITesting || boolValue(environment["BLUEPRINT_ALLOW_OFFSITE_CHECKIN"], defaultValue: false),
            maxReservationDriveMinutes: intValue(environment["BLUEPRINT_MAX_RESERVATION_DRIVE_MINUTES"], defaultValue: 60),
            fallbackMaxReservationAirMiles: doubleValue(environment["BLUEPRINT_FALLBACK_MAX_RESERVATION_AIR_MILES"], defaultValue: 35.0),
            enableDirectProviderFeatures: boolValue(environment["BLUEPRINT_ENABLE_DIRECT_PROVIDER_FEATURES"], defaultValue: false),
            allowMockJobsFallback: boolValue(environment["BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK"], defaultValue: false)
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
            guard enableDirectProviderFeatures else {
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
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return URL(string: trimmed)
    }
}

enum DeveloperProviderOverrides {
    static func value(for keys: [String], environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for key in keys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.isEmpty == false else {
                continue
            }
            return raw
        }
        return nil
    }
}
