import SwiftUI

// MARK: - Notifications (NavBar "Notifications" + "Mark read")

struct BPNotificationsView: View {
    @State private var items = BPSample.notifications

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Notifications") {
                BPTextAction(title: "Mark read") {
                    for i in items.indices { items[i].unread = false }
                }
            }
            ScrollView {
                VStack(spacing: Space.m) {
                    ForEach(items) { item in
                        row(item)
                    }
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

    private func row(_ item: BPNotification) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            ZStack {
                Circle().fill(item.signal.bg)
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(item.signal.fg)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Spacer(minLength: Space.s)
                    Text(item.time)
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.textFaint)
                }
                Text(item.body)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .bpCard()
        .opacity(item.unread ? 1 : 0.7)
    }
}

#if DEBUG
#Preview {
    NavigationStack { BPNotificationsView() }
}
#endif
