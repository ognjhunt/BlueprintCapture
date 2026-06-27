import SwiftUI

// MARK: - Capture history (tab: History)

struct BPHistoryView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    private let items = BPSample.history

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                BPLargeTitle(eyebrow: "\(items.count) captures", title: "History")
                    .padding(.bottom, Space.xs)
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
    }

    private func row(_ item: BPHistoryItem) -> some View {
        HStack(spacing: Space.m) {
            BPFacilityImage(name: item.imageName, height: 56, corner: Radius.sm)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.site)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text(item.meta)
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            BPStatusChip(item.status.label, signal: item.status.signal)
        }
        .padding(Space.m)
        .bpCard()
    }
}

#if DEBUG
#Preview { BPHistoryView().environmentObject(RedesignCoordinator()) }
#endif
