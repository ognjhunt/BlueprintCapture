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

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                FilterBar(radius: $viewModel.selectedRadius, limit: $viewModel.selectedLimit, sort: $viewModel.selectedSort)
                    .padding(.horizontal)
                    .padding(.top)

                if let reservation = activeReservation, let item = reservedItem, reservation.reservedUntil > now {
                    reservationBanner(item: item, reservation: reservation)
                        .padding(.horizontal)
                }

                content
            }
            .navigationTitle("Nearby Targets")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $navigateToCapture) {
                CaptureSessionView(viewModel: captureFlow)
            }
        }
        .task { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onReceive(countdownTimer) { date in
            now = date
            if let res = activeReservation, res.reservedUntil <= date {
                activeReservation = nil
                reservedItem = nil
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
                                reservationSecondsRemaining: secondsRemaining
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
                        let secondsRemaining: Int? = {
                            if let res = activeReservation, let reserved = reservedItem, reserved.id == item.id {
                                let secs = Int(res.reservedUntil.timeIntervalSince(now))
                                return max(0, secs)
                            }
                            return nil
                        }()
                        // Skip duplicate of pinned row in the main list
                        if reservedItem?.id == item.id { EmptyView() } else {
                            TargetRow(
                                item: item,
                                reservationSecondsRemaining: secondsRemaining
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                                showActions = true
                                if secondsRemaining != nil { showDirectionsPrompt = true }
                            }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refresh()
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
    @ViewBuilder func actionSheet(for item: NearbyTargetsViewModel.NearbyItem) -> some View {
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
                Button {
                    Task {
                        do {
                            let res = try await viewModel.reserveTarget(item.target)
                            reserveMessage = "This location is now reserved for you for 1 hour (until \(res.reservedUntil.formatted(date: .omitted, time: .shortened))). If you are not on-site and mapping within that hour, it will be un-reserved."
                            showReserveConfirm = true
                            activeReservation = res
                            reservedItem = item
                            if !viewModel.isOnSite(item.target) {
                                directionsItem = item
                                showDirectionsPrompt = true
                            }
                        } catch {
                            reserveMessage = "Unable to reserve right now. Please try again."
                            showReserveConfirm = true
                        }
                    }
                } label: {
                    Label("Reserve for 1 hour", systemImage: "clock.badge.checkmark")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                Button {
                    // If user is on site, go straight to capture flow
                    if viewModel.isOnSite(item.target) {
                        captureFlow.step = .readyToCapture
                        captureFlow.captureManager.configureSession()
                        captureFlow.captureManager.startSession()
                        navigateToCapture = true
                        showActions = false
                    } else {
                        reserveMessage = "You're not detected on-site yet. Head to the location, then tap Check in to begin mapping."
                        showReserveConfirm = true
                    }
                } label: {
                    Label("Check in & start mapping", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())

                if !viewModel.isOnSite(item.target) {
                    Button {
                        openDirections(to: item)
                    } label: {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                }

                // Show Cancel Reservation button if this item is currently reserved
                if let res = activeReservation, let reserved = reservedItem, reserved.id == item.id {
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
            Button("OK", role: .cancel) { showReserveConfirm = false; showActions = false }
        }, message: {
            Text(reserveMessage ?? "")
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
}
