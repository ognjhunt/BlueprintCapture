import SwiftUI
import AVFoundation
#if canImport(MWDATCore) && !targetEnvironment(simulator)
import MWDATCore
#endif

@main
struct BlueprintCaptureApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false
    @AppStorage(PendingReferralStore.storageKey) private var pendingReferralCode: String = ""
    @StateObject private var glassesManager = GlassesCaptureManager()
    @StateObject private var uploadQueue = UploadQueueViewModel()
    @StateObject private var alertsManager = NearbyAlertsManager()
    @StateObject private var notificationPreferences = NotificationPreferencesStore.shared
    @State private var launchCityGateViewModel = LaunchCityGateViewModel()

    init() {
        #if canImport(MWDATCore) && !targetEnvironment(simulator)
        do {
            try Wearables.configure()
        } catch {
            NSLog("[BlueprintCapture] Failed to configure Wearables SDK: \(error)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if RuntimeConfig.current.isUITesting {
                    UITestRootView()
                } else {
                    // Redesigned BlueprintCapture UI (ink/paper/brass). The real
                    // capture/upload managers stay alive and are injected for future
                    // wiring; the new presentation layer is the shipping UI.
                    BPAppRoot()
                        .environmentObject(glassesManager)
                        .environmentObject(uploadQueue)
                        .environmentObject(alertsManager)
                }
            }
            .onAppear {
                // Guarantee a local user exists even if user bypasses onboarding in dev
                UserDeviceService.ensureTemporaryUser()
                NotificationRouter.shared.consumePendingRouteIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { _ in }
            .onOpenURL { url in
                if glassesManager.handleWearablesCallback(url) {
                    return
                } else if let code = ReferralService.referralCode(from: url) {
                    pendingReferralCode = code
                } else {
                    NotificationRouter.shared.handle(url: url)
                }
            }
            .environmentObject(notificationPreferences)
            // Paper is the default; the viewfinder, sign-in hero and balance panel
            // declare `.dark` locally.
            .preferredColorScheme(.light)
        }
    }
}
