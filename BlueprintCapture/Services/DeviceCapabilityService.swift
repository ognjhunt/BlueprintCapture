import Foundation
import ARKit
import UIKit

final class DeviceCapabilityService {
    static let shared = DeviceCapabilityService()

    let hasLiDAR: Bool
    let supportsARKit: Bool
    let deviceModel: String

    /// Earnings multiplier based on device sensor capabilities.
    /// LiDAR devices earn 4x, non-LiDAR iPhones earn 2x, glasses earn 1x.
    var captureMultiplier: Double {
        if hasLiDAR { return 4.0 }
        if supportsARKit { return 2.0 }
        return 1.0
    }

    var capabilityDescription: String {
        var parts: [String] = []
        parts.append(hasLiDAR ? "LiDAR \u{2713}" : "LiDAR \u{2717}")
        parts.append(supportsARKit ? "ARKit \u{2713}" : "ARKit \u{2717}")
        parts.append("\(Int(captureMultiplier))x multiplier")
        return parts.joined(separator: " | ")
    }

    var multiplierLabel: String {
        "\(Int(captureMultiplier))x"
    }

    private init() {
        self.supportsARKit = ARWorldTrackingConfiguration.isSupported
        self.hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        self.deviceModel = UIDevice.current.modelName
    }
}

private extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapDeviceIdentifier(identifier)
    }

    private func mapDeviceIdentifier(_ id: String) -> String {
        // Return a human-readable name for common identifiers
        switch id {
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7":
            return "iPad Pro 11-inch (3rd gen)"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11":
            return "iPad Pro 12.9-inch (5th gen)"
        default:
            if id.hasPrefix("iPhone") { return "iPhone" }
            if id.hasPrefix("iPad") { return "iPad" }
            if id == "x86_64" || id == "arm64" { return "Simulator" }
            return id
        }
    }
}
