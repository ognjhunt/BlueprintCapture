import SwiftUI

enum BPAccountRoute: Hashable { case settings, rights }

// MARK: - Profile (tab: Profile)

struct BPProfileView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    BPLargeTitle(eyebrow: "Capturer #214", title: "Profile")
                    identityCard
                    statRow
                    menuCard
                    BPGhostButton(title: "Sign out", tint: BP.blockFg, border: BP.blockBd) {}
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .background(BP.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
            .navigationDestination(for: BPAccountRoute.self) { route in
                switch route {
                case .settings: BPSettingsView()
                case .rights: BPRightsTrainingView()
                }
            }
        }
    }

    private var identityCard: some View {
        BPCard {
            HStack(spacing: Space.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(BP.infoBg)
                    Text(initials)
                        .font(.bpSans(BPType.title, .bold))
                        .foregroundStyle(BP.infoFg)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(coordinator.capturerName)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text("Capturer #214 · \(coordinator.capturerCity)")
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.textMuted)
                }
                Spacer(minLength: Space.s)
                BPStatusChip("Active", signal: .proof)
            }
        }
    }

    private var initials: String {
        let parts = coordinator.capturerName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var statRow: some View {
        HStack(spacing: Space.m) {
            BPMetricStat(value: "27", label: "Captures")
            BPMetricStat(value: "4.9", label: "Rating")
            BPMetricStat(value: "98%", label: "Pass rate", valueColor: BP.proofFg)
        }
    }

    private var menuCard: some View {
        BPCard(padding: 0) {
            NavigationLink(value: BPAccountRoute.rights) {
                menuRow(icon: "checkmark.shield", title: "Rights & privacy",
                        trailingChip: BPChip(label: "Certified", signal: .proof))
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            menuRow(icon: "iphone", title: "Capture device", trailingText: "iPhone 16 Pro · LiDAR", showsChevron: false)
            BPDivider(color: BP.lineSoft)

            NavigationLink(value: BPAccountRoute.settings) {
                menuRow(icon: "gearshape", title: "Settings")
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            menuRow(icon: "questionmark.circle", title: "Help")
        }
    }

    private func menuRow(
        icon: String,
        title: String,
        trailingText: String? = nil,
        trailingChip: BPChip? = nil,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(BP.textMuted)
                .frame(width: 24)
            Text(title)
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Spacer(minLength: Space.s)
            if let trailingChip {
                BPStatusChip(trailingChip.label, signal: trailingChip.signal)
            }
            if let trailingText {
                Text(trailingText)
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    BPProfileView().environmentObject(RedesignCoordinator())
}
#endif
