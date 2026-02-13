import SwiftUI
import AVFoundation

@main
struct BlueprintCaptureApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false
    @StateObject private var glassesManager = GlassesCaptureManager()
    @StateObject private var uploadQueue = UploadQueueViewModel()
    @StateObject private var alertsManager = NearbyAlertsManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboarded {
                    MainTabView(
                        glassesManager: glassesManager,
                        uploadQueue: uploadQueue,
                        alertsManager: alertsManager
                    )
                } else {
                    OnboardingFlowView(
                        glassesManager: glassesManager,
                        alertsManager: alertsManager
                    )
                }
            }
            .onAppear {
                // Guarantee a local user exists even if user bypasses onboarding in dev
                UserDeviceService.ensureTemporaryUser()
            }
            .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { _ in }
            .preferredColorScheme(.dark)
        }
    }
}
