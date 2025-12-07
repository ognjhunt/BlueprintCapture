import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyTargetsView()
                .tabItem {
                    Label("Nearby", systemImage: "mappin.and.ellipse")
                }
                .tag(1)

            GlassesCaptureView()
                .tabItem {
                    Label("Glasses", systemImage: "eyeglasses")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "person.circle.fill")
                }
                .tag(3)
        }
        .tint(BlueprintTheme.brandTeal)
        .blueprintAppBackground()
    }
}

#Preview {
    MainTabView()
}

