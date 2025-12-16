import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyTargetsView()
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
        .blueprintAppBackground()
    }
}

#Preview {
    MainTabView()
}

