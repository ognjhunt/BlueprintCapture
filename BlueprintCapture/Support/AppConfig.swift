import Foundation

enum MapProvider: String {
    case appleSnapshot
    case googleStatic
}

enum AppConfig {
    static let mapProvider: MapProvider = .appleSnapshot

    static func streetViewAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return plist["STREET_VIEW_API_KEY"] as? String
            }
        } catch {
            return nil
        }
        return nil
    }

    static func placesAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return plist["PLACES_API_KEY"] as? String ?? plist["GOOGLE_PLACES_API_KEY"] as? String
            }
        } catch {
            return nil
        }
        return nil
    }

    static func geminiAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return plist["GEMINI_API_KEY"] as? String ?? plist["GOOGLE_AI_API_KEY"] as? String ?? plist["GEMINI_MAPS_API_KEY"] as? String
            }
        } catch {
            return nil
        }
        return nil
    }
}


