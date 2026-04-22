import SwiftUI
import CoreLocation

struct LocationConfirmationView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var showManualEntry = false
    @State private var searchQuery = ""
    @State private var isGeneratingDraft = false
    @State private var lastGeneratedAddress: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.isSpaceReviewMode ? "Submit a Space" : "Confirm Location")
                            .font(BlueprintTheme.display(34, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                        Text(viewModel.isSpaceReviewMode
                             ? "Tell us where the space is, why it matters, and confirm capture guardrails."
                             : "We use your current position to anchor the walkthrough to an exact address.")
                            .font(BlueprintTheme.body(15, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 28)

                    // Address card
                    sectionLabel("Location")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    addressCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    if !showManualEntry {
                        Button {
                            showManualEntry = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.hasSeedAddress ? "arrow.triangle.2.circlepath" : "pencil.circle")
                                    .font(.caption)
                                Text(viewModel.hasSeedAddress ? "Change location" : "Can't find it? Enter address manually")
                                    .font(BlueprintTheme.body(12, weight: .medium))
                            }
                            .foregroundStyle(BlueprintTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    } else {
                        manualEntryCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                    }

                    // Space review extras
                    if viewModel.isSpaceReviewMode {
                        sectionLabel("Context")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        contextCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        sectionLabel("Before You Record")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        checklistCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                    }

                    // CTA
                    ctaButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
        }
        .blueprintAppBackground()
        .task {
            if viewModel.currentAddress == nil && !viewModel.hasSeedAddress {
                viewModel.locationManager.requestLocation()
            }
        }
        .onChange(of: viewModel.currentAddress) { _, newAddress in
            guard viewModel.isSpaceReviewMode,
                  let address = newAddress,
                  address != lastGeneratedAddress,
                  viewModel.spaceContextNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            lastGeneratedAddress = address
            Task { await autofillDraft(address: address) }
        }
    }

    // MARK: - Address Card

    private var addressCard: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.hasSeedAddress ? "mappin.circle.fill" : "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    BlueprintTheme.panelStrong,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                if let address = viewModel.currentAddress {
                    Text(address)
                        .font(BlueprintTheme.body(14, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .lineLimit(2)
                    if viewModel.hasSeedAddress {
                        Text("From your search")
                            .font(BlueprintTheme.body(11, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                } else if let error = viewModel.locationError {
                    Text(error)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(BlueprintTheme.textPrimary)
                            .scaleEffect(0.8)
                        Text("Detecting location…")
                            .font(BlueprintTheme.body(14, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
    }

    // MARK: - Manual Entry Card

    private var manualEntryCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Search address")
                    .font(BlueprintTheme.body(14, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Spacer()
                Button("Cancel") {
                    showManualEntry = false
                    searchQuery = ""
                    viewModel.addressSearchResults = []
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color(white: 0.12))
                .frame(height: 1)
                .padding(.leading, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.textSecondary)
                TextField("Street address, city…", text: $searchQuery)
                    .font(BlueprintTheme.body(14, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                    .autocorrectionDisabled()
                    .textContentType(.addressCityAndState)
                    .onChange(of: searchQuery) { _, newValue in
                        if newValue.count > 2 {
                            Task { await viewModel.searchAddresses(query: newValue) }
                        } else {
                            viewModel.addressSearchResults = []
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if viewModel.isSearchingAddress {
                HStack(spacing: 8) {
                    ProgressView().tint(BlueprintTheme.brandTeal).scaleEffect(0.75)
                    Text("Searching…")
                        .font(BlueprintTheme.body(12, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if !viewModel.addressSearchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.addressSearchResults) { result in
                        Button {
                            viewModel.selectAddress(result)
                            showManualEntry = false
                            searchQuery = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(BlueprintTheme.body(14, weight: .medium))
                                        .foregroundStyle(BlueprintTheme.textPrimary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(BlueprintTheme.body(12, weight: .medium))
                                            .foregroundStyle(BlueprintTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(BlueprintTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Color(white: 0.12))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
    }

    // MARK: - Context Card

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Why is this space worth reviewing?")
                    .font(BlueprintTheme.body(14, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Spacer()
                if isGeneratingDraft {
                    HStack(spacing: 5) {
                        ProgressView().tint(BlueprintTheme.brandTeal).scaleEffect(0.65)
                        Text("AI drafting…")
                            .font(BlueprintTheme.body(11, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                } else if SpaceDraftGenerator.shared.isAvailable && viewModel.spaceContextNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        guard let address = viewModel.currentAddress else { return }
                        Task { await autofillDraft(address: address) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.semibold))
                            Text("Auto-fill")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BlueprintTheme.panelStrong, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                if viewModel.spaceContextNotes.isEmpty && !isGeneratingDraft {
                    Text("Tell us what makes this space valuable to capture…")
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.spaceContextNotes)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .font(BlueprintTheme.body(14, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .background(Color.clear)
                    .opacity(isGeneratingDraft ? 0.4 : 1)
            }

            Text("Example: active loading area, repeated congestion, strong coverage potential, or buyer-requested zone.")
                .font(BlueprintTheme.body(12, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
        .animation(.easeInOut(duration: 0.2), value: isGeneratingDraft)
    }

    // MARK: - LLM Auto-fill

    @MainActor
    private func autofillDraft(address: String) async {
        guard SpaceDraftGenerator.shared.isAvailable else { return }
        isGeneratingDraft = true
        viewModel.spaceContextNotes = ""

        let result = await SpaceDraftGenerator.shared.streamDraft(
            placeName: address,
            address: address
        ) { partial in
            Task { @MainActor in
                self.viewModel.spaceContextNotes = partial
            }
        }

        if let r = result {
            viewModel.spaceContextNotes = r.contextNotes
        }
        isGeneratingDraft = false
    }

    // MARK: - Checklist Card

    private var checklistCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.spaceReviewChecklist.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .frame(width: 22)
                    Text(item)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(Color(white: 0.12))
                    .frame(height: 1)
                    .padding(.leading, 50)
            }

            HStack {
                Text("I can follow these capture rules")
                    .font(BlueprintTheme.body(14, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Spacer()
                Toggle("", isOn: $viewModel.confirmedCaptureGuidelines)
                    .labelsHidden()
                    .tint(Color.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        let canContinue = viewModel.currentAddress != nil && viewModel.canConfirmAddress
        let label = viewModel.currentAddress == nil
            ? "Retry Location"
            : (viewModel.isSpaceReviewMode ? "Continue to Capture" : "Use This Location")

        return Button {
            if viewModel.canConfirmAddress {
                viewModel.confirmAddress()
            } else {
                viewModel.locationManager.requestLocation()
            }
        } label: {
            Text(label)
                .font(BlueprintTheme.body(16, weight: .semibold))
                .foregroundStyle(canContinue ? .black : Color(white: 0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canContinue ? Color.white : Color.white.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled((viewModel.currentAddress == nil && viewModel.locationError == nil) ||
                  (viewModel.currentAddress != nil && !viewModel.canConfirmAddress))
    }

    // MARK: - Helper

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BlueprintTheme.display(22, weight: .semibold))
            .foregroundStyle(BlueprintTheme.textPrimary)
            .tracking(1.0)
    }
}

#Preview {
    LocationConfirmationView(viewModel: CaptureFlowViewModel())
}
