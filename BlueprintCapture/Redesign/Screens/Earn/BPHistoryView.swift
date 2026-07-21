import SwiftUI

// MARK: - Capture history (tab: History)
//
// Renders the signed-in user's real `capture_submissions`. Empty and error
// states are honest — no sample captures or fabricated review verdicts.

struct BPHistoryView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @StateObject private var store = BPCaptureHistoryStore()
    @State private var selectedEntry: BPCaptureHistoryEntry?
    @State private var selectedDetail: CaptureDetailResponse?
    @State private var isLoadingDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                BPLargeTitle(eyebrow: eyebrow, title: "History")
                    .padding(.bottom, Space.xs)

                switch store.state {
                case .loading:
                    loadingCard
                case .unavailable(let message):
                    emptyCard(
                        icon: "exclamationmark.triangle",
                        title: "History unavailable",
                        message: message
                    )
                case .loaded where store.entries.isEmpty:
                    emptyCard(
                        icon: "camera.metering.matrix",
                        title: "No captures yet",
                        message: "Your uploads will appear here with their real review status once you complete a capture."
                    )
                case .loaded:
                    ForEach(store.entries) { entry in
                        row(entry)
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selectedEntry) { entry in
            BPCaptureDetailSheet(
                entry: entry,
                detail: selectedDetail,
                isLoading: isLoadingDetail
            )
        }
    }

    /// Opens the per-capture detail sheet. Review detail is fetched best-effort
    /// from the backend; the sheet renders honestly with just the submission
    /// status when no detail is available.
    private func openDetail(_ entry: BPCaptureHistoryEntry) {
        selectedDetail = nil
        selectedEntry = entry
        guard let uuid = UUID(uuidString: entry.id) else { return }
        isLoadingDetail = true
        Task {
            let detail = try? await APIService.shared.fetchCaptureDetail(id: uuid)
            if selectedEntry?.id == entry.id {
                selectedDetail = detail
                isLoadingDetail = false
            }
        }
    }

    private var eyebrow: String {
        switch store.state {
        case .loaded where !store.entries.isEmpty:
            return "\(store.entries.count) capture\(store.entries.count == 1 ? "" : "s")"
        default:
            return "Captures"
        }
    }

    private var loadingCard: some View {
        HStack(spacing: Space.m) {
            ProgressView()
            Text("Loading captures…")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xl)
        .bpCard()
    }

    private func emptyCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(BP.textMuted)
            Text(title)
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Text(message)
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xl)
        .bpCard()
    }

    private func row(_ entry: BPCaptureHistoryEntry) -> some View {
        Button {
            openDetail(entry)
        } label: {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.site)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                        .lineLimit(1)
                    if !entry.meta.isEmpty {
                        Text(entry.meta)
                            .font(.bpMono(BPType.caption))
                            .foregroundStyle(BP.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s)
                BPStatusChip(entry.chip.label, signal: entry.chip.signal)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
            .padding(Space.m)
            .bpCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.site), \(entry.chip.label). Opens capture detail.")
    }
}

#if DEBUG
#Preview { BPHistoryView().environmentObject(RedesignCoordinator()) }
#endif
