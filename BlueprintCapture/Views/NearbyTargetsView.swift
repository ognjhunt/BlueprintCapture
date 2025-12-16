import SwiftUI
import Combine

struct NearbyTargetsView: View {
    @StateObject private var viewModel = NearbyTargetsViewModel()
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
    @State private var keepActionsOpenAfterAlert = false
    @State private var showSwitchReservationConfirm = false
    @State private var pendingReservationItem: NearbyTargetsViewModel.NearbyItem?
    @State private var switchFromTargetId: String?
    @State private var showAddressSheet = false
    @State private var addressQuery: String = ""
    @State private var recentQueries: [RecentQuery] = []
    @FocusState private var isAddressFieldFocused: Bool
    @State private var showExpiryAlert = false
    @State private var expiryMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Simple location header
                locationHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Active reservation banner (if any)
                if let reservation = activeReservation, let item = reservedItem, reservation.reservedUntil > now {
                    reservationBanner(item: item, reservation: reservation)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                content
            }
            .navigationTitle("Earn")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $navigateToCapture) {
                CaptureSessionView(viewModel: captureFlow, targetId: reservedItem?.id ?? selectedItem?.id, reservationId: nil)
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .blueprintAppBackground()
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
                expiryMessage = "Reservation expired for \(name)."
                showExpiryAlert = true
                if let reserved = reservedItem {
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
                Task { await syncActiveReservationState() }
            }
        }
    }

    // MARK: - Simple Location Header
    private var locationHeader: some View {
        VStack(spacing: 10) {
            Button {
                showAddressSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    if let address = viewModel.currentAddress {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text("Detecting location...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)

            // Recording Policy Filter
            policyFilterBar
        }
    }

    private var policyFilterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Show:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(RecordingPolicyFilter.allCases, id: \.rawValue) { filter in
                policyFilterChip(filter)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func policyFilterChip(_ filter: RecordingPolicyFilter) -> some View {
        Button {
            viewModel.policyFilter = filter
        } label: {
            Text(filter.shortLabel)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(viewModel.policyFilter == filter ? policyFilterColor(filter).opacity(0.15) : Color(.systemFill))
                )
                .overlay(
                    Capsule().stroke(viewModel.policyFilter == filter ? policyFilterColor(filter).opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(viewModel.policyFilter == filter ? policyFilterColor(filter) : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func policyFilterColor(_ filter: RecordingPolicyFilter) -> Color {
        switch filter {
        case .all: return .secondary
        case .excludeRestricted: return .orange
        case .safeOnly: return .green
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Finding opportunities...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Couldn't load opportunities")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await viewModel.refresh() } }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.items.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No opportunities nearby")
                        .font(.headline)
                    Text("Try searching a different location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Search Location") { showAddressSheet = true }
                        .buttonStyle(BlueprintSecondaryButtonStyle())
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.items) { item in
                            let status = viewModel.reservationStatus(for: item.id)
                            let secondsRemaining: Int? = {
                                if let res = activeReservation, let reserved = reservedItem, reserved.id == item.id {
                                    return max(0, Int(res.reservedUntil.timeIntervalSince(now)))
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .sheet(isPresented: $showActions) {
                    if let item = selectedItem { actionSheet(for: item) }
                }
                .alert("Get Directions?", isPresented: $showDirectionsPrompt, actions: {
                    Button("Open Maps") {
                        if let item = directionsItem { openDirections(to: item) }
                    }
                    Button("Not Now", role: .cancel) {}
                }, message: {
                    Text("Navigate to this location to start mapping.")
                })
            }
        }
    }
}

#Preview {
    NearbyTargetsView()
}

private extension NearbyTargetsView {
    private var addressSearchSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search address or place", text: $addressQuery)
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
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                Divider()

                // Results
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.isSearchingAddress {
                            HStack {
                                ProgressView()
                                Text("Searching...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 40)
                        } else if !viewModel.addressSearchResults.isEmpty {
                            ForEach(viewModel.addressSearchResults) { result in
                                Button {
                                    registerRecentSearch(from: result)
                                    viewModel.setCustomSearchCenter(coordinate: result.coordinate, address: result.formatted)
                                    addressQuery = ""
                                    showAddressSheet = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: result.isEstablishment ? "building.2" : "mappin")
                                            .frame(width: 24)
                                            .foregroundStyle(BlueprintTheme.brandTeal)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)

                                Divider().padding(.leading, 56)
                            }
                        } else if addressQuery.isEmpty {
                            // Current location option
                            if viewModel.isUsingCustomSearchCenter {
                                Button {
                                    viewModel.clearCustomSearchCenter()
                                    addressQuery = ""
                                    showAddressSheet = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "location.fill")
                                            .frame(width: 24)
                                            .foregroundStyle(BlueprintTheme.primary)

                                        Text("Use current location")
                                            .foregroundStyle(.primary)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)

                                Divider().padding(.leading, 56)
                            }

                            // Recent searches
                            if !recentQueries.isEmpty {
                                ForEach(recentQueries) { recent in
                                    Button {
                                        addressQuery = recent.primary
                                        isAddressFieldFocused = true
                                        Task { await viewModel.searchAddresses(query: recent.primary) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock")
                                                .frame(width: 24)
                                                .foregroundStyle(.secondary)

                                            Text(recent.primary)
                                                .foregroundStyle(.primary)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)

                                    Divider().padding(.leading, 56)
                                }
                            }
                        } else if addressQuery.count >= 3 {
                            Text("No results found")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAddressSheet = false }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAddressFieldFocused = true
                }
            }
        }
    }

    private func registerRecentSearch(from result: NearbyTargetsViewModel.LocationSearchResult) {
        let entry = RecentQuery(primary: result.title, secondary: result.subtitle)
        if let existingIndex = recentQueries.firstIndex(where: { $0.matches(entry) }) {
            recentQueries.remove(at: existingIndex)
        }
        recentQueries.insert(entry, at: 0)
        if recentQueries.count > 5 {
            recentQueries = Array(recentQueries.prefix(5))
        }
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
    @ViewBuilder func actionSheet(for item: NearbyTargetsViewModel.NearbyItem) -> some View {
        let isReservedByMe: Bool = {
            if let s = viewModel.targetStates[item.id], let owner = s.reservedBy {
                return owner == UserDeviceService.resolvedUserId()
            }
            if let res = activeReservation { return res.targetId == item.id && res.reservedUntil > now }
            return false
        }()
        let isOnSite = viewModel.isOnSite(item.target) || AppConfig.allowOffsiteCheckIn()

        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Location info
            VStack(alignment: .leading, spacing: 6) {
                Text(item.target.displayName)
                    .font(.title3.weight(.semibold))

                if let address = item.target.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Payout highlight
                HStack(spacing: 16) {
                    Label("$\(item.estimatedPayoutUsd)", systemImage: "dollarsign.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.successGreen)

                    Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Primary action
            VStack(spacing: 12) {
                if isOnSite {
                    Button {
                        Task {
                            do {
                                try await viewModel.checkIn(item.target)
                                await MainActor.run {
                                    reservedItem = item
                                    captureFlow.step = .readyToCapture
                                    captureFlow.captureManager.configureSession()
                                    captureFlow.captureManager.startSession()
                                    navigateToCapture = true
                                    showActions = false
                                }
                            } catch {
                                await MainActor.run {
                                    reserveMessage = "Couldn't start mapping. Please try again."
                                    showReserveConfirm = true
                                }
                            }
                        }
                    } label: {
                        Text("Start Mapping")
                    }
                    .buttonStyle(BlueprintSuccessButtonStyle())
                } else {
                    Button {
                        openDirections(to: item)
                        showActions = false
                    } label: {
                        Text("Get Directions")
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())

                    Text("You need to be at this location to start mapping")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Cancel reservation if active
                if isReservedByMe {
                    Button {
                        Task { await cancelActiveReservation() }
                        showActions = false
                    } label: {
                        Text("Cancel Reservation")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .presentationDetents([.height(340)])
        .alert("Info", isPresented: $showReserveConfirm, actions: {
            Button("OK", role: .cancel) { showReserveConfirm = false }
        }, message: {
            Text(reserveMessage ?? "")
        })
        .alert("Switch reservation?", isPresented: $showSwitchReservationConfirm, actions: {
            Button("Switch", role: .destructive) { confirmSwitchReservation() }
            Button("Cancel", role: .cancel) { showSwitchReservationConfirm = false }
        }, message: {
            Text("You can only have one reservation at a time. Switch to this location?")
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
