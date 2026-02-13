import Foundation
import CoreLocation

/// A curated scan opportunity defined by the backend (Firestore: `capture_jobs`).
struct ScanJob: Identifiable, Equatable {
    let id: String // Firestore doc id (jobId) and pipeline `scene_id`

    // Required fields
    let title: String
    let address: String
    let lat: Double
    let lng: Double
    let payoutCents: Int
    let estMinutes: Int
    let active: Bool
    let updatedAt: Date

    // Optional fields
    let category: String?
    let instructions: [String]
    let allowedAreas: [String]
    let restrictedAreas: [String]
    let permissionDocURL: URL?
    let checkinRadiusM: Int
    let alertRadiusM: Int
    let priority: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var payoutDollars: Int {
        max(0, payoutCents / 100)
    }

    func distanceMeters(from userLocation: CLLocation) -> Double {
        userLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
    }
}

