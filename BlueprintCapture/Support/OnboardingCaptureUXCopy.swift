import Foundation

enum OnboardingCaptureUXCopy {
    static func completionTitle(glassesConnected: Bool) -> String {
        glassesConnected ? "Capture Setup Complete" : "Start with iPhone Capture"
    }

    static func completionMessage(glassesConnected: Bool) -> String {
        glassesConnected
        ? "We'll show approved opportunities and review-gated submissions separately. Payout and downstream use depend on backend review."
        : "You can submit review-gated spaces and capture with your iPhone now. Connect glasses later for supported hands-free capture."
    }

    static let disconnectedGlassesSubtitle = "Optional for supported hands-free capture. Approved jobs and review submissions can still start with iPhone."
}
