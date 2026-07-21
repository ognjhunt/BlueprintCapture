import SwiftUI

// MARK: - Capture history (tab: History)
//
// Real capture history from the creator backend, with the live upload queue
// stacked on top so a fresh capture appears immediately (Uploading → Submitted)
// and per-capture detail (timeline, quality, earnings) on tap. No sample rows.

struct BPHistoryView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @EnvironmentObject private var uploadQueue: UploadQueueViewModel
    @StateObject private var viewModel = BPHistoryViewModel()
    @State private var showingGlossary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                BPLargeTitle(eyebrow: eyebrow, title: "History") {
                    BPTextAction(title: "Status guide") { showingGlossary = true }
                }

                if case .failed(let message) = viewModel.phase {
                    BPProofBoundary(
                        "Sync unavailable",
                        message: "\(message) Pull to refresh to try again.",
                        signal: .caution,
                        systemImage: "arrow.clockwise"
                    )
                }

                uploadsSection
                capturesSection
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingGlossary) {
            BPStatusGlossarySheet()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.selectedEntry != nil },
                set: { if !$0 { viewModel.clearSelection() } }
            )
        ) {
            if let entry = viewModel.selectedEntry {
                BPCaptureDetailSheet(
                    entry: entry,
                    detail: viewModel.selectedDetail,
                    isLoading: viewModel.detailLoading
                )
            }
        }
    }

    private var eyebrow: String {
        viewModel.entries.isEmpty ? "Captures" : "\(viewModel.entries.count) captures"
    }

    // MARK: Active uploads (local truth)

    @ViewBuilder
    private var uploadsSection: some View {
        let active = uploadQueue.uploadStatuses.filter {
            if case .completed = $0.state { return false }
            return true
        }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                BPEyebrow("On this device")
                VStack(spacing: Space.m) {
                    ForEach(active) { status in
                        let entry = BPStatusPresentation.entry(for: status.state)
                        HStack(spacing: Space.m) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(entry.signal.fg)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(status.targetName ?? "Capture bundle")
                                    .font(.bpSans(BPType.body, .semibold))
                                    .foregroundStyle(BP.textStrong)
                                    .lineLimit(1)
                                if case .uploading(let progress) = status.state {
                                    ProgressView(value: progress)
                                        .tint(BP.brassDeep)
                                }
                            }
                            Spacer(minLength: Space.s)
                            BPStatusChip(entry.label, signal: entry.signal, mono: true)
                        }
                        .padding(Space.l)
                        .bpCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Backend history

    @ViewBuilder
    private var capturesSection: some View {
        if viewModel.phase == .loading && viewModel.entries.isEmpty {
            BPCard {
                HStack(spacing: Space.m) {
                    ProgressView().controlSize(.small)
                    Text("Syncing capture history…")
                        .font(.bpSans(BPType.bodyS, .regular))
                        .foregroundStyle(BP.textMuted)
                }
            }
        } else if viewModel.entries.isEmpty {
            emptyState
        } else {
            VStack(spacing: Space.m) {
                ForEach(viewModel.entries) { entry in
                    Button {
                        viewModel.select(entry)
                    } label: {
                        historyRow(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rowAccessibilityLabel(entry))
                }
            }
        }
    }

    private func historyRow(_ entry: CaptureHistoryEntry) -> some View {
        let status = BPStatusPresentation.entry(for: entry.status)
        return HStack(spacing: Space.m) {
            BPRemoteFacilityImage(url: entry.thumbnailURL, height: 52)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(entry.targetAddress)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text(metaLine(entry))
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            BPStatusChip(status.label, signal: status.signal)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BP.textFaint)
        }
        .padding(Space.l)
        .bpCard()
    }

    private func metaLine(_ entry: CaptureHistoryEntry) -> String {
        var parts = [entry.capturedAt.formatted(date: .abbreviated, time: .omitted)]
        if let payout = entry.estimatedPayout {
            parts.append(BPFormat.currency(NSDecimalNumber(decimal: payout).doubleValue))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func rowAccessibilityLabel(_ entry: CaptureHistoryEntry) -> String {
        let status = BPStatusPresentation.entry(for: entry.status)
        return "\(entry.targetAddress), \(status.label), \(entry.capturedAt.formatted(date: .abbreviated, time: .omitted)). Opens capture detail."
    }

    private var emptyState: some View {
        BPCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Your captures land here")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text("After you upload, each capture moves through review — Submitted, In review, then Accepted or Recapture. Accepted captures become payout-eligible.")
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                BPPrimaryButton(title: "Start a capture", systemImage: "camera.aperture") {
                    coordinator.startCapture()
                }
                .padding(.top, Space.xs)
            }
        }
    }
}

#if DEBUG
#Preview {
    BPHistoryView()
        .environmentObject(RedesignCoordinator())
        .environmentObject(UploadQueueViewModel())
}
#endif
