import SwiftUI

// MARK: - How Blueprint works
//
// The comprehension hub: what the app is, how a capture becomes a payout, and
// what every status means. Copy follows the public capturer copy rules
// (Blueprint-WebApp/docs/public-capturer-copy-rules-2026-05-13.md): assignment
// payout shown before you start, review required, payout eligibility — never
// guaranteed work, approval, or payout.

struct BPHowItWorksStep: Identifiable {
    let id: Int
    let title: String
    let body: String
    let icon: String

    static let all: [BPHowItWorksStep] = [
        BPHowItWorksStep(
            id: 1,
            title: "Find an assignment",
            body: "Assignments near you show the payout before you start. Open capture is available where you have permission — those uploads enter review first.",
            icon: "mappin.and.ellipse"
        ),
        BPHowItWorksStep(
            id: 2,
            title: "Walk the route",
            body: "The viewfinder coaches depth, pose lock, and coverage while you walk. Truthful evidence only — no staging, no restricted areas.",
            icon: "camera.aperture"
        ),
        BPHowItWorksStep(
            id: 3,
            title: "Upload for review",
            body: "Every capture is reviewed. Accepted captures become payout-eligible; recapture requests tell you exactly what to fix.",
            icon: "arrow.up.doc"
        ),
    ]
}

// MARK: - Reusable numbered steps

struct BPHowItWorksSteps: View {
    var steps: [BPHowItWorksStep] = BPHowItWorksStep.all

    var body: some View {
        VStack(spacing: Space.m) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: Space.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(BP.proofBg)
                        Text("\(step.id)")
                            .font(.bpMono(BPType.bodyS))
                            .foregroundStyle(BP.proofFg)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.bpSans(BPType.body, .semibold))
                            .foregroundStyle(BP.textStrong)
                        Text(step.body)
                            .font(.bpSans(BPType.caption, .regular))
                            .foregroundStyle(BP.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.l)
                .bpCard()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Full screen

struct BPHowItWorksView: View {
    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("How it works")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        BPEyebrow("Field guide", color: BP.brassDeep)
                        Text("Capture real sites.\nGet paid for accepted evidence.")
                            .font(.bpDisplay(24))
                            .foregroundStyle(BP.textStrong)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    BPHowItWorksSteps()

                    payoutSection

                    statusSection
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
    }

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Payout math")
            BPPayoutMathCard()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("What statuses mean")
            BPStatusGlossaryCard()
        }
    }
}

// MARK: - Payout math (honest composition, no invented dollar figures)

struct BPPayoutMathCard: View {
    private let components: [(String, String)] = [
        ("Base payout", "Set per assignment and shown before you start."),
        ("Device multiplier", "Your approved capture device adjusts the base."),
        ("Quality bonus", "Strong coverage and depth can add a bonus after review."),
        ("Task & referral bonuses", "Applied when the assignment or your referrals qualify."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPCard(padding: 0) {
                ForEach(Array(components.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(systemName: idx == 0 ? "equal.square" : "plus.square")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(BP.brassDeep)
                            .frame(width: 24)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(item.1)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    if idx < components.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }

            BPProofBoundary(
                "Payout eligibility follows review",
                message: "Final payout depends on approved device, route completion, capture quality, site access, and QA approval. Nothing here guarantees assignments or payout.",
                signal: .info,
                systemImage: "checkmark.shield"
            )
        }
    }
}

// MARK: - Status glossary

struct BPStatusGlossaryCard: View {
    var body: some View {
        BPCard(padding: 0) {
            let statuses = BPStatusPresentation.glossaryOrder
            ForEach(Array(statuses.enumerated()), id: \.offset) { idx, status in
                let entry = BPStatusPresentation.entry(for: status)
                HStack(alignment: .top, spacing: Space.m) {
                    BPStatusChip(entry.label, signal: entry.signal)
                        .frame(width: 118, alignment: .leading)
                    Text(entry.explanation)
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.label): \(entry.explanation)")
                if idx < statuses.count - 1 { BPDivider(color: BP.lineSoft) }
            }
        }
    }
}

/// Sheet wrapper used from History / Earnings ("What do these mean?").
struct BPStatusGlossarySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Status guide", showsBack: false) {
                BPTextAction(title: "Done") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    BPStatusGlossaryCard()
                    VStack(alignment: .leading, spacing: Space.m) {
                        BPEyebrow("Payout transfers")
                        BPCard(padding: 0) {
                            let payoutStatuses: [PayoutLedgerStatus] = [.pending, .inTransit, .paid, .failed]
                            ForEach(Array(payoutStatuses.enumerated()), id: \.offset) { idx, status in
                                let entry = BPStatusPresentation.entry(for: status)
                                HStack(alignment: .top, spacing: Space.m) {
                                    BPStatusChip(entry.label, signal: entry.signal)
                                        .frame(width: 118, alignment: .leading)
                                    Text(entry.explanation)
                                        .font(.bpSans(BPType.caption, .regular))
                                        .foregroundStyle(BP.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, Space.l)
                                .padding(.vertical, Space.m)
                                if idx < payoutStatuses.count - 1 { BPDivider(color: BP.lineSoft) }
                            }
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
}

#if DEBUG
#Preview("How it works") {
    NavigationStack { BPHowItWorksView() }
}

#Preview("Glossary sheet") {
    BPStatusGlossarySheet()
}
#endif
