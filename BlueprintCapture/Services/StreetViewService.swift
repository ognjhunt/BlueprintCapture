import Foundation
import CoreGraphics
import CoreLocation
import MapKit
import UIKit

enum LocationPreviewSource: Equatable {
    case lookAround
    case mapSnapshot
    case unavailable
}

struct LocationPreviewResult: Equatable {
    let image: UIImage?
    let source: LocationPreviewSource
}

@MainActor
protocol LocationPreviewServiceProtocol {
    func preview(
        for coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> LocationPreviewResult

    func mapSnapshot(
        for coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> UIImage?
}

@MainActor
final class AppleLocationPreviewService: LocationPreviewServiceProtocol {
    static let shared = AppleLocationPreviewService()

    private var previewCache: [String: LocationPreviewResult] = [:]
    private var mapCache: [String: UIImage] = [:]

    func preview(
        for coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> LocationPreviewResult {
        let normalized = normalizedSize(size)
        guard normalized.width > 0, normalized.height > 0 else {
            return LocationPreviewResult(image: nil, source: .unavailable)
        }

        let key = cacheKey(prefix: "preview", coordinate: coordinate, size: normalized, scale: scale)
        if let cached = previewCache[key] {
            return cached
        }

        if let image = await lookAroundSnapshot(for: coordinate, size: normalized, scale: scale) {
            let result = LocationPreviewResult(image: image, source: .lookAround)
            previewCache[key] = result
            return result
        }

        if let image = await mapSnapshot(for: coordinate, size: normalized, scale: scale) {
            let result = LocationPreviewResult(image: image, source: .mapSnapshot)
            previewCache[key] = result
            return result
        }

        let result = LocationPreviewResult(image: nil, source: .unavailable)
        previewCache[key] = result
        return result
    }

    func mapSnapshot(
        for coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        let normalized = normalizedSize(size)
        guard normalized.width > 0, normalized.height > 0 else { return nil }

        let key = cacheKey(prefix: "map", coordinate: coordinate, size: normalized, scale: scale)
        if let cached = mapCache[key] {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0035, longitudeDelta: 0.0035)
        )
        options.size = normalized
        options.scale = scale
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await withCheckedThrowingContinuation { continuation in
                snapshotter.start { snapshot, error in
                    if let snapshot {
                        continuation.resume(returning: snapshot)
                    } else {
                        continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                    }
                }
            }
            mapCache[key] = snapshot.image
            return snapshot.image
        } catch {
            return nil
        }
    }

    private func lookAroundSnapshot(
        for coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        guard #available(iOS 16.0, *) else { return nil }

        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        do {
            guard let scene = try await request.scene else { return nil }

            let options = MKLookAroundSnapshotter.Options()
            options.size = size
            options.traitCollection = UITraitCollection(displayScale: scale)

            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            let snapshot = try await snapshotter.snapshot
            return snapshot.image
        } catch {
            return nil
        }
    }

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, Int(size.width.rounded())), height: max(1, Int(size.height.rounded())))
    }

    private func cacheKey(
        prefix: String,
        coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) -> String {
        [
            prefix,
            String(format: "%.5f", coordinate.latitude),
            String(format: "%.5f", coordinate.longitude),
            "\(Int(size.width))x\(Int(size.height))",
            String(format: "%.2f", scale)
        ].joined(separator: "|")
    }
}
