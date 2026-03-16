import SwiftUI
import MapKit
import CoreLocation

struct CaptureSearchSheet: View {
    let existingItems: [ScanHomeViewModel.JobItem]
    let onSelectItem: (ScanHomeViewModel.JobItem) -> Void
    let onSubmitAddress: (String, String?) -> Void  // (address, suggestedContext)

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var addressResults: [AddressResult] = []
    @State private var jobResults: [SearchResult] = []
    @State private var selectedAddressLabel = ""
    @State private var selectedAddressSubtitle = ""
    @State private var isSearchingAddresses = false
    @State private var isSearchingJobs = false
    @State private var isGeneratingDraft = false
    @State private var generatedDraftContext: String? = nil
    @FocusState private var fieldFocused: Bool

    private let searchRadiusMeters: Double = 1609.34 * 2 // 2 miles

    // MARK: - Types

    enum Phase { case idle, addresses, jobs, empty }

    struct AddressResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
    }

    struct SearchResult: Identifiable {
        let id: String
        let item: ScanHomeViewModel.JobItem
        let distanceFromSearch: Double
        var distanceLabel: String {
            let miles = distanceFromSearch / 1609.34
            return miles < 0.05 ? "Here" : String(format: "%.1f mi", miles)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                HStack {
                    Image(systemName: "b.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Search field
                HStack(spacing: 10) {
                    Image(systemName: isSearchingAddresses ? "arrow.clockwise" : "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(fieldFocused ? BlueprintTheme.brandTeal : Color(white: 0.4))
                        .rotationEffect(.degrees(isSearchingAddresses ? 360 : 0))
                        .animation(isSearchingAddresses ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSearchingAddresses)

                    TextField("Mall, store, or address…", text: $query)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { triggerAddressSearch() }
                        .onChange(of: query) { _, newVal in
                            if newVal.isEmpty {
                                addressResults = []
                                phase = .idle
                            } else if newVal.count >= 2 {
                                triggerAddressSearch()
                            }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            addressResults = []
                            jobResults = []
                            selectedAddressLabel = ""
                            phase = .idle
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.3))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(fieldFocused ? BlueprintTheme.brandTeal.opacity(0.5) : Color(white: 0.14), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Searching jobs indicator
                if isSearchingJobs {
                    HStack(spacing: 8) {
                        ProgressView().tint(BlueprintTheme.brandTeal).scaleEffect(0.75)
                        Text("Finding captures near \(selectedAddressLabel)…")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.4))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch phase {
                        case .idle:
                            idleHint
                        case .addresses:
                            addressList
                        case .jobs:
                            jobList
                        case .empty:
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
        }
    }

    // MARK: - Idle

    private var idleHint: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 32)

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 52))
                .foregroundStyle(Color(white: 0.15))

            VStack(spacing: 6) {
                Text("Find Nearby Opportunities")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.4))
                Text("Search a mall, store, or address to see\nif there's an active capture job nearby.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.25))
                    .multilineTextAlignment(.center)
            }

            // Quick examples
            VStack(spacing: 8) {
                exampleChip("South Park Mall")
                exampleChip("Whole Foods Market")
                exampleChip("123 Main St, Charlotte")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            query = text
            triggerAddressSearch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(white: 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Address Results

    private var addressList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Suggested Locations")
                .padding(.bottom, 12)

            if addressResults.isEmpty && !isSearchingAddresses {
                Text("No results found")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(addressResults) { result in
                        Button { selectAddress(result) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(BlueprintTheme.brandTeal.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Color(white: 0.4))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(white: 0.2))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)

                        if result.id != addressResults.last?.id {
                            Rectangle().fill(Color(white: 0.12)).frame(height: 1).padding(.leading, 66)
                        }
                    }
                }
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(white: 0.12), lineWidth: 1))
            }
        }
    }

    // MARK: - Job Results

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("\(jobResults.count) capture\(jobResults.count == 1 ? "" : "s") near \(selectedAddressLabel)")
                Spacer()
                Text("within 2 mi")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(jobResults) { result in
                    Button {
                        onSelectItem(result.item)
                        dismiss()
                    } label: {
                        jobCard(result)
                    }
                    .buttonStyle(.plain)
                }
            }

            submitCard
                .padding(.top, 20)
                .padding(.bottom, 48)
        }
    }

    private func jobCard(_ result: SearchResult) -> some View {
        let item = result.item
        let (tierColor, tierLabel): (Color, String) = {
            switch item.permissionTier {
            case .approved:         return (BlueprintTheme.successGreen, "Approved")
            case .reviewRequired:   return (BlueprintTheme.brandTeal,    "Review")
            case .permissionRequired: return (Color(red: 0.9, green: 0.55, blue: 0.1), "Permission")
            case .blocked:          return (Color(white: 0.3),           "Blocked")
            }
        }()

        return HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.13))
                    .frame(width: 52, height: 52)

                CapturePreviewView(coordinate: item.job.coordinate, remoteImageURL: item.previewURL)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.job.address)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(item.payoutLabel, systemImage: "dollarsign.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                    Text("·")
                        .foregroundStyle(Color(white: 0.3))
                        .font(.caption)
                    Text(result.distanceLabel)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(tierColor).frame(width: 6, height: 6)
                    Text(tierLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tierColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tierColor.opacity(0.12), in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(white: 0.12), lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 32)

            ZStack {
                Circle()
                    .fill(Color(white: 0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "mappin.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(white: 0.25))
            }

            VStack(spacing: 6) {
                Text("No captures here yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.5))
                Text("There's no active capture job registered\nnear \(selectedAddressLabel).")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.3))
                    .multilineTextAlignment(.center)
            }

            submitCard
                .padding(.top, 4)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Submit Card

    private var submitCard: some View {
        Button {
            let fullAddress = selectedAddressSubtitle.isEmpty
                ? selectedAddressLabel
                : "\(selectedAddressLabel), \(selectedAddressSubtitle)"
            onSubmitAddress(fullAddress, generatedDraftContext)
            dismiss()
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(BlueprintTheme.brandTeal)
                    .frame(width: 3)
                    .cornerRadius(2)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Submit This Space for Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if isGeneratingDraft {
                            HStack(spacing: 5) {
                                ProgressView().tint(BlueprintTheme.brandTeal).scaleEffect(0.6)
                                Text("AI drafting context…")
                                    .font(.caption)
                                    .foregroundStyle(BlueprintTheme.brandTeal)
                            }
                        } else if generatedDraftContext != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.brandTeal)
                                Text("Context pre-filled by AI")
                                    .font(.caption)
                                    .foregroundStyle(BlueprintTheme.brandTeal)
                            }
                        } else {
                            Text("Nominate it to become an approved capture job")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.4))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.25))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BlueprintTheme.brandTeal.opacity(generatedDraftContext != nil ? 0.5 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isGeneratingDraft)
        .animation(.easeInOut(duration: 0.2), value: generatedDraftContext != nil)
    }

    // MARK: - Logic

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }

    private func triggerAddressSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearchingAddresses = true

        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)

            do {
                let response = try await search.start()
                let results: [AddressResult] = response.mapItems.prefix(7).compactMap { item in
                    guard let coord = item.placemark.location?.coordinate else { return nil }
                    let title = item.name ?? item.placemark.name ?? "Unknown"
                    let parts: [String?] = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea]
                    let subtitle = parts.compactMap { $0 }.joined(separator: ", ")
                    return AddressResult(title: title, subtitle: subtitle, coordinate: coord)
                }
                await MainActor.run {
                    addressResults = results
                    phase = .addresses
                    isSearchingAddresses = false
                }
            } catch {
                await MainActor.run {
                    isSearchingAddresses = false
                    if addressResults.isEmpty { phase = .addresses }
                }
            }
        }
    }

    private func selectAddress(_ result: AddressResult) {
        selectedAddressLabel = result.title
        selectedAddressSubtitle = result.subtitle
        fieldFocused = false
        isSearchingJobs = true
        generatedDraftContext = nil
        phase = .addresses

        let searchLocation = CLLocation(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)

        Task {
            var candidates = existingItems

            // Fallback: fetch fresh from Firestore if no pre-loaded items
            if candidates.isEmpty {
                if let jobs = try? await JobsRepository().fetchActiveJobs(limit: 200) {
                    candidates = jobs.compactMap { job -> ScanHomeViewModel.JobItem? in
                        let dist = job.distanceMeters(from: searchLocation)
                        let miles = dist / 1609.34
                        return ScanHomeViewModel.JobItem(
                            job: job,
                            distanceMeters: dist,
                            distanceMiles: miles,
                            targetState: nil,
                            permissionTier: ScanHomeViewModel.permissionTier(for: job),
                            opportunityKind: ScanHomeViewModel.captureOpportunityKind(for: job),
                            previewURL: nil,
                            previewSource: .mapSnapshot
                        )
                    }
                }
            }

            // Re-rank by distance from the searched address
            let results: [SearchResult] = candidates
                .map { item -> SearchResult in
                    let dist = item.job.distanceMeters(from: searchLocation)
                    return SearchResult(id: item.id, item: item, distanceFromSearch: dist)
                }
                .filter { $0.distanceFromSearch <= searchRadiusMeters }
                .sorted { $0.distanceFromSearch < $1.distanceFromSearch }

            await MainActor.run {
                jobResults = results
                isSearchingJobs = false
                phase = results.isEmpty ? .empty : .jobs
            }

            // Kick off background LLM draft generation so it's ready when user taps submit
            Task { await generateDraft() }
        }
    }

    private func generateDraft() async {
        guard SpaceDraftGenerator.shared.isAvailable else { return }
        await MainActor.run { isGeneratingDraft = true }

        let result = await SpaceDraftGenerator.shared.generateDraft(
            placeName: selectedAddressLabel,
            address: selectedAddressSubtitle.isEmpty ? nil : selectedAddressSubtitle
        )

        await MainActor.run {
            generatedDraftContext = result?.contextNotes
            isGeneratingDraft = false
        }
    }
}
