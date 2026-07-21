import SwiftUI

// MARK: - Task detail & accept (NavBar "Task")
//
// Bound to the real discovery feed (`ScanHomeViewModel.JobItem`). Requirements,
// boundaries, and payout come straight from the marketplace job document —
// nothing is staged. Accepting hands back to Home, which owns the reservation
// call (CAP-04) and launches the real capture engine.

struct BPTaskDetailView: View {
    let item: ScanHomeViewModel.JobItem
    var isReserving: Bool = false
    var onAccept: (ScanHomeViewModel.JobItem) -> Void = { _ in }

    private var job: ScanJob { item.job }

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Task") {
                BPStatusChip(item.permissionTier.shortLabel, signal: BPSignalMapping.signal(for: item.permissionTier))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    pathHero
                    titleBlock
                    if let recaptureReason = job.recaptureReason, !recaptureReason.isEmpty {
                        BPProofBoundary(
                            "Recapture requested",
                            message: recaptureReason,
                            signal: .caution,
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    if !steps.isEmpty { stepsSection }
                    requirementsSection
                    reservationNote
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
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    // MARK: Site hero
    //
    // Real imagery only. The previous decorative "suggested capture path"
    // bezier was drawn client-side over whatever image happened to load — a
    // fabricated route the site never provided. Route guidance comes from the
    // job's real instructions below.

    private var pathHero: some View {
        BPRemoteFacilityImage(
            url: job.heroImageURL ?? job.thumbnailURL ?? item.previewURL,
            height: 200
        )
        .overlay { BPRegistrationCorners() }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(job.title)
                .font(.bpSans(BPType.largeTitle, .bold))
                .tracking(BPTracking.headlineLarge)
                .foregroundStyle(BP.textStrong)
            Text(metaLine)
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let badge = item.availabilityBadge {
                BPStatusChip(badge, signal: badge == "Complete" ? .proof : .info)
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let category = job.category, !category.isEmpty { parts.append(category) }
        parts.append(item.distanceLabel)
        if job.estMinutes > 0 { parts.append("~\(job.estMinutes) min") }
        if let due = job.dueWindow, !due.isEmpty { parts.append(due) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: What to capture (real instructions)

    private var steps: [String] {
        job.workflowSteps.isEmpty ? job.instructions : job.workflowSteps
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("What to capture")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)

            BPCard {
                ForEach(Array(steps.prefix(8).enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: Space.m) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.bpMono(BPType.caption))
                            .foregroundStyle(BP.brassDeep)
                            .padding(.top, 2)
                        Text(step)
                            .font(.bpSans(BPType.bodyS, .regular))
                            .foregroundStyle(BP.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if idx < min(steps.count, 8) - 1 {
                        BPDivider(color: BP.lineSoft)
                    }
                }
            }
        }
    }

    // MARK: Requirements & boundaries (real job document fields)

    private struct Requirement: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let signal: BPSignal
    }

    private var requirements: [Requirement] {
        var result: [Requirement] = []
        if !job.allowedAreas.isEmpty {
            result.append(Requirement(
                title: "Allowed areas",
                detail: job.allowedAreas.joined(separator: " · "),
                signal: .proof
            ))
        }
        if !job.restrictedAreas.isEmpty {
            result.append(Requirement(
                title: "Restricted zones",
                detail: job.restrictedAreas.joined(separator: " · "),
                signal: .blocker
            ))
        }
        if !job.approvalRequirements.isEmpty {
            result.append(Requirement(
                title: "Approval requirements",
                detail: job.approvalRequirements.joined(separator: " · "),
                signal: .caution
            ))
        }
        if !job.rightsChecklist.isEmpty {
            result.append(Requirement(
                title: "Rights checklist",
                detail: job.rightsChecklist.joined(separator: " · "),
                signal: .info
            ))
        }
        // Standing capture rules — always true for every Blueprint capture.
        result.append(Requirement(
            title: "Depth & coverage",
            detail: "Walk steadily and keep the full route in frame — the viewfinder coaches depth and coverage live.",
            signal: .proof
        ))
        result.append(Requirement(
            title: "Privacy",
            detail: "Avoid people, screens, and badges. Restricted or private areas stay out of frame.",
            signal: .info
        ))
        return result
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Requirements")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)

            BPCard {
                let items = requirements
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, req in
                    HStack(alignment: .top, spacing: Space.m) {
                        Circle()
                            .fill(req.signal.fg)
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(req.title)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(req.detail)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    if idx < items.count - 1 {
                        BPDivider(color: BP.lineSoft)
                    }
                }
            }
        }
    }

    private var reservationNote: some View {
        Text("Accepting reserves this assignment for you for 60 minutes and checks you in on arrival.")
            .font(.bpSans(BPType.caption, .regular))
            .foregroundStyle(BP.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pinned bottom bar

    private var canAccept: Bool {
        item.permissionTier != .blocked && !isReserving
    }

    private var payoutLabelText: String {
        let cents = job.quotedPayoutCents ?? job.payoutCents
        return cents > 0 ? BPFormat.currency(Double(cents) / 100.0) : "Review gated"
    }

    private var payoutEyebrow: String {
        let cents = job.quotedPayoutCents ?? job.payoutCents
        return cents > 0 ? "Assignment payout" : "Payout"
    }

    private var bottomBar: some View {
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payoutEyebrow)
                    .bpEyebrow()
                Text(payoutLabelText)
                    .font(.bpMono(BPType.title))
                    .foregroundStyle(BP.textStrong)
            }
            Spacer(minLength: Space.m)
            BPPrimaryButton(
                title: isReserving ? "Reserving…" : "Accept & start capture",
                enabled: canAccept
            ) {
                onAccept(item)
            }
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(
            BP.canvas
                .overlay(alignment: .top) { BPDivider(color: BP.line) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Signal mapping shared with Home

enum BPSignalMapping {
    static func signal(for tier: ScanHomeViewModel.CapturePermissionTier) -> BPSignal {
        switch tier {
        case .approved: return .proof
        case .reviewRequired: return .info
        case .permissionRequired: return .caution
        case .blocked: return .caution
        }
    }
}

// MARK: - Remote facility image (real thumbnails with honest placeholder)

struct BPRemoteFacilityImage: View {
    let url: URL?
    var height: CGFloat = 156

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .grayscale(0.9)
                    default:
                        neutralPlaceholder
                    }
                }
            } else {
                neutralPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(BP.line, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    /// Honest no-imagery state: a neutral surface, never a stock photo of a
    /// different site pretending to be this one.
    private var neutralPlaceholder: some View {
        ZStack {
            BP.ink.opacity(0.05)
            BPEvidenceGrid(spacing: 22, lineColor: BP.ink.opacity(0.05))
            Image(systemName: "building.2")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(BP.textFaint)
        }
    }
}
