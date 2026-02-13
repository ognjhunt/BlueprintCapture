import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel
    @ObservedObject var alertsManager: NearbyAlertsManager

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ScanHomeView(
                    glassesManager: glassesManager,
                    uploadQueue: uploadQueue,
                    alertsManager: alertsManager
                )
                    .tabItem {
                        Label("Scan", systemImage: "mappin.circle.fill")
                    }
                    .tag(0)

                WalletView(glassesManager: glassesManager)
                    .tabItem {
                        Label("Wallet", systemImage: "creditcard.fill")
                    }
                    .tag(1)
            }
            .tint(BlueprintTheme.brandTeal)

            // Upload progress overlay - appears above tab bar
            UploadProgressOverlayView(viewModel: uploadQueue)
        }
        .blueprintAppBackground()
        .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { note in
            guard
                let info = note.userInfo as? [String: Any],
                let action = info["action"] as? String,
                action == "start_scan"
            else { return }
            selectedTab = 0
        }
    }
}

#Preview {
    MainTabView(glassesManager: GlassesCaptureManager(), uploadQueue: UploadQueueViewModel(), alertsManager: NearbyAlertsManager())
}
