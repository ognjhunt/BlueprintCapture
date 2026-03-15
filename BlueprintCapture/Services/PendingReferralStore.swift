import Foundation

enum PendingReferralStore {
    static let storageKey = "com.blueprint.pendingReferralCode"

    static func persist(_ code: String, defaults: UserDefaults = .standard) {
        defaults.set(code, forKey: storageKey)
    }

    @discardableResult
    static func consume(defaults: UserDefaults = .standard) -> String? {
        let code = defaults.string(forKey: storageKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.removeObject(forKey: storageKey)
        guard let code, !code.isEmpty else { return nil }
        return code
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    static func current(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: storageKey) ?? ""
    }
}
