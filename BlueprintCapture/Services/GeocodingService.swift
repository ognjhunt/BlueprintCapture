import Foundation
import CoreLocation

protocol GeocodingServiceProtocol {
    func reverseGeocode(lat: Double, lng: Double) async throws -> String?
}

final class GeocodingService: GeocodingServiceProtocol {
    private let geocoder: CLGeocoder
    private var lastRequestAt: Date = .distantPast
    private let minInterval: TimeInterval = 60 // 1 per minute

    init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    func reverseGeocode(lat: Double, lng: Double) async throws -> String? {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minInterval {
            try await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
        }
        lastRequestAt = Date()
        let location = CLLocation(latitude: lat, longitude: lng)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let p = placemarks.first else { return nil }
        var parts: [String] = []
        if let sub = p.subThoroughfare { parts.append(sub) }
        if let thoroughfare = p.thoroughfare { parts.append(thoroughfare) }
        if let locality = p.locality { parts.append(locality) }
        if let admin = p.administrativeArea { parts.append(admin) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}


