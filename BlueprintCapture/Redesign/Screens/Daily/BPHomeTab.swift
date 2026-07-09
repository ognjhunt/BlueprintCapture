import SwiftUI

// MARK: - Home / assignments (tab: Home)
//
// CAP-04: this screen is bound to the real discovery/reservation engine
// (`ScanHomeViewModel` + `NearbyAlertsManager`), not `BPSample.*` constants. Nearby
// and active assignments come from the live `capture_jobs` feed. Selecting a job
// reserves/claims it (yielding a stable `capture_job_id`) and launches the real
// capture engine with that id threaded through (CAP-01).

struct BPHomeTab: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @EnvironmentObject private var glassesManager: GlassesCaptureManager
    @EnvironmentObject private var uploadQueue: UploadQueueViewModel
    @EnvironmentObject private var alertsManager: NearbyAlertsManager

    @StateObject private var viewModel: ScanHomeViewModel
    @State private var reservingJobId: String?
    @State private var reservationError: String?

    private let targetStateService: TargetStateServiceProtocol = TargetStateService()

    init() {
        // The real discovery view model requires a NearbyAlertsManager. The app
        // injects a single shared instance as an environment object; SwiftUI can't
        // read environment objects at init time, so we seed the StateObject with a
        // fresh manager and re-point discovery at the injected one in `.task`.
        _viewModel = StateObject(wrappedValue: ScanHomeViewModel(alertsManager: NearbyAlertsManager()))
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
        }
        .task {
            viewModel.onAppear()
            await viewModel.refresh()
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
                BPEyebrow(coordinator.capturerCity, color: BP.brassDeep)
                Text("\(greeting), \(coordinator.capturerName)")
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
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(BP.blockFg).frame(width: 8, height: 8).offset(x: -10, y: 12)
                    }
                    .contentShape(Rectangle())
            }
            .offset(x: 8)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Active assignment (real)

    private func activeCard(_ item: ScanHomeViewModel.JobItem) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPFacilityImage(name: "pov-warehouse-tote", height: 156)
                .overlay(alignment: .topLeading) {
                    BPStatusChip(item.permissionTier.shortLabel, signal: signal(for: item.permissionTier))
                        .padding(Space.m)
                }

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

            Text([item.job.title, item.job.category ?? item.job.address, item.distanceLabel]
                .joined(separator: "  ·  "))
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)

            BPPrimaryButton(
                title: reservingJobId == item.id ? "Reserving…" : "Continue capture",
                systemImage: "camera.aperture"
            ) {
                Task { await reserveAndLaunch(item) }
            }
            .disabled(reservingJobId != nil || item.permissionTier == .blocked)
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
            Text("Move closer to a published site, or start an open capture where you have permission.")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.textMuted)
            BPPrimaryButton(title: "Start open capture", systemImage: "camera.aperture") {
                coordinator.startCapture()
            }
            .padding(.top, Space.xs)
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
            }

            if nearbyItems.isEmpty {
                Text("Pull to refresh, or check back once you’re near a published site.")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textFaint)
            } else {
                VStack(spacing: Space.m) {
                    ForEach(nearbyItems) { item in
                        Button {
                            Task { await reserveAndLaunch(item) }
                        } label: {
                            BPJobRow(item: item, isReserving: reservingJobId == item.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(reservingJobId != nil || item.permissionTier == .blocked)
                    }
                }
            }
        }
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

    private func signal(for tier: ScanHomeViewModel.CapturePermissionTier) -> BPSignal {
        switch tier {
        case .approved: return .proof
        case .reviewRequired: return .info
        case .permissionRequired: return .caution
        case .blocked: return .caution
        }
    }
}

// MARK: - Real job row

struct BPJobRow: View {
    let item: ScanHomeViewModel.JobItem
    var isReserving: Bool = false

    var body: some View {
        HStack(spacing: Space.m) {
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
        }
        .padding(Space.l)
        .bpCard()
        .opacity(isReserving ? 0.5 : 1)
    }

    private var signal: BPSignal {
        switch item.permissionTier {
        case .approved: return .proof
        case .reviewRequired: return .info
        case .permissionRequired: return .caution
        case .blocked: return .caution
        }
    }
}

#if DEBUG
#Preview {
    BPHomeTab()
        .environmentObject(RedesignCoordinator())
        .environmentObject(GlassesCaptureManager())
        .environmentObject(UploadQueueViewModel())
        .environmentObject(NearbyAlertsManager())
}
#endif
