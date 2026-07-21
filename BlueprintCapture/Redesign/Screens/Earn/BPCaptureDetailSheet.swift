import SwiftUI

// MARK: - BPCaptureDetailSheet
//
// Per-capture truth: review timeline, quality breakdown, and the payout math
// for one submitted capture — all from `fetchCaptureDetail`. Sections render
// only when the backend actually returned them; nothing is synthesized.

struct BPCaptureDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: BPCaptureHistoryEntry
    let detail: CaptureDetailResponse?
    var isLoading: Bool = false

    /// Chip + explanation from the typed status when the backend detail (or the
    /// submission status string) parses; otherwise fall back to the entry's raw
    /// chip with no invented explanation.
    private var statusChip: BPChip {
        if let typed = detail?.status ?? entry.captureStatus {
            let presented = BPStatusPresentation.entry(for: typed)
            return BPChip(label: presented.label, signal: presented.signal)
        }
        return entry.chip
    }

    private var statusExplanation: String? {
        (detail?.status ?? entry.captureStatus).map { BPStatusPresentation.entry(for: $0).explanation }
    }

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Capture", showsBack: false) {
                BPTextAction(title: "Done") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header

                    if let reason = detail?.rejectionReason, !reason.isEmpty {
                        BPProofBoundary(
                            "Review note",
                            message: reason,
                            signal: (detail?.status ?? entry.captureStatus) == .rejected ? .blocker : .caution,
                            systemImage: "text.bubble"
                        )
                    }

                    if isLoading {
                        BPCard {
                            HStack(spacing: Space.m) {
                                ProgressView().controlSize(.small)
                                Text("Loading review detail…")
                                    .font(.bpSans(BPType.bodyS, .regular))
                                    .foregroundStyle(BP.textMuted)
                            }
                        }
                    }

                    if let timeline = detail?.timeline, !timeline.isEmpty {
                        timelineSection(timeline)
                    }

                    if let quality = detail?.quality {
                        qualitySection(quality)
                    }

                    if let earnings = detail?.earnings {
                        earningsSection(earnings)
                    }

                    if !isLoading && detail?.hasRenderableDetail != true {
                        BPCard {
                            Text("Full review detail isn't available for this capture yet. The status above is the latest we have on record.")
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(entry.site)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    if let capturedAt = entry.capturedAt {
                        Text(capturedAt.formatted(date: .long, time: .shortened))
                            .font(.bpMono(BPType.caption))
                            .foregroundStyle(BP.textMuted)
                    }
                }
                Spacer(minLength: Space.m)
                BPStatusChip(statusChip.label, signal: statusChip.signal)
            }
            if let statusExplanation {
                Text(statusExplanation)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Timeline

    private func timelineSection(_ events: [CaptureTimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Review timeline")
            BPCard(padding: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(event.isCompleted ? BP.proofFg : BP.textFaint)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.label)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(event.isCompleted ? BP.textStrong : BP.textMuted)
                            if let completedAt = event.completedAt {
                                Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.bpMono(BPType.caption))
                                    .foregroundStyle(BP.textMuted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    if idx < events.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }
        }
    }

    // MARK: Quality

    private func qualitySection(_ quality: CaptureQualityBreakdown) -> some View {
        let metrics: [(String, Int?)] = [
            ("Overall", quality.overall),
            ("Coverage", quality.coverage),
            ("Steadiness", quality.steadiness),
            ("Complete", quality.completeness),
            ("Depth", quality.depthQuality),
            ("Sharpness", quality.blurScore),
        ]
        let present = metrics.compactMap { label, value in value.map { (label, $0) } }
        return VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Quality")
            let columns = [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]
            LazyVGrid(columns: columns, spacing: Space.m) {
                ForEach(present, id: \.0) { label, value in
                    BPMetricStat(
                        value: "\(value)",
                        label: label,
                        valueColor: value >= 80 ? BP.proofFg : (value >= 60 ? BP.textStrong : BP.warnFg)
                    )
                }
            }
        }
    }

    // MARK: Earnings breakdown (real payout math)

    private func earningsSection(_ earnings: CaptureEarningsBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Payout math")
            BPCard(padding: 0) {
                VStack(spacing: 0) {
                    if let quoted = earnings.quotedPayoutCents {
                        earningsRow("Quoted payout", cents: quoted)
                        BPDivider(color: BP.lineSoft)
                    }
                    if let base = earnings.basePayoutCents {
                        earningsRow("Base payout", cents: base)
                        BPDivider(color: BP.lineSoft)
                    }
                    if let multiplier = earnings.deviceMultiplier {
                        keyValueRow("Device multiplier", value: String(format: "×%.2f", multiplier))
                        BPDivider(color: BP.lineSoft)
                    }
                    if let bonus = earnings.qualityBonusCents, bonus != 0 {
                        earningsRow("Quality bonus", cents: bonus, positive: true)
                        BPDivider(color: BP.lineSoft)
                    }
                    if let bonus = earnings.specialTaskBonusCents, bonus != 0 {
                        earningsRow("Special task bonus", cents: bonus, positive: true)
                        BPDivider(color: BP.lineSoft)
                    }
                    if let bonus = earnings.referralBonusCents, bonus != 0 {
                        earningsRow("Referral bonus", cents: bonus, positive: true)
                        BPDivider(color: BP.lineSoft)
                    }
                    ForEach(earnings.bonuses) { bonus in
                        if let cents = bonus.amountCents, cents != 0 {
                            earningsRow(bonus.label, cents: cents, positive: true)
                            BPDivider(color: BP.lineSoft)
                        }
                    }
                    if let final = earnings.finalApprovedPayoutCents ?? earnings.totalPayoutCents {
                        totalRow("Approved payout", cents: final)
                    }
                }
            }
        }
    }

    private func earningsRow(_ label: String, cents: Int, positive: Bool = false) -> some View {
        keyValueRow(label, value: (positive && cents > 0 ? "+" : "") + BPFormat.currency(Double(cents) / 100.0))
    }

    private func keyValueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
            Spacer()
            Text(value)
                .font(.bpMono(BPType.bodyS))
                .foregroundStyle(BP.textStrong)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }

    private func totalRow(_ label: String, cents: Int) -> some View {
        HStack {
            Text(label)
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Spacer()
            Text(BPFormat.currency(Double(cents) / 100.0))
                .font(.bpMono(BPType.bodyL))
                .foregroundStyle(BP.proofFg)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(BP.proofBg.opacity(0.5))
    }
}
