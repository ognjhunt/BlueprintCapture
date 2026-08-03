import Foundation

struct DeviceCalibrationProfile: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case qualified
        case rejected
    }

    let schemaVersion: String
    let id: UUID
    let rigId: String
    let hardwareModelIdentifier: String
    let createdAt: Date
    let expiresAt: Date
    let referenceDistanceM: Double
    let observedMedianDepthM: Double
    let relativeError: Double
    let medianAbsoluteDeviationM: Double
    let acceptedSampleCount: Int
    let requiredConfidenceValue: Int
    let maximumRelativeError: Double
    let maximumMedianAbsoluteDeviationM: Double
    let status: Status

    var isCurrentlyQualified: Bool {
        status == .qualified && expiresAt > Date()
    }
}

enum DeviceCalibrationEvaluator {
    static let minimumSamples = 45
    static let maximumRelativeError = 0.015
    static let maximumMedianAbsoluteDeviationM = 0.008
    static let validityDays = 90

    static func evaluate(
        rigId: String,
        hardwareModelIdentifier: String,
        referenceDistanceM: Double,
        depthSamplesM: [Double],
        now: Date = Date()
    ) -> DeviceCalibrationProfile? {
        let samples = depthSamplesM.filter { $0.isFinite && $0 > 0 }.sorted()
        guard referenceDistanceM.isFinite, (0.2...5.0).contains(referenceDistanceM),
              samples.count >= minimumSamples,
              let median = percentile(samples, fraction: 0.5) else { return nil }
        let deviations = samples.map { abs($0 - median) }.sorted()
        let mad = percentile(deviations, fraction: 0.5) ?? .infinity
        let relativeError = abs(median - referenceDistanceM) / referenceDistanceM
        let status: DeviceCalibrationProfile.Status =
            relativeError <= maximumRelativeError && mad <= maximumMedianAbsoluteDeviationM
            ? .qualified
            : .rejected
        return DeviceCalibrationProfile(
            schemaVersion: "device_calibration.v1",
            id: UUID(),
            rigId: rigId,
            hardwareModelIdentifier: hardwareModelIdentifier,
            createdAt: now,
            expiresAt: Calendar(identifier: .gregorian).date(byAdding: .day, value: validityDays, to: now)
                ?? now.addingTimeInterval(Double(validityDays) * 86_400),
            referenceDistanceM: referenceDistanceM,
            observedMedianDepthM: median,
            relativeError: relativeError,
            medianAbsoluteDeviationM: mad,
            acceptedSampleCount: samples.count,
            requiredConfidenceValue: 2,
            maximumRelativeError: maximumRelativeError,
            maximumMedianAbsoluteDeviationM: maximumMedianAbsoluteDeviationM,
            status: status
        )
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let index = min(values.count - 1, max(0, Int((Double(values.count - 1) * fraction).rounded())))
        return values[index]
    }
}

final class DeviceCalibrationStore {
    static let shared = DeviceCalibrationStore()

    private let defaults: UserDefaults
    private let key = "blueprint.device_calibration_profile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ profile: DeviceCalibrationProfile) throws {
        defaults.set(try JSONEncoder().encode(profile), forKey: key)
    }

    func profile(for hardwareModelIdentifier: String, now: Date = Date()) -> DeviceCalibrationProfile? {
        guard let data = defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(DeviceCalibrationProfile.self, from: data),
              profile.hardwareModelIdentifier == hardwareModelIdentifier,
              profile.expiresAt > now else { return nil }
        return profile
    }
}
