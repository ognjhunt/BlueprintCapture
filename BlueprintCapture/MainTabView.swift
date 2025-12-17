import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var captureFlowViewModel = CaptureFlowViewModel()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NearbyTargetsView(sharedCaptureFlow: captureFlowViewModel)
                    .tabItem {
                        Label("Earn", systemImage: "mappin.circle.fill")
                    }
                    .tag(0)

                SettingsView()
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                    .tag(1)
            }
            .tint(BlueprintTheme.brandTeal)

            // Upload progress overlay - appears above tab bar
            UploadProgressOverlayView(viewModel: captureFlowViewModel)
        }
        .blueprintAppBackground()
    }
}

#Preview {
    MainTabView()
}

