import SwiftUI

// MARK: - Tabs

enum BPTab: Int, CaseIterable, Hashable {
    case home, history, earnings, profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .earnings: return "Earnings"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .earnings: return "dollarsign.circle"
        case .profile: return "person"
        }
    }
}

// MARK: - BPTabBar
//
// Home · History · [Capture] · Earnings · Profile. The center capture control is a
// raised brass circle (aperture) — an action, not a tab. 44pt+ hit targets.

struct BPTabBar: View {
    @Binding var selection: BPTab
    var captureEnabled: Bool = true
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home)
            tabItem(.history)
            captureButton
            tabItem(.earnings)
            tabItem(.profile)
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
        .background(
            BP.canvas
                .overlay(alignment: .top) { BPDivider(color: BP.line) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(_ tab: BPTab) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: active ? .medium : .regular))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.bpSans(10, active ? .semibold : .medium))
                    .tracking(0.2)
            }
            .foregroundStyle(active ? BP.brassDeep : BP.textFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            ZStack {
                Circle()
                    .fill(captureEnabled ? BP.brass : BP.sunken)
                    .overlay(Circle().strokeBorder(BP.brassDeep.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(BP.ink)
            }
            .frame(width: 58, height: 58)
            .offset(y: -14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Start capture")
    }
}

// MARK: - Attach the tab bar to a tab root
//
// Applied to a tab root's scrolling content (inside the NavigationStack root), so
// the bar shows on roots but disappears when a detail screen is pushed — pushed
// screens own their bottom bar and must not sit under the tab bar.

extension View {
    func bpTabBarOverlay(selection: Binding<BPTab>, onCapture: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            BPTabBar(selection: selection, onCapture: onCapture)
        }
    }
}

#if DEBUG
private struct BPTabBarPreview: View {
    @State private var sel: BPTab = .home
    var body: some View {
        VStack {
            Spacer()
            BPTabBar(selection: $sel, onCapture: {})
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bpPaperBackground()
    }
}
#Preview { BPTabBarPreview() }
#endif
