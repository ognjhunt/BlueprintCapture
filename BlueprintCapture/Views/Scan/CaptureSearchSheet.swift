import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - MapKit autocomplete coordinator

/// Wraps MKLocalSearchCompleter so SwiftUI can observe completions reactively.
/// Uses `.pointOfInterest` + `.address` result types so both named commercial
/// spaces (malls, warehouses, stores) and raw street addresses come through.
/// The `region` is centred on the user's GPS position for local bias.
private final class LocationCompleter: NSObject, MKLocalSearchCompleterDelegate, ObservableObject {
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        // No tight POI category filter — we want any physical space that can be walked.
        // Region bias is set from user GPS via updateRegion().
    }

    func updateRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }

    func search(_ query: String) {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completions = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
    }
}

// MARK: - Sheet

struct CaptureSearchSheet: View {
    let existingItems: [ScanHomeViewModel.JobItem]
    let userLocation: CLLocation?
    let onSelectItem: (ScanHomeViewModel.JobItem) -> Void
    let onSubmitAddress: (String, String?) -> Void  // (address, suggestedContext)

    @StateObject private var locationCompleter = LocationCompleter()
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var jobResults: [SearchResult] = []
    @State private var selectedAddressLabel = ""
    @State private var selectedAddressSubtitle = ""
    @State private var isResolvingAddress = false   // resolving completion → coordinate
    @State private var isSearchingJobs = false
    @State private var isGeneratingDraft = false
    @State private var generatedDraftContext: String? = nil
    @State private var nearbyExamples: [(title: String, subtitle: String)] = []
    @State private var isLoadingExamples = false
    @FocusState private var fieldFocused: Bool

