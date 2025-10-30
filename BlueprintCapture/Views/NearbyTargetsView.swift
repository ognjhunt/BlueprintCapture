import SwiftUI
import Combine
import AVFoundation

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
    @AppStorage("NearbyTargetsWalkthroughCompleted") private var hasCompletedWalkthrough = false
    @State private var showWalkthrough = false
    @State private var didTriggerWalkthrough = false
    // Alert for reservation expiry while app is active
    @State private var showExpiryAlert = false
    @State private var expiryMessage: String?
    @State private var lastRefreshedAt: Date? = nil

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
                    metaBar()
                        .padding(.horizontal)

                    if let reservation = activeReservation, let item = reservedItem, reservation.reservedUntil > now {
                        reservationBanner(item: item, reservation: reservation)
                            .padding(.horizontal)
                    }

                    content
                }

                if showWalkthrough {
                    NearbyTargetsWalkthroughOverlay(
                        isPresented: $showWalkthrough,
                        sampleItem: viewModel.items.first,
                        currentAddress: viewModel.currentAddress,
                        onDismiss: {
                            hasCompletedWalkthrough = true
                        }
                    )
                    .transition(.opacity)
                    .zIndex(1)
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
                if !hasCompletedWalkthrough && !didTriggerWalkthrough {
                    didTriggerWalkthrough = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
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

// MARK: - Nearby Walkthrough Overlay

private struct NearbyTargetsWalkthroughOverlay: View {
    @Binding var isPresented: Bool
    let sampleItem: NearbyTargetsViewModel.NearbyItem?
    let currentAddress: String?
    let onDismiss: () -> Void

    @State private var currentPage = 0
    @StateObject private var cameraController = WalkthroughCameraController()
    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
    @State private var cameraUnavailable = false
    @State private var didTriggerDismiss = false

    private var steps: [Step] { Step.all }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                TabView(selection: $currentPage) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        WalkthroughStepPage(
                            step: step,
                            sampleItem: sampleItem,
                            currentAddress: currentAddress,
                            size: geometry.size,
                            safeArea: geometry.safeAreaInsets,
                            cameraController: cameraController,
                            cameraAuthorized: cameraAuthorized,
                            cameraDenied: cameraDenied,
                            cameraUnavailable: cameraUnavailable,
                            selection: $currentPage,
                            index: index,
                            totalSteps: steps.count,
                            onFinish: dismiss
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                Button(action: dismiss) {
                    HStack(spacing: 6) {
                        Text("Skip tour")
                            .font(.callout.weight(.semibold))
                        Image(systemName: "xmark.circle.fill")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                }
                .padding(.top, geometry.safeAreaInsets.top + 16)
                .padding(.trailing, 20)
            }
        }
        .onAppear { updateCamera(for: currentPage) }
        .onChange(of: currentPage) { _, newValue in updateCamera(for: newValue) }
        .onDisappear { cameraController.stop() }
    }

    private func dismiss() {
        guard !didTriggerDismiss else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isPresented = false
            }
            return
        }
        didTriggerDismiss = true
        cameraController.stop()
        onDismiss()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isPresented = false
        }
    }

    private func updateCamera(for index: Int) {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        if step.usesCameraBackground {
            ensureCameraSession()
        } else {
            cameraController.stop()
        }
    }

    private func ensureCameraSession() {
#if targetEnvironment(simulator)
        cameraUnavailable = true
        cameraAuthorized = false
        cameraDenied = false
        return
#else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            do {
                try cameraController.prepareSession()
                cameraUnavailable = false
                cameraController.start()
            } catch {
                cameraUnavailable = true
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    cameraDenied = !granted
                    if granted {
                        do {
                            try cameraController.prepareSession()
                            cameraUnavailable = false
                            cameraController.start()
                        } catch {
                            cameraUnavailable = true
                        }
                    }
                }
            }
        default:
            cameraAuthorized = false
            cameraDenied = true
            cameraUnavailable = false
            cameraController.stop()
        }
