import SwiftUI
import AVFoundation

@main
struct BlueprintCaptureApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboarded {
                    MainTabView()
                } else {
                    OnboardingFlowView()
                }
            }
                .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { _ in }
        }
    }
}