    private var isSearchingAddresses: Bool { locationCompleter.isSearching || isResolvingAddress }
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
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                HStack {
                    Text("Search")
                        .font(BlueprintTheme.display(28, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(BlueprintTheme.body(14, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Search field
                HStack(spacing: 10) {
                    Image(systemName: isSearchingAddresses ? "arrow.clockwise" : "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(fieldFocused ? BlueprintTheme.textPrimary : BlueprintTheme.textSecondary)
                        .rotationEffect(.degrees(isSearchingAddresses ? 360 : 0))
                        .animation(isSearchingAddresses ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSearchingAddresses)

                    TextField("Mall, store, or address…", text: $query)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { locationCompleter.search(query) }
                        .onChange(of: query) { _, newVal in
                            if newVal.isEmpty {
                                locationCompleter.completions = []
                                phase = .idle
                            } else {
                                phase = .addresses
                                locationCompleter.search(newVal)
                            }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            locationCompleter.completions = []
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
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(fieldFocused ? Color.white.opacity(0.18) : BlueprintTheme.hairline, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Searching jobs indicator
                if isSearchingJobs {
                    HStack(spacing: 8) {
                        ProgressView().tint(BlueprintTheme.textPrimary).scaleEffect(0.75)
                        Text("Finding captures near \(selectedAddressLabel)…")
                            .font(BlueprintTheme.body(12, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
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
        .blueprintAppBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            if let coord = userLocation?.coordinate {
                locationCompleter.updateRegion(center: coord)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
            Task { await loadNearbyExamples() }
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
                    .font(BlueprintTheme.display(24, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Text("Search a mall, store, or address to see\nif there's an active capture job nearby.")
                    .font(BlueprintTheme.body(14, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Dynamic nearby suggestions from MapKit POI search
            VStack(spacing: 8) {
                if isLoadingExamples {
                    // Skeleton shimmer while loading
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.08))
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.12), lineWidth: 1))
                    }
                } else if nearbyExamples.isEmpty {
                    // No location or no results — generic fallback
                    exampleChip(title: "South Park Mall", subtitle: "")
                    exampleChip(title: "Whole Foods Market", subtitle: "")
                    exampleChip(title: "123 Main St", subtitle: "")
                } else {
                    ForEach(nearbyExamples, id: \.title) { place in
                        exampleChip(title: place.title, subtitle: place.subtitle)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func exampleChip(title: String, subtitle: String) -> some View {
        Button {
            query = title
            phase = .addresses
            locationCompleter.search(title)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(BlueprintTheme.body(11, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, subtitle.isEmpty ? 12 : 10)
            .blueprintEditorialCard(radius: 14, fill: BlueprintTheme.panel)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Address Results

    private var addressList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Suggested Locations")
                .padding(.bottom, 12)

            if locationCompleter.completions.isEmpty && !isSearchingAddresses {
                Text("No results found")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(locationCompleter.completions, id: \.self) { completion in
                        Button { resolveAndSelect(completion) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(BlueprintTheme.body(14, weight: .semibold))
                                        .foregroundStyle(BlueprintTheme.textPrimary)
                                        .lineLimit(1)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(BlueprintTheme.body(12, weight: .medium))
                                            .foregroundStyle(BlueprintTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)

                        if completion != locationCompleter.completions.last {
                            Rectangle().fill(Color(white: 0.12)).frame(height: 1).padding(.leading, 66)
                        }
                    }
                }
                .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
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
                    .font(BlueprintTheme.body(12, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
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
            case .approved:         return (BlueprintTheme.textPrimary, "Approved")
            case .reviewRequired:   return (BlueprintTheme.textSecondary, "Review")
            case .permissionRequired: return (BlueprintTheme.textSecondary, "Permission")
            case .blocked:          return (BlueprintTheme.textTertiary, "Blocked")
            }
        }()

        return HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BlueprintTheme.panelStrong)
                    .frame(width: 52, height: 52)

                CapturePreviewView(
                    coordinate: item.job.coordinate,
                    remoteImageURL: nil,
                    preferredAssetName: preferredAssetName(for: item)
                )
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.job.title)
                    .font(BlueprintTheme.body(14, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                    .lineLimit(1)
                Text(item.job.address)
                    .font(BlueprintTheme.body(12, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(item.payoutLabel, systemImage: "dollarsign.circle.fill")
                        .font(BlueprintTheme.body(12, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Text("·")
                        .foregroundStyle(BlueprintTheme.textTertiary)
                        .font(BlueprintTheme.body(12, weight: .medium))
                    Text(result.distanceLabel)
                        .font(BlueprintTheme.body(12, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(tierColor).frame(width: 6, height: 6)
                    Text(tierLabel)
                        .font(BlueprintTheme.body(11, weight: .semibold))
                        .foregroundStyle(tierColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BlueprintTheme.panelStrong, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
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
                    .font(BlueprintTheme.display(22, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                Text("There's no active capture job registered\nnear \(selectedAddressLabel).")
                    .font(BlueprintTheme.body(14, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
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
                    .fill(BlueprintTheme.textPrimary)
                    .frame(width: 3)
                    .cornerRadius(2)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Submit This Space for Review")
                            .font(BlueprintTheme.body(14, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)

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
                                    .foregroundStyle(BlueprintTheme.textPrimary)
                                Text("Context pre-filled by AI")
                                    .font(BlueprintTheme.body(12, weight: .medium))
                                    .foregroundStyle(BlueprintTheme.textSecondary)
                            }
                        } else {
                            Text("Nominate it to become an approved capture job")
                                .font(BlueprintTheme.body(12, weight: .medium))
                                .foregroundStyle(BlueprintTheme.textSecondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .blueprintEditorialCard(radius: 16, fill: BlueprintTheme.panel)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isGeneratingDraft)
        .animation(.easeInOut(duration: 0.2), value: generatedDraftContext != nil)
    }

    // MARK: - Nearby examples

    /// Fetches real nearby commercial spaces from MapKit POI search to populate
    /// the idle-state suggestion chips. Three parallel queries cover different
    /// space types (retail, food market, restaurant/café) so chips are diverse
    /// rather than all the same category.
    private func loadNearbyExamples() async {
        guard let coord = userLocation?.coordinate else { return }
        await MainActor.run { isLoadingExamples = true }

        async let retail  = searchNearbyPOIs(coord: coord, categories: [.store],       limit: 2)
        async let grocery = searchNearbyPOIs(coord: coord, categories: [.foodMarket],  limit: 1)
        async let dining  = searchNearbyPOIs(coord: coord, categories: [.restaurant, .cafe], limit: 1)

        let (r, g, d) = await (retail, grocery, dining)

        // Build a diverse set: prefer one of each category, fill remainder with retail
        var merged: [(title: String, subtitle: String)] = []
        if let first = r.first  { merged.append(first) }
        if let first = g.first  { merged.append(first) }
        if let first = d.first  { merged.append(first) }
        // If we still have fewer than 3, backfill with any remaining retail hits
        for item in r.dropFirst() where merged.count < 3 { merged.append(item) }

        await MainActor.run {
            nearbyExamples = Array(merged.prefix(3))
            isLoadingExamples = false
        }
    }

    private func searchNearbyPOIs(
        coord: CLLocationCoordinate2D,
        categories: [MKPointOfInterestCategory],
        limit: Int
    ) async -> [(title: String, subtitle: String)] {
        let request = MKLocalSearch.Request()
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 3000,
            longitudinalMeters: 3000
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(limit).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let parts: [String?] = [item.placemark.locality, item.placemark.administrativeArea]
            let subtitle = parts.compactMap { $0 }.joined(separator: ", ")
            return (title: name, subtitle: subtitle)
        }
    }

    // MARK: - Logic

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BlueprintTheme.display(22, weight: .semibold))
            .foregroundStyle(BlueprintTheme.textPrimary)
            .tracking(1.0)
    }

    private func preferredAssetName(for item: ScanHomeViewModel.JobItem) -> String {
        let category = (item.job.category ?? "").lowercased()
        if category.contains("industrial") || category.contains("warehouse") || category.contains("logistics") {
            return "CaptureWarehouseHero"
        }
        return "CaptureRetailHero"
    }

    /// Resolves an MKLocalSearchCompletion to real coordinates, then passes it
    /// downstream. MKLocalSearchCompleter gives us name + subtitle instantly but
    /// no coordinates; MKLocalSearch.Request(completion:) resolves those on tap.
    private func resolveAndSelect(_ completion: MKLocalSearchCompletion) {
        isResolvingAddress = true
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                let coord = item.placemark.coordinate
                let parts: [String?] = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea]
                let resolvedSubtitle = parts.compactMap { $0 }.joined(separator: ", ")
                let result = AddressResult(
                    title: completion.title,
                    subtitle: resolvedSubtitle.isEmpty ? completion.subtitle : resolvedSubtitle,
                    coordinate: coord
                )
                await MainActor.run {
                    isResolvingAddress = false
                    selectAddress(result)
                }
            } else {
                await MainActor.run { isResolvingAddress = false }
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
