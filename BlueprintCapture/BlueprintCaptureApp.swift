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
            .onOpenURL { url in
                if let code = ReferralService.referralCode(from: url) {
                    pendingReferralCode = code
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