#endif
    }

    private struct Step: Identifiable {
        enum Highlight {
            case none
            case addressChip
            case filterBar
            case targetList
            case bottomTabs
        }

        enum Kind {
            case targets
            case filters
            case search
            case reserve
            case checkIn
            case captureQuality
            case payout
        }

        let id: Int
        let icon: String
        let title: String
        let message: String
        let highlight: Highlight
        let usesCameraBackground: Bool
        let kind: Kind
        let accent: Color

        static let all: [Step] = [
            Step(
                id: 0,
                icon: "mappin.circle.fill",
                title: "Spot your next target",
                message: "Your Nearby list shows real locations ready to map.",
                highlight: .targetList,
                usesCameraBackground: false,
                kind: .targets,
                accent: BlueprintTheme.brandTeal
            ),
            Step(
                id: 1,
                icon: "slider.horizontal.3",
                title: "Fine-tune with filters",
                message: "Prioritize distance, payout, or demand with quick toggles.",
                highlight: .filterBar,
                usesCameraBackground: false,
                kind: .filters,
                accent: BlueprintTheme.primary
            ),
            Step(
                id: 2,
                icon: "magnifyingglass",
                title: "Search other areas",
                message: "Jump to cities or stores you plan to visit soon.",
                highlight: .addressChip,
                usesCameraBackground: false,
                kind: .search,
                accent: BlueprintTheme.accentAqua
            ),
            Step(
                id: 3,
                icon: "clock.badge.checkmark",
                title: "Reserve when you're en route",
                message: "Hold a target for up to an hour if you’re heading there next.",
                highlight: .targetList,
                usesCameraBackground: false,
                kind: .reserve,
                accent: BlueprintTheme.primaryDeep
            ),
            Step(
                id: 4,
                icon: "mappin.and.ellipse",
                title: "Check in & start mapping",
                message: "Kick off your scan the moment you arrive on-site.",
                highlight: .targetList,
                usesCameraBackground: false,
                kind: .checkIn,
                accent: BlueprintTheme.successGreen
            ),
            Step(
                id: 5,
                icon: "camera.viewfinder",
                title: "Capture with care",
                message: "Use your rear camera (or connected glasses) for a smooth walkthrough.",
                highlight: .none,
                usesCameraBackground: true,
                kind: .captureQuality,
                accent: BlueprintTheme.brandTeal
            ),
            Step(
                id: 6,
                icon: "dollarsign.circle.fill",
                title: "Earn after review",
                message: "Quality scans get paid quickly after we verify them.",
                highlight: .bottomTabs,
                usesCameraBackground: false,
                kind: .payout,
                accent: BlueprintTheme.payoutTeal
            )
        ]
    }

    private static let payoutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct WalkthroughStepPage: View {
    let step: NearbyTargetsWalkthroughOverlay.Step
    let sampleItem: NearbyTargetsViewModel.NearbyItem?
    let currentAddress: String?
    let size: CGSize
    let safeArea: EdgeInsets
    @ObservedObject var cameraController: WalkthroughCameraController
    let cameraAuthorized: Bool
    let cameraDenied: Bool
    let cameraUnavailable: Bool
    @Binding var selection: Int
    let index: Int
    let totalSteps: Int
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            background

            if let rect = highlightRect(for: step.highlight) {
                WalkthroughHighlightView(rect: rect)
            }

            VStack {
                Spacer()
                VStack(spacing: 18) {
                    WalkthroughInfoCard(
                        step: step,
                        sampleItem: sampleItem,
                        currentAddress: currentAddress,
                        cameraDenied: cameraDenied,
                        cameraUnavailable: cameraUnavailable
                    )

                    WalkthroughPageIndicator(currentIndex: selection, total: totalSteps)

                    VStack(alignment: .leading, spacing: 12) {
                        if index > 0 {
                            Button(action: goBack) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                        .fontWeight(.semibold)
                                }
                                .font(.callout)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: advance) {
                            Text(index == totalSteps - 1 ? "I'm ready to map" : "Next")
                        }
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, safeArea.bottom + 24)
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        Group {
            if step.usesCameraBackground {
                if cameraAuthorized && !cameraUnavailable {
                    WalkthroughCameraPreview(session: cameraController.session)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                } else {
                    LinearGradient(
                        colors: [BlueprintTheme.primaryDeep.opacity(0.9), BlueprintTheme.primary.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
            } else {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step.usesCameraBackground)
    }

    private func highlightRect(for highlight: NearbyTargetsWalkthroughOverlay.Step.Highlight) -> CGRect? {
        switch highlight {
        case .none:
            return nil
        case .addressChip:
            let width = max(0, size.width - 32)
            let height: CGFloat = 76
            let y = safeArea.top + 70
            return CGRect(x: 16, y: y, width: width, height: height)
        case .filterBar:
            let width = max(0, size.width - 32)
            let height: CGFloat = 120
            let y = safeArea.top + 160
            return CGRect(x: 16, y: y, width: width, height: height)
        case .targetList:
            let width = max(0, size.width - 32)
            let top = safeArea.top + 260
            let bottomPadding = safeArea.bottom + 220
            let rawHeight = size.height - top - bottomPadding
            let height = max(220, min(rawHeight, size.height - top - safeArea.bottom - 100))
            return CGRect(x: 16, y: top, width: width, height: height)
        case .bottomTabs:
            let width = max(180, size.width - 120)
            let height: CGFloat = 110
            let x = (size.width - width) / 2
            let y = size.height - safeArea.bottom - height - 36
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private func goBack() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            selection = max(0, index - 1)
        }
    }

    private func advance() {
        if index == totalSteps - 1 {
            onFinish()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                selection = min(totalSteps - 1, index + 1)
            }
        }
    }
}

private struct WalkthroughHighlightView: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color.white.opacity(0.9), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: Color.white.opacity(0.22), radius: 18)
            .blendMode(.screen)
            .transition(.opacity)
    }
}

