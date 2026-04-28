import Foundation

enum OnboardingCaptureUXCopy {
    static func completionTitle(glassesConnected: Bool) -> String {
        glassesConnected ? "You're Ready to Capture" : "Start with iPhone Capture"
    }

    static func completionMessage(glassesConnected: Bool) -> String {
        glassesConnected
        ? "We'll notify you when approved capture opportunities are nearby."
        : "You can submit spaces and capture with your iPhone now. Connect glasses later for hands-free capture."
    }

    static let disconnectedGlassesSubtitle = "Optional for hands-free capture. Approved jobs also work with iPhone."
}
