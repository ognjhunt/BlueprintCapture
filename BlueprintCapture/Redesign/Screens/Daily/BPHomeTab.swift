import SwiftUI
import UIKit

// MARK: - Home / assignments (tab: Home)
//
// CAP-04: this screen is bound to the real discovery/reservation engine
// (`ScanHomeViewModel` + `NearbyAlertsManager`), not `BPSample.*` constants. Nearby
// and active assignments come from the live `capture_jobs` feed. Browsing a job
// opens the real task detail; accepting reserves/claims it (yielding a stable
// `capture_job_id`) and launches the real capture engine with that id threaded
// through (CAP-01).

struct BPHomeTab: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @EnvironmentObject private var glassesManager: GlassesCaptureManager
    @EnvironmentObject private var uploadQueue: UploadQueueViewModel
    @EnvironmentObject private var alertsManager: NearbyAlertsManager

    @StateObject private var viewModel: ScanHomeViewModel
    @StateObject private var checklist = BPSetupChecklistModel()
    @State private var reservingJobId: String?
    @State private var reservationError: String?
    @AppStorage("com.blueprint.hasDismissedEarningExplainer") private var hasDismissedEarningExplainer = false
    @State private var isPreActivationCapturer = false
    @State private var detailItem: ScanHomeViewModel.JobItem?
    @State private var showingDetail = false
    @State private var showingMap = false
    @State private var showingHowItWorks = false

    private let targetStateService: TargetStateServiceProtocol = TargetStateService()

    init(alertsManager: NearbyAlertsManager) {
        // The real discovery view model requires a NearbyAlertsManager. BPRootView
        // passes the app-level shared instance in explicitly so geofenced nearby
        // alerts and the discovery feed operate on one manager (beta-launch-audit
        // M-3: the previous throwaway `NearbyAlertsManager()` split alert state
        // across two instances).
        _viewModel = StateObject(wrappedValue: ScanHomeViewModel(alertsManager: alertsManager))
    }

    // MARK: Live → presentation mapping

    /// Highest-signal ready/approved job surfaced as the "active" card.
    private var activeItem: ScanHomeViewModel.JobItem? {
        viewModel.readyNow
            ?? viewModel.items.first { $0.permissionTier == .approved }
            ?? viewModel.items.first
    }

    /// Remaining discoverable jobs, excluding whatever is shown in the active card.
    private var nearbyItems: [ScanHomeViewModel.JobItem] {
        let activeId = activeItem?.id
        return viewModel.items.filter { $0.id != activeId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    if !hasDismissedEarningExplainer && isPreActivationCapturer {
                        earningExplainerCard
                    }
                    uploadsInFlightCard
                    BPSetupChecklistCard(model: checklist)
                    if let activeItem {
                        activeCard(activeItem)
                    } else {
                        emptyStateCard
                    }
                    nearbySection
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
            .background(BP.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
            .navigationDestination(isPresented: $showingDetail) {
                if let detailItem {
                    BPTaskDetailView(
                        item: detailItem,
                        isReserving: reservingJobId == detailItem.id,
                        onAccept: { item in
                            Task { await reserveAndLaunch(item) }
                        }
                    )
                }
            }
        }
        .task {
            // The earning explainer is a first-run affordance: only capturers who
            // have not completed first-capture activation see it, so existing
            // capturers don't get onboarding chrome after an app update.
            isPreActivationCapturer = !ActivationFunnelStore.shared.snapshot().activationCompleted
            viewModel.onAppear()
            await viewModel.refresh()
            await checklist.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await checklist.refresh() }
            }
        }
        .sheet(isPresented: $showingMap) {
            BPNearbyMapView(items: viewModel.items) { item in
                openDetail(item)
            }
        }
        .sheet(isPresented: $showingHowItWorks) {
            NavigationStack { BPHowItWorksView() }
        }
        .alert(
            "Couldn’t start this capture",
            isPresented: Binding(
                get: { reservationError != nil },
                set: { if !$0 { reservationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { reservationError = nil }
        } message: {
            Text(reservationError ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                BPEyebrow(eyebrowText, color: BP.brassDeep)
                Text(greetingLine)
                    .font(.bpSans(BPType.largeTitle, .bold))
                    .tracking(BPTracking.headlineLarge)
                    .foregroundStyle(BP.textStrong)
            }
            Spacer(minLength: Space.m)
            NavigationLink {
                BPNotificationsView()
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.textStrong)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Notifications")
            .offset(x: 8)
        }
    }

    private var eyebrowText: String {
        coordinator.capturerCity.isEmpty ? "Field capture" : coordinator.capturerCity
    }

    private var greetingLine: String {
        coordinator.capturerName.isEmpty ? greeting : "\(greeting), \(coordinator.capturerName)"
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: First-session explainer
    //
    // One dismissible card that tells a brand-new capturer how the loop works.
    // Copy stays review-gated: quoted payouts on eligible jobs only, and review
    // decides payout eligibility rather than promising payment.

    private var earningExplainerCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                BPEyebrow("How earning works", color: BP.brassDeep)
                Spacer()
                Button {
                    withAnimation(BPMotion.transition) { hasDismissedEarningExplainer = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BP.textFaint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
            BPNumberedStepRow(index: 1, text: "Pick a nearby job — eligible jobs show a quoted payout.")
            BPNumberedStepRow(index: 2, text: "Walk the space and record with your iPhone.")
            BPNumberedStepRow(index: 3, text: "Quality and rights review decides payout eligibility.")
        }
        .padding(Space.l)
        .bpCard()
    }

    // MARK: Uploads in flight (real queue state)

    @ViewBuilder
    private var uploadsInFlightCard: some View {
        let active = uploadQueue.uploadStatuses.filter {
            if case .completed = $0.state { return false }
            return true
        }
        if !active.isEmpty {
            VStack(spacing: Space.m) {
                ForEach(active) { status in
                    let entry = BPStatusPresentation.entry(for: status.state)
                    HStack(spacing: Space.m) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(entry.signal.fg)
                        VStack(alignment: .leading, spacing: 2) {
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

    // MARK: Active assignment (real)

    private func activeCard(_ item: ScanHomeViewModel.JobItem) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                openDetail(item)
            } label: {
                BPRemoteFacilityImage(
                    url: item.job.heroImageURL ?? item.job.thumbnailURL ?? item.previewURL,
                    height: 156
                )
                .overlay(alignment: .topLeading) {
                    BPStatusChip(item.permissionTier.shortLabel, signal: BPSignalMapping.signal(for: item.permissionTier))
                        .padding(Space.m)
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline) {
                Text(item.job.title)
                    .font(.bpSans(BPType.bodyL, .semibold))
                    .foregroundStyle(BP.textStrong)
                Spacer(minLength: Space.m)
                if let payout = payoutDollars(for: item) {
                    Text(BPFormat.currency(payout))
                        .font(.bpMono(BPType.bodyL))
                        .foregroundStyle(BP.textStrong)
                }
            }

            Text([item.job.category ?? item.job.address, item.distanceLabel]
                .joined(separator: "  ·  "))
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)

            HStack(spacing: Space.s) {
                BPPrimaryButton(
                    title: reservingJobId == item.id ? "Reserving…" : "Continue capture",
                    systemImage: "camera.aperture"
                ) {
                    Task { await reserveAndLaunch(item) }
                }
                .disabled(reservingJobId != nil || item.permissionTier == .blocked)

                Button {
                    openDetail(item)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(BP.textStrong)
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(BP.lineStrong, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("View task details")
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .bpCard()
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("No assignments nearby yet")
                .font(.bpSans(BPType.bodyL, .semibold))
                .foregroundStyle(BP.textStrong)
            Text("Assignments appear when published sites are near you. Open capture is always available where you have permission — those uploads enter review first.")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            BPPrimaryButton(title: "Start open capture", systemImage: "camera.aperture") {
                coordinator.startCapture()
            }
            .padding(.top, Space.xs)
            Button("How Blueprint works") { showingHowItWorks = true }
                .font(.bpSans(BPType.bodyS, .semibold))
                .foregroundStyle(BP.brassDeep)
                .underline()
        }
        .padding(Space.l)
        .bpCard()
    }

    // MARK: Nearby (real)

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby")
                    .font(.bpSans(BPType.title, .semibold))
                    .tracking(BPTracking.headline)
                    .foregroundStyle(BP.textStrong)
                Spacer()
                if !viewModel.items.isEmpty {
                    BPTextAction(title: "Map") { showingMap = true }
                        .accessibilityLabel("Open nearby map")
                }
            }

            if nearbyItems.isEmpty {
                Text("Pull to refresh, or check back once you’re near a published site.")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textFaint)
            } else {
                VStack(spacing: Space.m) {
                    ForEach(nearbyItems) { item in
                        Button {
                            openDetail(item)
                        } label: {
                            BPJobRow(item: item, isReserving: reservingJobId == item.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(reservingJobId != nil)
                        .accessibilityLabel("\(item.job.title), \(item.payoutLabel), \(item.distanceLabel). Opens task detail.")
                    }
                }
            }
        }
    }

    // MARK: Navigation

    private func openDetail(_ item: ScanHomeViewModel.JobItem) {
        detailItem = item
        showingDetail = true
    }

    // MARK: Reservation → capture launch (CAP-04 → CAP-01)

    private func reserveAndLaunch(_ item: ScanHomeViewModel.JobItem) async {
        guard reservingJobId == nil else { return }
        reservingJobId = item.id
        defer { reservingJobId = nil }

        let job = item.job

        // Reserve + check in against the marketplace target_state doc, mirroring the
        // legacy ScanRecordingView flow. This is what makes the claim real and yields
        // an authoritative capture_job_id (job.id). Open-capture-here has no
        // marketplace document, so we skip reservation for it.
        if job.id != ScanHomeViewModel.alphaCurrentLocationJobID {
            do {
                let target = Target(
                    id: job.id,
                    displayName: job.title,
                    sku: .B,
                    lat: job.lat,
                    lng: job.lng,
                    address: job.address,
                    demandScore: nil,
                    sizeSqFt: nil,
                    category: job.category,
                    computedDistanceMeters: nil
                )
                _ = try await targetStateService.reserve(target: target, for: 60 * 60)
                try await targetStateService.checkIn(targetId: job.id)
            } catch {
                reservationError = "This job is already reserved or in progress."
                return
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showingDetail = false
        coordinator.startCapture(seed: seed(for: item))
    }

    /// Builds the real capture-job seed carrying the reserved `capture_job_id`.
    /// Mirrors `ScanHomeView.submissionSeed(for:)` so the redesign path produces the
    /// same upload metadata the legacy path does.
    private func seed(for item: ScanHomeViewModel.JobItem) -> SpaceReviewSeed {
        let contextParts = [item.job.workflowName, item.job.targetKPI, item.job.zone].compactMap { $0 }
        let suggestedContext = contextParts.isEmpty ? nil : contextParts.joined(separator: " • ")

        let isApprovedLaunchScope = item.permissionTier == .approved
        let hasUpstreamBootstrap = item.job.siteSubmissionId != nil || item.job.buyerRequestId != nil
        let defaultRequestedOutputs = (isApprovedLaunchScope || hasUpstreamBootstrap)
            ? CaptureRequestedOutputs.robotEvaluation
            : CaptureRequestedOutputs.reviewIntake
        let requestedOutputs = item.job.requestedOutputs.isEmpty
            ? defaultRequestedOutputs
            : CaptureRequestedOutputs.normalized(item.job.requestedOutputs)

        let intakePacket = item.job.qualificationIntakePacket
        let approvedIntakePacket = (isApprovedLaunchScope && intakePacket.isComplete) ? intakePacket : nil
        let captureRights: CaptureRightsMetadata? = isApprovedLaunchScope ? CaptureRightsMetadata(
            derivedSceneGenerationAllowed: true,
            dataLicensingAllowed: true,
            payoutEligible: item.job.quotedPayoutCents != nil,
            consentStatus: item.job.captureConsentStatus,
            permissionDocumentURI: item.job.permissionDocURL?.absoluteString,
            consentScope: item.job.allowedAreas,
            consentNotes: item.job.rightsChecklist + item.job.approvalRequirements + item.job.captureRestrictions,
            venuePermission: VenuePermission.from(job: item.job)
        ) : nil
        let requestedCaptureMode = approvedIntakePacket == nil ? nil : "site_world_candidate"

        return SpaceReviewSeed(
            id: item.job.id,
            title: item.job.title,
            address: item.job.address,
            payoutRange: item.job.quotedPayoutCents.map { max(5, $0 / 100 - 10)...($0 / 100) },
            captureJobId: item.job.id,
            buyerRequestId: item.job.buyerRequestId,
            siteSubmissionId: item.job.siteSubmissionId,
            regionId: item.job.regionId,
            rightsProfile: item.job.rightsProfile,
            requestedOutputs: requestedOutputs,
            suggestedContext: suggestedContext,
            intakePacket: approvedIntakePacket,
            captureRights: captureRights,
            requestedCaptureMode: requestedCaptureMode
        )
    }

    // MARK: Helpers

    private func payoutDollars(for item: ScanHomeViewModel.JobItem) -> Double? {
        let cents = item.job.quotedPayoutCents ?? item.job.payoutCents
        guard cents > 0 else { return nil }
        return Double(cents) / 100.0
    }
}

// MARK: - Real job row

struct BPJobRow: View {
    let item: ScanHomeViewModel.JobItem
    var isReserving: Bool = false

    var body: some View {
        HStack(spacing: Space.m) {
            BPRemoteFacilityImage(
                url: item.job.thumbnailURL ?? item.previewURL,
                height: 52
            )
            .frame(width: 52)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.job.title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text([item.job.category ?? item.job.address, item.distanceLabel].joined(separator: "  ·  "))
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.s) {
                let cents = item.job.quotedPayoutCents ?? item.job.payoutCents
                if cents > 0 {
                    Text(BPFormat.currency(Double(cents) / 100.0))
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textStrong)
                } else {
                    // Rights pending: no payout shown — the boundary stays honest.
                    Text("—")
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textFaint)
                }
                BPStatusChip(item.permissionTier.shortLabel, signal: signal)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BP.textFaint)
        }
        .padding(Space.l)
        .bpCard()
        .opacity(isReserving ? 0.5 : 1)
    }

    private var signal: BPSignal {
        BPSignalMapping.signal(for: item.permissionTier)
    }
}

#if DEBUG
#Preview {
    let alertsManager = NearbyAlertsManager()
    return BPHomeTab(alertsManager: alertsManager)
        .environmentObject(RedesignCoordinator())
        .environmentObject(GlassesCaptureManager())
        .environmentObject(UploadQueueViewModel())
        .environmentObject(alertsManager)
}
#endif
