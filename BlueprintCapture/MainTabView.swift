import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(0)
            
            NearbyTargetsView()
                .tabItem {
                    Label("Nearby", systemImage: "mappin.and.ellipse")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "person.circle.fill")
                }
                .tag(2)
        }
        .tint(BlueprintTheme.brandTeal)
        .blueprintAppBackground()
    }
}

#Preview {
    MainTabView()
}

