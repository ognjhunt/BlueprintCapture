import SwiftUI
import Combine

struct NearbyTargetsView: View {
    @StateObject private var viewModel = NearbyTargetsViewModel()
    @State private var isRefreshing = false
    @State private var selectedItem: NearbyTargetsViewModel.NearbyItem?
    @State private var showActions = false
    @State private var showReserveConfirm = false
    @State private var reserveMessage: String?
    @State private var navigateToCapture = false
    @StateObject private var captureFlow = CaptureFlowViewModel()
    @State private var activeReservation: Reservation?
    @State private var reservedItem: NearbyTargetsViewModel.NearbyItem?
    @State private var showDirectionsPrompt = false
    @State private var directionsItem: NearbyTargetsViewModel.NearbyItem?
    @State private var now = Date()
    @Environment(\.openURL) private var openURL
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    // Controls whether the action sheet should remain open after dismissing the alert
    @State private var keepActionsOpenAfterAlert = false
    // Switching reservation confirmation state
    @State private var showSwitchReservationConfirm = false
    @State private var pendingReservationItem: NearbyTargetsViewModel.NearbyItem?
    @State private var switchFromTargetId: String?
    @State private var showAddressSheet = false
    @State private var addressQuery: String = ""
    @State private var recentQueries: [RecentQuery] = []
    @FocusState private var isAddressFieldFocused: Bool
    @State private var showWalkthrough = false
    @AppStorage("NearbyTargetsWalkthroughShown") private var walkthroughShown: Bool = false
    @State private var walkthroughPage = 0
    // Alert for reservation expiry while app is active
    @State private var showExpiryAlert = false
    @State private var expiryMessage: String?
    @State private var lastRefreshedAt: Date? = nil
    // Geometry capture
    @State private var filterBarFrame: CGRect = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 8) {
                    currentAddressChip()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .onTapGesture { showAddressSheet = true }
                    FilterBar(radius: $viewModel.selectedRadius, limit: $viewModel.selectedLimit, sort: $viewModel.selectedSort)
                        .padding(.horizontal)
                        .padding(.top, 0)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: FilterBarFrameKey.self, value: proxy.frame(in: .global))
                            }
                        )
                        .onPreferenceChange(FilterBarFrameKey.self) { rect in
                            filterBarFrame = rect
                        }
                    metaBar()
                        .padding(.horizontal)

                    if let reservation = activeReservation, let item = reservedItem, reservation.reservedUntil > now {
                        reservationBanner(item: item, reservation: reservation)
                            .padding(.horizontal)
                    }

                    content
                }

                if showWalkthrough {
                    NearbyWalkthroughOverlay(
                        isVisible: $showWalkthrough,
                        pageIndex: $walkthroughPage,
                        items: viewModel.items,
                        currentAddress: viewModel.currentAddress,
                        filterBarFrame: filterBarFrame,
                        onComplete: {
                            walkthroughShown = true
                            showWalkthrough = false
                        }
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle("Nearby Targets")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $navigateToCapture) {
                CaptureSessionView(viewModel: captureFlow, targetId: reservedItem?.id, reservationId: nil)
            }
        }
        // Transparent nav bar to let hero gradient show through
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .blueprintScreenBackground()
        .task { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showAddressSheet) { addressSearchSheet }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { note in
            guard
                let info = note.userInfo as? [String: Any],
                let action = info["action"] as? String,
                action == "checkin",
                let targetId = info["targetId"] as? String,
                let item = viewModel.items.first(where: { $0.id == targetId })
            else { return }
            selectedItem = item
            showActions = true
        }
        .onReceive(countdownTimer) { date in
            now = date
            if let res = activeReservation, res.reservedUntil <= date {
                let name = reservedItem?.target.displayName ?? "this location"
                expiryMessage = "You didn’t start mapping within the hour, so we auto‑cancelled your reservation for \(name)."
                showExpiryAlert = true
                if let reserved = reservedItem {
                    // Clean up backend and any scheduled expiry notification
                    Task { await viewModel.cancelReservation(for: reserved.id) }
                    viewModel.cancelReservationExpiryNotification(for: reserved.id)
                }
                activeReservation = nil
                reservedItem = nil
            }
        }
        .alert("Reservation expired", isPresented: $showExpiryAlert, actions: {
            Button("OK", role: .cancel) { showExpiryAlert = false }
        }, message: {
            Text(expiryMessage ?? "Your reservation expired.")
        })
        .onChange(of: viewModel.state) { _, newValue in
            if case .loaded = newValue {
                lastRefreshedAt = Date()
                Task { await syncActiveReservationState() }
                if !walkthroughShown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            walkthroughPage = 0
                            showWalkthrough = true
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BlueprintTheme.warningOrange)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await viewModel.refresh() } }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .loaded:
            if viewModel.items.isEmpty {
                VStack(spacing: 8) {
                    Text("No targets within \(String(format: "%.1f", viewModel.selectedRadius.rawValue)) miles")
                        .font(.headline)
                    Button("Expand radius to 5 mi") { viewModel.selectedRadius = .five }
                        .buttonStyle(BlueprintSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    // Pin reserved item (if any) to the top
                    if let res = activeReservation, let pinned = reservedItem {
                        let secondsRemaining = max(0, Int(res.reservedUntil.timeIntervalSince(now)))
                        Section {
                            TargetRow(
                                item: pinned,
                                reservationSecondsRemaining: secondsRemaining,
                                isOnSite: viewModel.isOnSite(pinned.target),
                                reservedByMe: true
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = pinned
                                showActions = true
                            }
                        } header: {
                            Text("Your reservation").font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(viewModel.items) { item in
                        let status = viewModel.reservationStatus(for: item.id)
                        let secondsRemaining: Int? = {
                            if let res = activeReservation, let reserved = reservedItem, reserved.id == item.id {
                                let secs = Int(res.reservedUntil.timeIntervalSince(now))
                                return max(0, secs)
                            }
                            if case .reserved(let until) = status {
                                let secs = Int(until.timeIntervalSince(now))
                                return secs > 0 ? secs : nil
                            }
                            return nil
                        }()
                        let isReservedByMe: Bool = {
                            if let res = activeReservation, let reserved = reservedItem, reserved.id == item.id, res.reservedUntil > now { return true }
                            return false
                        }()
                        // Skip duplicate of pinned row in the main list
                        if reservedItem?.id == item.id { EmptyView() } else {
                            TargetRow(
                                item: item,
                                reservationSecondsRemaining: secondsRemaining,
                                isOnSite: viewModel.isOnSite(item.target),
                                reservedByMe: isReservedByMe
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                                showActions = true
                            }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .background(Color.clear)
                .refreshable {
                    await viewModel.refresh()
                    lastRefreshedAt = Date()
                }
                .sheet(isPresented: $showActions) {
                    if let item = selectedItem { actionSheet(for: item) }
                }
                .alert("Start route?", isPresented: $showDirectionsPrompt, actions: {
                    Button("Start route") {
                        if let item = directionsItem { openDirections(to: item) }
                    }
                    Button("Not now", role: .cancel) {}
                }, message: {
                    Text("You're not on-site yet. Would you like directions to this location?")
                })
            }
        }
    }
}

#Preview {
    NearbyTargetsView()
}

private extension NearbyTargetsView {
    private struct FilterBarFrameKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
    }
    @ViewBuilder
    func currentAddressChip() -> some View {
        if let address = viewModel.currentAddress {
            HStack {
                Spacer(minLength: 0)
                Button {
                    showAddressSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(BlueprintTheme.brandTeal)
                        Text(address)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if viewModel.isUsingCustomSearchCenter {
                            Text("(custom)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                            Text("Change")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BlueprintTheme.primary.opacity(0.12)))
                        .foregroundStyle(BlueprintTheme.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Current area: \(address)")
                .accessibilityHint("Double tap to search a different location")
                Spacer(minLength: 0)
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Detecting your location…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func metaBar() -> some View {
        HStack(spacing: 10) {
            Label("\(viewModel.items.count) results", systemImage: "list.bullet")
                .font(.footnote).foregroundStyle(.secondary)
            if let ts = lastRefreshedAt {
                Text("• Updated \(relativeTime(from: ts))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.refresh(); lastRefreshedAt = Date() }
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(BlueprintTheme.brandTeal)
            }.buttonStyle(.plain)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var addressSearchSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [
                    BlueprintTheme.brandTeal.opacity(0.18),
                    Color(.systemBackground)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    searchHeader

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            searchResultsSection

                            if !recentQueries.isEmpty {
                                sectionHeader("Recent searches")
                                VStack(spacing: 12) {
                                    ForEach(recentQueries) { recent in
                                        Button {
                                            addressQuery = recent.primary
                                            isAddressFieldFocused = true
                                            Task { await viewModel.searchAddresses(query: recent.primary) }
                                        } label: {
                                            recentRow(for: recent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            sectionHeader("Quick filters")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(quickSuggestionItems) { suggestion in
                                        Button {
                                            addressQuery = suggestion.query
                                            isAddressFieldFocused = true
                                            Task { await viewModel.searchAddresses(query: suggestion.query) }
                                        } label: {
                                            suggestionChip(for: suggestion)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if viewModel.isUsingCustomSearchCenter {
                        Button {
                            viewModel.clearCustomSearchCenter()
                            addressQuery = ""
                            showAddressSheet = false
                        } label: {
                            Label("Use my current location", systemImage: "location.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(BlueprintSecondaryButtonStyle())
                    }

                    HStack {
                        Spacer()
                        Label("Powered by Google", systemImage: "globe.americas.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, -4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 12)
            }
            .navigationTitle("Search location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAddressSheet = false }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isAddressFieldFocused = true
                }
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search anywhere")
                .font(.title3.weight(.semibold))
            Text("Find businesses, landmarks, or street addresses powered by Google Places.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BlueprintTheme.brandTeal)

                TextField("Search another address", text: $addressQuery)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($isAddressFieldFocused)
                    .onChange(of: addressQuery) { _, newValue in
                        Task { await viewModel.searchAddresses(query: newValue) }
                    }

                if !addressQuery.isEmpty {
                    Button {
                        addressQuery = ""
                        Task { await viewModel.searchAddresses(query: "") }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 8)
            )
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if viewModel.isSearchingAddress {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(BlueprintTheme.brandTeal)
                Text("Searching Google Places…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.92))
            )
        } else if !viewModel.addressSearchResults.isEmpty {
            sectionHeader("Results")
            VStack(spacing: 14) {
                ForEach(viewModel.addressSearchResults) { result in
                    Button {
                        registerRecentSearch(from: result)
                        viewModel.setCustomSearchCenter(coordinate: result.coordinate, address: result.formatted)
                        addressQuery = ""
                        showAddressSheet = false
                    } label: {
                        searchResultRow(for: result)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if addressQuery.count >= 3 {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash.circle")
                    .font(.system(size: 46))
                    .foregroundStyle(.secondary)
                Text("No matches yet")
                    .font(.headline)
                Text("Try refining the name or adding the city.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.92))
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 56))
                    .foregroundStyle(BlueprintTheme.brandTeal)
                Text("Search for a location")
                    .font(.title3.weight(.semibold))
                Text("Start typing to see live suggestions for stores, landmarks, and addresses nearby.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.92))
            )
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private func searchResultRow(for result: NearbyTargetsViewModel.LocationSearchResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(result.isEstablishment ? BlueprintTheme.brandTeal.opacity(0.2) : Color(.tertiarySystemFill))
                    .frame(width: 44, height: 44)
                Image(systemName: result.isEstablishment ? "building.2.fill" : "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(result.isEstablishment ? BlueprintTheme.brandTeal : .secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if result.isEstablishment {
                        Text("Business")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(BlueprintTheme.brandTeal.opacity(0.15))
                            )
                            .foregroundStyle(BlueprintTheme.brandTeal)
                    }
                }

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !result.types.isEmpty {
                    Text(result.types.prefix(3).joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 12)
        )
    }

    private func recentRow(for recent: RecentQuery) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.fill")
                .font(.subheadline)
                .foregroundStyle(BlueprintTheme.brandTeal)

            VStack(alignment: .leading, spacing: 4) {
                Text(recent.primary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if !recent.secondary.isEmpty {
                    Text(recent.secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "arrow.up.left")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func suggestionChip(for suggestion: QuickSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.subheadline.weight(.semibold))
            Text(suggestion.title)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [suggestion.color.opacity(0.22), suggestion.color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(Capsule())
        )
        .foregroundStyle(suggestion.color.opacity(0.85))
    }

    private func registerRecentSearch(from result: NearbyTargetsViewModel.LocationSearchResult) {
        let entry = RecentQuery(primary: result.title, secondary: result.subtitle)
        if let existingIndex = recentQueries.firstIndex(where: { $0.matches(entry) }) {
            recentQueries.remove(at: existingIndex)
        }
        recentQueries.insert(entry, at: 0)
        if recentQueries.count > 6 {
            recentQueries = Array(recentQueries.prefix(6))
        }
    }

    private var quickSuggestionItems: [QuickSuggestion] {
        [
            QuickSuggestion(icon: "cup.and.saucer.fill", title: "Coffee", query: "coffee", color: .orange),
            QuickSuggestion(icon: "fuelpump.fill", title: "Gas", query: "gas station", color: .red),
            QuickSuggestion(icon: "cart.fill", title: "Groceries", query: "grocery store", color: .green),
            QuickSuggestion(icon: "house.fill", title: "Apartments", query: "apartment", color: .indigo),
            QuickSuggestion(icon: "building.2.fill", title: "Offices", query: "office", color: .blue)
        ]
    }

    private struct RecentQuery: Identifiable, Equatable {
        let id = UUID()
        let primary: String
        let secondary: String

        func matches(_ other: RecentQuery) -> Bool {
            primary.caseInsensitiveCompare(other.primary) == .orderedSame &&
            secondary.caseInsensitiveCompare(other.secondary) == .orderedSame
        }
    }

    private struct QuickSuggestion: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let query: String
        let color: Color
    }
    @ViewBuilder func actionSheet(for item: NearbyTargetsViewModel.NearbyItem) -> some View {
        let status = viewModel.reservationStatus(for: item.id)
        let isReservedHere: Bool = {
            if case .reserved(let until) = status { return until > now }
            return false
        }()
        let isReservedByMe: Bool = {
            // Prefer live target_state owner comparison to work across sessions
            if let s = viewModel.targetStates[item.id], let owner = s.reservedBy {
                return owner == UserDeviceService.resolvedUserId()
            }
            if let res = activeReservation { return res.targetId == item.id && res.reservedUntil > now }
            return false
        }()
        let reservedUntilTime: Date? = {
            if case .reserved(let until) = status { return until }
            return nil
        }()

        VStack(spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.target.displayName).font(.headline)
                Text(item.target.address ?? "").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status text if already reserved
            switch viewModel.reservationStatus(for: item.id) {
            case .reserved(let until):
                Text("Reserved until \(until.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }

            VStack(spacing: 12) {
                if !isReservedHere {
                    Button {
                        attemptReserve(item)
                    } label: {
                        Label("Reserve for 1 hour", systemImage: "clock.badge.checkmark")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                }

                if viewModel.isOnSite(item.target) {
                    Button {
                        // If someone else reserved it, inform instead of attempting check-in
                        if isReservedHere && !isReservedByMe, let until = reservedUntilTime {
                            reserveMessage = "This venue is reserved until \(until.formatted(date: .omitted, time: .shortened)). If that user isn’t checked in and actively mapping by then, you can start mapping once you’re on-site."
                            keepActionsOpenAfterAlert = true
                            showReserveConfirm = true
                        } else {
                            // On-site: perform check-in and navigate to capture
                            Task {
                                do {
                                    try await viewModel.checkIn(item.target)
                                    await MainActor.run {
                                        captureFlow.step = .readyToCapture
                                        captureFlow.captureManager.configureSession()
                                        captureFlow.captureManager.startSession()
                                        navigateToCapture = true
                                        showActions = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        reserveMessage = "We couldn't check you in. Please try again."
                                        showReserveConfirm = true
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Check in & start mapping", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(BlueprintSuccessButtonStyle())
                } else {
                    Button {
                        // Off-site: show guidance alert and keep sheet open; include reservation info if held by someone else
                        if isReservedHere && !isReservedByMe, let until = reservedUntilTime {
                            reserveMessage = "This venue is reserved until \(until.formatted(date: .omitted, time: .shortened)). If that user isn’t checked in and actively mapping by then, you can start once you’re on‑site. You’re not detected on‑site yet."
                        } else {
                            reserveMessage = "You're not detected on-site yet. Head to the location, then tap Check in to begin mapping."
                        }
                        keepActionsOpenAfterAlert = true
                        showReserveConfirm = true
                    } label: {
                        Label("Check in & start mapping", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                }

                if !viewModel.isOnSite(item.target) {
                    Button {
                        openDirections(to: item)
                    } label: {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                }

                // Show Cancel Reservation button if this item is currently reserved by me
                if isReservedByMe {
                    Divider().padding(.vertical, 8)
                    Button(role: .destructive) {
                        Task { await cancelActiveReservation() }
                        showActions = false
                    } label: {
                        Label("Cancel reservation", systemImage: "xmark.circle")
                            .foregroundStyle(BlueprintTheme.errorRed)
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 8)
        }
        .padding()
        .presentationDetents([.medium, .large])
                .alert("Reservation", isPresented: $showReserveConfirm, actions: {
            Button("OK", role: .cancel) {
                // Dismiss alert and optionally keep the action sheet open
                showReserveConfirm = false
                if !keepActionsOpenAfterAlert { showActions = false }
                // Reset for the next alert
                keepActionsOpenAfterAlert = false
            }
        }, message: {
            Text(reserveMessage ?? "")
        })
                .alert("Switch reservation?", isPresented: $showSwitchReservationConfirm, actions: {
                    Button("Switch", role: .destructive) { confirmSwitchReservation() }
                    Button("Keep current", role: .cancel) { showSwitchReservationConfirm = false }
                }, message: {
                    Text("You already have an active reservation. You can only reserve one location at a time. Switching will cancel your current reservation and reserve this new location.")
                })
    }

    @ViewBuilder
    func reservationBanner(item: NearbyTargetsViewModel.NearbyItem, reservation: Reservation) -> some View {
        let seconds = max(0, Int(reservation.reservedUntil.timeIntervalSince(now)))
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.white)
            Text("Reserved: \(item.target.displayName)")
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(formatCountdown(seconds))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BlueprintTheme.primary)
        )
    }

    func formatCountdown(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func openDirections(to item: NearbyTargetsViewModel.NearbyItem) {
        let lat = item.target.lat
        let lng = item.target.lng
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d") {
            openURL(url)
        }
    }

    func cancelActiveReservation() async {
        guard let reserved = reservedItem else { return }
        await viewModel.cancelReservation(for: reserved.id)
        activeReservation = nil
        reservedItem = nil
    }

    // MARK: - Reservation Flow Helpers

    private func attemptReserve(_ item: NearbyTargetsViewModel.NearbyItem) {
        Task {
            // If we already have a local active reservation and it's different, ask to switch
            if let res = activeReservation, let currentItem = reservedItem, res.reservedUntil > now {
                if currentItem.id == item.id {
                    reserveMessage = "You already reserved this location until \(res.reservedUntil.formatted(date: .omitted, time: .shortened))."
                    keepActionsOpenAfterAlert = true
                    showReserveConfirm = true
                    return
                } else {
                    pendingReservationItem = item
                    switchFromTargetId = currentItem.id
                    showSwitchReservationConfirm = true
                    return
                }
            }

            // Fallback to backend check in case local state is empty/out-of-sync
            if activeReservation == nil {
                if let backendActive = await viewModel.fetchCurrentUserActiveReservation() {
                    if backendActive.targetId != item.id {
                        pendingReservationItem = item
                        switchFromTargetId = backendActive.targetId
                        showSwitchReservationConfirm = true
                        return
                    }
                }
            }

            await performReservation(for: item)
        }
    }

    private func performReservation(for item: NearbyTargetsViewModel.NearbyItem) async {
        do {
            let res = try await viewModel.reserveTarget(item.target)
            activeReservation = res
            reservedItem = item
            // Also schedule a background expiry notification just in case user backgrounds the app
            viewModel.scheduleReservationExpiryNotification(for: item.target, at: res.reservedUntil)
            if !viewModel.isOnSite(item.target) {
                directionsItem = item
                showDirectionsPrompt = true
            }
        } catch {
            if let guardError = error as? NearbyTargetsViewModel.ReservationGuardError {
                reserveMessage = guardError.localizedDescription
            } else {
                reserveMessage = "Unable to reserve right now. Please try again."
            }
            keepActionsOpenAfterAlert = true
            showReserveConfirm = true
        }
    }

    private func confirmSwitchReservation() {
        showSwitchReservationConfirm = false
        guard let item = pendingReservationItem else { return }
        Task {
            if let fromId = switchFromTargetId {
                await viewModel.cancelReservation(for: fromId)
            } else if let reserved = reservedItem {
                await viewModel.cancelReservation(for: reserved.id)
            }
            await performReservation(for: item)
            pendingReservationItem = nil
            switchFromTargetId = nil
        }
    }

    // Keep local active reservation in sync with backend across sessions so the action sheet is accurate
    private func syncActiveReservationState() async {
        if let res = await viewModel.fetchCurrentUserActiveReservation() {
            // If the reserved item isn't in the current filtered list, build it explicitly and pin it
            let item = await viewModel.buildItemForTargetId(res.targetId)
            await MainActor.run {
                self.activeReservation = res
                self.reservedItem = item ?? viewModel.items.first(where: { $0.id == res.targetId })
            }
        } else {
            await MainActor.run {
                self.activeReservation = nil
                self.reservedItem = nil
            }
        }
    }
}
