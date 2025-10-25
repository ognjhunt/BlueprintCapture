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
    @AppStorage("NearbyTargetsAddressHintShown") private var addressHintShown: Bool = false
    @State private var showChipHint = false
    // Alert for reservation expiry while app is active
    @State private var showExpiryAlert = false
    @State private var expiryMessage: String?
    @State private var lastRefreshedAt: Date? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                currentAddressChip()
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .onTapGesture { showAddressSheet = true }
                FilterBar(radius: $viewModel.selectedRadius, limit: $viewModel.selectedLimit, sort: $viewModel.selectedSort)
                    .padding(.horizontal)
                    .padding(.top, 0)
                metaBar()
                    .padding(.horizontal)

                if let reservation = activeReservation, let item = reservedItem, reservation.reservedUntil > now {
                    reservationBanner(item: item, reservation: reservation)
                        .padding(.horizontal)
                }

                content
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
            .onAppear {
                if !addressHintShown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showChipHint = true
                        addressHintShown = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showChipHint = false
                        }
                    }
                }
            }
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
                .popover(isPresented: $showChipHint) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tip")
                            .font(.caption).fontWeight(.semibold)
                        Text("Tap here to change the area you're searching")
                            .font(.footnote)
                        Button("Got it") { showChipHint = false }
                            .font(.caption)
                    }
                    .padding(12)
                }
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
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search another address", text: $addressQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: addressQuery) { _, newVal in
                            Task { await viewModel.searchAddresses(query: newVal) }
                        }
                }
                .padding(.horizontal)

                if viewModel.isSearchingAddress {
                    ProgressView("Searching…")
                        .padding(.top, 8)
                }

                if !viewModel.addressSearchResults.isEmpty {
                    List(viewModel.addressSearchResults) { result in
                        Button {
                            viewModel.setCustomSearchCenter(coordinate: result.coordinate, address: result.formatted)
                            addressQuery = ""
                            showAddressSheet = false
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: result.isEstablishment ? "building.2.fill" : "mappin.circle.fill")
                                    .foregroundStyle(result.isEstablishment ? BlueprintTheme.brandTeal : .secondary)
                                    .font(.title3)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                } else if addressQuery.count >= 3 && !viewModel.isSearchingAddress {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if addressQuery.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(BlueprintTheme.brandTeal.opacity(0.5))
                        VStack(spacing: 6) {
                            Text("Search for a location")
                                .font(.headline)
                            Text("Enter a store name or street address")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }

                if viewModel.isUsingCustomSearchCenter {
                    Button {
                        viewModel.clearCustomSearchCenter()
                        addressQuery = ""
                        showAddressSheet = false
                    } label: {
                        Label("Use my current location", systemImage: "location.fill")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Search location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAddressSheet = false }
                }
            }
        }
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
            reserveMessage = "This location is now reserved for you for 1 hour (until \(res.reservedUntil.formatted(date: .omitted, time: .shortened))). If you are not on-site and mapping within that hour, it will be un-reserved."
            keepActionsOpenAfterAlert = false
            showReserveConfirm = true
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
