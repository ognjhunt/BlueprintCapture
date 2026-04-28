import Foundation
import CoreLocation
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class UITestLocationService: LocationServiceProtocol {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var latestLocation: CLLocation?

    private var listener: ((CLLocation?) -> Void)?

    init(location: CLLocation) {
        self.latestLocation = location
    }

    func requestWhenInUseAuthorization() {
        listener?(latestLocation)
    }

    func requestCurrentLocation() {
        listener?(latestLocation)
    }

    func startUpdatingLocation() {
        listener?(latestLocation)
    }

    func stopUpdatingLocation() {}

    func setListener(_ listener: @escaping (CLLocation?) -> Void) {
        self.listener = listener
        listener(latestLocation)
    }
}

@MainActor
final class UITestJobsRepository: JobsRepositoryProtocol {
    func fetchActiveJobs(limit: Int) async throws -> [ScanJob] {
        Array(UITestFixtures.jobs.prefix(limit))
    }
}

@MainActor
final class UITestTargetStateService: TargetStateServiceProtocol {
    private var states: [String: TargetState]

    init(states: [String: TargetState] = [:]) {
        self.states = states
    }

    func batchFetchStates(for targetIds: [String]) async -> [String : TargetState] {
        states.filter { targetIds.contains($0.key) }
    }

    func observeState(for targetId: String, onChange: @escaping (TargetState?) -> Void) -> TargetStateObservation {
        onChange(states[targetId])
        return TargetStateObservation {}
    }

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let until = Date().addingTimeInterval(duration)
        states[target.id] = TargetState(
            status: .reserved,
            reservedBy: UserDeviceService.resolvedUserId(),
            reservedUntil: until,
            checkedInBy: nil,
            completedAt: nil,
            lat: target.lat,
            lng: target.lng,
            geohash: nil,
            updatedAt: Date()
        )
        return Reservation(targetId: target.id, reservedUntil: until)
    }

    func cancelReservation(for targetId: String) async {
        states[targetId] = nil
    }

    func checkIn(targetId: String) async throws {
        guard let existing = states[targetId] else { return }
        states[targetId] = TargetState(
            status: .in_progress,
            reservedBy: existing.reservedBy,
            reservedUntil: existing.reservedUntil,
            checkedInBy: UserDeviceService.resolvedUserId(),
            completedAt: nil,
            lat: existing.lat,
            lng: existing.lng,
            geohash: existing.geohash,
            updatedAt: Date()
        )
    }

    func complete(targetId: String) async throws {
        guard let existing = states[targetId] else { return }
        states[targetId] = TargetState(
            status: .completed,
            reservedBy: existing.reservedBy,
            reservedUntil: existing.reservedUntil,
            checkedInBy: existing.checkedInBy,
            completedAt: Date(),
            lat: existing.lat,
            lng: existing.lng,
            geohash: existing.geohash,
            updatedAt: Date()
        )
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? {
        guard let match = states.first(where: { _, state in
            state.status == .reserved && state.reservedBy == UserDeviceService.resolvedUserId()
        }) else {
            return nil
        }
        return Reservation(targetId: match.key, reservedUntil: match.value.reservedUntil ?? Date().addingTimeInterval(600))
    }
}

@MainActor
final class UITestCaptureHistoryService: CaptureHistoryServiceProtocol {
    func fetchCaptureHistory() async throws -> [CaptureHistoryEntry] {
        UITestFixtures.captureHistory
    }
}

@MainActor
final class UITestCaptureUploadService: CaptureUploadServiceProtocol {
    private let subject = PassthroughSubject<CaptureUploadService.Event, Never>()

    var events: AnyPublisher<CaptureUploadService.Event, Never> {
        subject.eraseToAnyPublisher()
    }

    func enqueue(_ request: CaptureUploadRequest) {
        subject.send(.queued(request))
    }

    func retryUpload(id: UUID) {}
    func cancelUpload(id: UUID) {}
}

@MainActor
enum UITestFixtures {
    static let location = CLLocation(latitude: 37.7765, longitude: -122.3940)

    static let jobs: [ScanJob] = [
        ScanJob(
            id: "ui_test_job_approved",
            title: "Warehouse Dock A",
            address: "1 Warehouse Way, San Francisco, CA",
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            payoutCents: 4500,
            estMinutes: 25,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: "Warehouse",
            instructions: ["Walk all aisles", "Include entry/exit", "Avoid faces"],
            allowedAreas: ["Main floor"],
            restrictedAreas: ["Offices"],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 1,
            priorityWeight: 1.25,
            regionId: "bay-area",
            jobType: .buyerRequestedSpecialTask,
            buyerRequestId: "req-ui-approved",
            siteSubmissionId: "submission-ui-approved",
            quotedPayoutCents: 4500,
            dueWindow: "managed",
            approvalRequirements: ["ops_review"],
            recaptureReason: nil,
            rightsChecklist: ["Stay in approved areas only"],
            rightsProfile: "documented_permission",
            requestedOutputs: ["qualification"],
            workflowName: "Dock walkthrough",
            workflowSteps: ["Entry", "Dock lane", "Exit"],
            targetKPI: "coverage",
            zone: "dock_a",
            shift: "day",
            owner: "warehouse_supervisor",
            facilityTemplate: "warehouse",
            benchmarkStations: ["Entry"],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        ),
        ScanJob(
            id: "ui_test_job_review",
            title: "Retail Backroom B",
            address: "200 Market St, San Francisco, CA",
            lat: 37.7935,
            lng: -122.3966,
            payoutCents: 3000,
            estMinutes: 20,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: "Retail",
            instructions: ["Capture stock areas"],
            allowedAreas: [],
            restrictedAreas: ["Registers"],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: "bay-area",
            jobType: .operatorApprovedOnDemand,
            buyerRequestId: nil,
            siteSubmissionId: "submission-ui-review",
            quotedPayoutCents: 3000,
            dueWindow: nil,
            approvalRequirements: ["review_required"],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: "review_required",
            requestedOutputs: ["qualification", "review_intake"],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )
    ]

