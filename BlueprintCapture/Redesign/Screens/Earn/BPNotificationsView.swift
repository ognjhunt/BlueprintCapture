import SwiftUI

// MARK: - Notifications (NavBar "Notifications")
//
// There is no client-side notification feed yet — real capture/QA events are
// delivered by the backend via push. Until an in-app feed source exists this
// screen shows an honest empty state; it must never render fabricated QA or
// validation events (capture-truth rule).

struct BPNotificationsView: View {
    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Notifications") {}
            ScrollView {
                VStack(spacing: Space.m) {
                    emptyState
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            ZStack {
                Circle().fill(BP.infoBg)
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(BP.infoFg)
            }
            .frame(width: 52, height: 52)

            Text("No notifications")
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Text("Capture review results and nearby assignment alerts will appear here as they happen.")
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xl)
        .bpCard()
    }
}

#if DEBUG
#Preview {
    NavigationStack { BPNotificationsView() }
}
#endif
