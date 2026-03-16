import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel
    @ObservedObject var alertsManager: NearbyAlertsManager

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                ScanHomeView(
                    glassesManager: glassesManager,
                    uploadQueue: uploadQueue,
                    alertsManager: alertsManager
                )
                .tag(0)

                WalletView(glassesManager: glassesManager)
                    .tag(1)

                ProfileTabView()
                    .tag(2)
            }
            .tint(.white)

            // Upload progress overlay
            UploadProgressOverlayView(viewModel: uploadQueue)
                .padding(.bottom, 60)

            // Custom Kled-style tab bar
            kledTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            NotificationRouter.shared.consumePendingRouteIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenTab)) { note in
            guard let tab = note.userInfo?["tab"] as? String else { return }
            switch tab {
            case "scan":
                selectedTab = 0
            case "wallet":
                selectedTab = 1
            case "profile":
                selectedTab = 2
            default:
                break
            }
        }
    }

    private var kledTabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, icon: "location.viewfinder", activeIcon: "location.viewfinder")
            tabButton(index: 1, icon: "creditcard", activeIcon: "creditcard.fill")
            tabButton(index: 2, icon: "person.circle", activeIcon: "person.circle.fill")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            Color(white: 0.06)
                .overlay(
                    Rectangle()
                        .fill(Color(white: 0.14))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    private func tabButton(index: Int, icon: String, activeIcon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            ZStack {
                if selectedTab == index {
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: 52, height: 52)
                }
                Image(systemName: selectedTab == index ? activeIcon : icon)
                    .font(.system(size: 22, weight: selectedTab == index ? .semibold : .regular))
                    .foregroundStyle(selectedTab == index ? .white : Color(white: 0.45))
                    .frame(width: 52, height: 52)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MainTabView(
        glassesManager: GlassesCaptureManager(),
        uploadQueue: UploadQueueViewModel(),
        alertsManager: NearbyAlertsManager()
    )
}