    static let captureHistory: [CaptureHistoryEntry] = [
        CaptureHistoryEntry(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            targetAddress: "1 Warehouse Way, San Francisco, CA",
            capturedAt: Date().addingTimeInterval(-86_400),
            status: .approved,
            estimatedPayoutCents: 4500,
            thumbnailURL: nil
        ),
        CaptureHistoryEntry(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            targetAddress: "200 Market St, San Francisco, CA",
            capturedAt: Date().addingTimeInterval(-43_200),
            status: .submitted,
            estimatedPayoutCents: 3000,
            thumbnailURL: nil
        )
    ]

    static func makeScanHomeViewModel(alertsManager: NearbyAlertsManager) -> ScanHomeViewModel {
        return MainActor.run {
            ScanHomeViewModel(
                jobsRepository: UITestJobsRepository(),
                targetStateService: UITestTargetStateService(),
                locationService: UITestLocationService(location: location),
                alertsManager: alertsManager,
                captureHistoryService: UITestCaptureHistoryService()
            )
        }
    }

    static func makeUploadQueueViewModel() -> UploadQueueViewModel {
        return MainActor.run {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("blueprint-ui-test-upload-queue.json")
            try? FileManager.default.removeItem(at: tempURL)
            return UploadQueueViewModel(
                uploadService: UITestCaptureUploadService(),
                targetStateService: UITestTargetStateService(),
                store: UploadQueueStore(fileURL: tempURL)
            )
        }
    }

    static func makeWalletViewModel() -> WalletViewModel {
        return MainActor.run {
            let model = WalletViewModel()
            model.isAuthenticated = true
            model.totalEarnings = Decimal(125)
            model.pendingPayout = Decimal(30)
            model.scansCompleted = 4
            model.captureHistory = captureHistory
            model.payoutLedger = []
            model.qcStatus = nil
            model.billingInfo = nil
            model.stripeAccountState = nil
            model.isLoading = false
            model.errorMessage = nil
            return model
        }
    }
}

struct UITestRootView: View {
    @StateObject private var glassesManager: GlassesCaptureManager
    @StateObject private var uploadQueue: UploadQueueViewModel
    @StateObject private var alertsManager: NearbyAlertsManager

    private let scenario: RuntimeConfig.UITestScenario
    private let scanHomeViewModel: ScanHomeViewModel
    private let walletViewModel: WalletViewModel

    @MainActor
    init(scenario: RuntimeConfig.UITestScenario? = nil) {
        let resolvedScenario = scenario ?? RuntimeConfig.current.uiTestScenario
        let alertsManager = NearbyAlertsManager()
        _glassesManager = StateObject(wrappedValue: GlassesCaptureManager())
        _uploadQueue = StateObject(wrappedValue: UITestFixtures.makeUploadQueueViewModel())
        _alertsManager = StateObject(wrappedValue: alertsManager)
        self.scenario = resolvedScenario
        self.scanHomeViewModel = UITestFixtures.makeScanHomeViewModel(alertsManager: alertsManager)
        self.walletViewModel = UITestFixtures.makeWalletViewModel()
    }

    var body: some View {
        Group {
            switch scenario {
            case .onboarding:
                UITestOnboardingView()
            case .wallet:
                MainTabView(
                    glassesManager: glassesManager,
                    uploadQueue: uploadQueue,
                    alertsManager: alertsManager,
                    initialSelectedTab: 1,
                    scanHomeViewModel: scanHomeViewModel,
                    walletViewModel: walletViewModel,
                    walletShouldAutoload: false
                )
            case .corePath, .disabled:
                MainTabView(
                    glassesManager: glassesManager,
                    uploadQueue: uploadQueue,
                    alertsManager: alertsManager,
                    initialSelectedTab: 0,
                    scanHomeViewModel: scanHomeViewModel,
                    walletViewModel: walletViewModel,
                    walletShouldAutoload: false
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UserDeviceService.ensureTemporaryUser()
        }
    }
}

private struct UITestOnboardingView: View {
    @State private var step: Step = .welcome
    @State private var email: String = ""

    private enum Step {
        case welcome
        case auth
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch step {
            case .welcome:
                VStack {
                    Spacer()
                    Button("Get Started") {
                        step = .auth
                    }
                    .accessibilityIdentifier("onboarding-get-started")
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            case .auth:
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        Button("Skip for now") {}
                    }

                    Text("Create your account")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Button("Continue with Google") {}
                        .accessibilityIdentifier("auth-google")

                    HStack(spacing: 8) {
                        Button("Create Account") {}
                            .accessibilityIdentifier("auth-create-account")
                        Button("Sign In") {}
                            .accessibilityIdentifier("auth-sign-in")
                    }

                    TextField("you@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("auth-email")
                        .textFieldStyle(.roundedBorder)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }
}
