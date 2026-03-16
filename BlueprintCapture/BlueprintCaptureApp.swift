import SwiftUI
import AVFoundation

@main
struct BlueprintCaptureApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false
    @AppStorage(PendingReferralStore.storageKey) private var pendingReferralCode: String = ""
    @StateObject private var glassesManager = GlassesCaptureManager()
    @StateObject private var uploadQueue = UploadQueueViewModel()
    @StateObject private var alertsManager = NearbyAlertsManager()
    @StateObject private var notificationPreferences = NotificationPreferencesStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if RuntimeConfig.current.isUITesting {
                    UITestRootView()
                } else if isOnboarded {
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
                NotificationRouter.shared.consumePendingRouteIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { _ in }
            .onOpenURL { url in
                if let code = ReferralService.referralCode(from: url) {
                    pendingReferralCode = code
                } else {
                    NotificationRouter.shared.handle(url: url)
                }
            }
            .environmentObject(notificationPreferences)
            .preferredColorScheme(.dark)
        }
    }
}