private struct WalkthroughInfoCard: View {
    let step: NearbyTargetsWalkthroughOverlay.Step
    let sampleItem: NearbyTargetsViewModel.NearbyItem?
    let currentAddress: String?
    let cameraDenied: Bool
    let cameraUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: step.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(step.accent)
                    .frame(width: 52, height: 52)
                    .background(step.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.title3).fontWeight(.bold)
                    Text(step.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(bulletPoints, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(step.accent)
                            .padding(.top, 2)
                        Text(bullet)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var bulletPoints: [String] {
        switch step.kind {
        case .targets:
            var lines: [String] = [
                "See the nearby locations we've highlighted for you to map."
            ]
            if let item = sampleItem {
                let payout = NearbyTargetsWalkthroughOverlay.payoutFormatter.string(from: NSNumber(value: item.estimatedPayoutUsd)) ?? "$\(item.estimatedPayoutUsd)"
                let duration = formatDuration(estimatedScanTimeMinutes(for: item.target))
                let distance = String(format: "%.1f", item.distanceMiles)
                lines.append("\(item.target.displayName) · \(distance) mi · \(duration) · est. \(payout)")
            } else if let address = currentAddress {
                lines.append("We're finding top targets around \(address).")
            }
            lines.append("Each card shows the address, scan time, and estimated payout.")
            return lines
        case .filters:
            return [
                "Use the radius chips (0.5–10 mi) to match how far you’ll travel.",
                "Tap Highest payout, Nearest, or Highest demand to reorder the list instantly."
            ]
        case .search:
            var lines: [String] = []
            if let address = currentAddress {
                lines.append("You're currently browsing around \(address).")
            }
            lines.append("Tap the address bar to look up another city, neighborhood, or store.")
            lines.append("Plan trips ahead and line up earning opportunities before you arrive.")
            return lines
        case .reserve:
            return [
                "Open a target and tap Reserve to hold it just for you for up to one hour.",
                "Reservations are optional—save them for when you’re on the way." 
            ]
        case .checkIn:
            return [
                "Once you're on-site, tap Check in & start mapping to launch the capture flow.",
                "We'll walk you through connecting glasses (if any) and open the camera right away."
            ]
        case .captureQuality:
            var lines: [String] = [
                "Walk slowly and let the camera see every aisle, wall, and corner.",
                "Go down and back each aisle so the whole space is captured—quality beats speed."
            ]
            if cameraDenied {
                lines.append("Enable camera access in Settings to record your walkthroughs.")
            } else if cameraUnavailable {
                lines.append("Camera preview unavailable here—use your rear camera during real captures.")
            }
            return lines
        case .payout:
            return [
                "We review your video and typically pay out within 2–3 days.",
                "Final payout depends on quality, demand for the space, and square footage.",
                "Repeated low-quality scans can pause your access—we’ll warn you well before that happens."
            ]
        }
    }
}

private struct WalkthroughPageIndicator: View {
    let currentIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == currentIndex ? 28 : 10, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
    }
}

private final class WalkthroughCameraController: ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.blueprint.walkthrough.camera")
    private var isConfigured = false

    enum ConfigurationError: Error {
        case unavailable
    }

    func prepareSession() throws {
        var capturedError: Error?
        queue.sync {
            if !self.isConfigured {
#if targetEnvironment(simulator)
                capturedError = ConfigurationError.unavailable
#else
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    capturedError = error
                }
#endif
            }
        }
        if let error = capturedError { throw error }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw ConfigurationError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }

    func start() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

private struct WalkthroughCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> WalkthroughPreviewView {
        let view = WalkthroughPreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: WalkthroughPreviewView, context: Context) {}
}

private final class WalkthroughPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}
