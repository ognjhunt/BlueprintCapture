import SwiftUI
import UIKit

// MARK: - BPOnboardingFlowView
//
// Pre-auth onboarding for the shipping redesign. Value first:
// 1. the dark hero says what Blueprint pays for and how review gates payout,
// 2. a read-only nearby preview shows real capture opportunities around the
//    capturer before any account exists,
// 3. auth is requested from BPAppRoot when the capturer opts in.
// Registration stays required for capture/upload (beta-launch-audit CAP-02) —
// this flow moves discovery in front of the auth wall, it does not bypass it.

struct BPOnboardingFlowView: View {
    /// Which auth form the flow wants opened. Reuses the auth view model's own
    /// mode so there is no second enum to keep in sync.
    var onAuth: (AuthViewModel.Mode) -> Void

    private enum Step {
        case welcome
        case nearby
    }

    @State private var step: Step = .welcome
    @StateObject private var previewViewModel = OnboardingNearbyPreviewViewModel()
    // The redesign previously never recorded the funnel's first step
    // (`onboarding_started` fired only from the retired legacy flow), leaving
    // pre-auth drop-off invisible. Record once per flow appearance — the same
    // per-launch semantics as the legacy flow and as the permission-step events,
    // so funnel stage ratios stay meaningful and ActivationFunnelStore.reset()
    // works without a parallel persistent flag.
    @State private var onboardingStartedRecorded = false

    var body: some View {
        Group {
            switch step {
            case .welcome:
                BPSignInView(
                    onExplore: {
                        withAnimation(BPMotion.transition) { step = .nearby }
                    },
                    onSignIn: { onAuth(.signIn) }
                )
            case .nearby:
                BPNearbyPreviewStepView(
                    viewModel: previewViewModel,
                    onBack: {
                        withAnimation(BPMotion.transition) { step = .welcome }
                    },
                    onCreateAccount: { onAuth(.signUp) },
                    onSignIn: { onAuth(.signIn) }
                )
            }
        }
        .onAppear {
            if !onboardingStartedRecorded {
                onboardingStartedRecorded = true
                ActivationFunnelStore.shared.record(
                    .onboardingStarted,
                    metadata: ["reason": "redesign_onboarding"]
                )
            }
        }
    }
}

// MARK: - Nearby preview step (paper)
//
// Read-only look at real capture opportunities around the capturer before any
// account exists. The create-account CTA stays pinned so the path to auth is
// always one tap away regardless of permission or network state.

struct BPNearbyPreviewStepView: View {
    @ObservedObject var viewModel: OnboardingNearbyPreviewViewModel
    var onBack: () -> Void
    var onCreateAccount: () -> Void
    var onSignIn: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    intro
                    content
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
        .background(BP.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { viewModel.onStepAppear() }
        .onDisappear { viewModel.onStepDisappear() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BP.textStrong)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Spacer()
            BPWordmark()
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BPEyebrow("Around you", color: BP.brassDeep)
            Text("See what you can capture")
                .font(.bpSans(BPType.largeTitle, .bold))
                .tracking(BPTracking.headlineLarge)
                .foregroundStyle(BP.textStrong)
            Text("A read-only look at capture jobs and candidate spaces near you — no account needed to browse.")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Content by phase

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .primer:
            primerCard
        case .locating:
            statusCard(
                title: "Waiting for your location",
                message: "Allow location access when prompted so nearby capture opportunities can load."
            )
        case .loading:
            statusCard(
                title: "Scanning your area",
                message: "Looking for capture jobs and candidate spaces within 10 miles."
            )
        case .denied:
            deniedCard
        case .empty:
            emptyCard
        case .loaded:
            resultsList
        }
    }

    private var primerCard: some View {
        BPCard {
            HStack(spacing: Space.s) {
                Image(systemName: "location.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.brassDeep)
                Text("Location powers the nearby feed")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
            }
            Text("Blueprint asks for “While Using the App” location access to find capture jobs and candidate spaces around you. Nothing is recorded or shared in this preview.")
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            BPPrimaryButton(title: "Show what's near me", systemImage: "location.fill") {
                viewModel.requestLocationAccess()
            }
            .accessibilityIdentifier("onboarding_location_primer_button")
        }
    }

    private func statusCard(title: String, message: String) -> some View {
        BPCard {
            HStack(spacing: Space.m) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(BP.brassDeep)
                Text(title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
            }
            Text(message)
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deniedCard: some View {
        BPCard {
            HStack(spacing: Space.s) {
                Image(systemName: "location.slash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.warnFg)
                Text("Location is off")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
            }
            Text("Nearby capture opportunities can't load without location access. Enable it in Settings, or continue — you can browse the feed after you sign up.")
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            BPGhostButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    private var emptyCard: some View {
        BPCard {
            Text("No mapped spaces here yet")
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Text("Blueprint is expanding city by city. You can still create an account and start an open capture at a place where you have permission — it goes through the same review.")
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Loaded results

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(viewModel.previewItems.count) spots within 10 mi")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                Spacer()
                if viewModel.quotedJobCount > 0 {
                    Text("\(viewModel.quotedJobCount) with quoted payouts")
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.brassDeep)
                }
            }

            searchField

            if viewModel.filteredItems.isEmpty {
                Text("No matches for that search.")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textFaint)
                    .padding(.vertical, Space.m)
            } else {
                VStack(spacing: Space.m) {
                    ForEach(viewModel.filteredItems) { item in
                        BPNearbyPreviewRow(item: item)
                    }
                }
            }

            Text("Payouts are quoted per job before you capture. Spaces without a quote start as reviewed submissions — quality, scope, and rights review decides payout eligibility.")
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BP.textFaint)
            TextField("Search by name or type", text: $viewModel.searchText)
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textStrong)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(BP.textFaint)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(BP.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(BP.line, lineWidth: 1)
        )
    }

    // MARK: Pinned CTA

    private var ctaBar: some View {
        VStack(spacing: 0) {
            BPDivider()
            VStack(spacing: Space.s) {
                BPPrimaryButton(title: "Create a free account to start", systemImage: "arrow.right") {
                    onCreateAccount()
                }
                .accessibilityIdentifier("onboarding_create_account_button")
                Button("I already have an account", action: onSignIn)
                    .buttonStyle(BPGhostButtonStyle())
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
        }
        .background(BP.canvas.ignoresSafeArea())
    }
}

// MARK: - Preview row

struct BPNearbyPreviewRow: View {
    let item: OnboardingNearbyPreviewViewModel.PreviewItem

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text([item.detail, item.distanceLabel].joined(separator: "  ·  "))
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.s) {
                if let payout = item.payoutLabel {
                    Text(payout)
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textStrong)
                } else {
                    // No quoted payout: show the honest placeholder, never an estimate.
                    Text("—")
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textFaint)
                }
                BPStatusChip(chipLabel, signal: chipSignal)
            }
        }
        .padding(Space.l)
        .bpCard()
    }

    private var chipLabel: String {
        guard let tier = item.tier else { return "Candidate" }
        return tier.shortLabel
    }

    private var chipSignal: BPSignal {
        guard let tier = item.tier else { return .neutral }
        switch tier {
        case .approved: return .proof
        case .reviewRequired: return .info
        case .permissionRequired: return .caution
        case .blocked: return .caution
        }
    }
}

#if DEBUG
#Preview {
    BPOnboardingFlowView(onAuth: { (_: AuthViewModel.Mode) in })
}
#endif
