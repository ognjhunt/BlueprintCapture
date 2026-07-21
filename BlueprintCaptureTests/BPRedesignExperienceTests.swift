import XCTest
@testable import BlueprintCapture

// MARK: - BP redesign experience logic
//
// Pure-logic coverage for the shipping BP experience: onboarding step machine,
// capturer setup persistence, status presentation truth, identity derivation,
// and the honest activity-feed mapping.

final class BPOnboardingStateMachineTests: XCTestCase {
    func testAdvancesThroughAllStepsInOrderThenFinishes() {
        var machine = BPOnboardingStateMachine()
        XCTAssertEqual(machine.step, .welcome)
        XCTAssertTrue(machine.isFirst)
        XCTAssertEqual(machine.count, 5)

        XCTAssertTrue(machine.advance())
        XCTAssertEqual(machine.step, .city)
        XCTAssertTrue(machine.advance())
        XCTAssertEqual(machine.step, .permissions)
        XCTAssertTrue(machine.advance())
        XCTAssertEqual(machine.step, .rights)
        XCTAssertTrue(machine.advance())
        XCTAssertEqual(machine.step, .payouts)
        XCTAssertTrue(machine.isLast)

        // Advancing past the last step reports completion.
        XCTAssertFalse(machine.advance())
        XCTAssertEqual(machine.step, .payouts)
    }

    func testGoBackStopsAtFirstStep() {
        var machine = BPOnboardingStateMachine()
        XCTAssertFalse(machine.goBack())
        machine.advance()
        machine.advance()
        XCTAssertTrue(machine.goBack())
        XCTAssertEqual(machine.step, .city)
        XCTAssertTrue(machine.goBack())
        XCTAssertEqual(machine.step, .welcome)
        XCTAssertFalse(machine.goBack())
    }

    func testIndexTracksRawStepOrder() {
        var machine = BPOnboardingStateMachine()
        for expected in 0..<machine.count {
            XCTAssertEqual(machine.index, expected)
            machine.advance()
        }
    }
}

final class BPCapturerStateStoreTests: XCTestCase {
    private func makeStore() -> (BPCapturerStateStore, UserDefaults) {
        let suiteName = "bp-capturer-state-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (BPCapturerStateStore(defaults: defaults), defaults)
    }

    func testOnboardingCompletionPersists() {
        let (store, defaults) = makeStore()
        XCTAssertFalse(store.hasCompletedOnboarding)

        store.completeOnboarding()
        XCTAssertTrue(store.hasCompletedOnboarding)

        // A fresh store over the same defaults sees the persisted value.
        let reloaded = BPCapturerStateStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testRightsCertificationExpiresAfterAYear() {
        let (store, _) = makeStore()
        XCTAssertFalse(store.isRightsCertified)

        store.certifyRights()
        XCTAssertTrue(store.isRightsCertified)

        let expired = Date().addingTimeInterval(-366 * 24 * 3600)
        store.certifyRights(at: expired)
        XCTAssertFalse(store.isRightsCertified, "Certification older than a year must not count")

        let recent = Date().addingTimeInterval(-30 * 24 * 3600)
        store.certifyRights(at: recent)
        XCTAssertTrue(store.isRightsCertified)
    }

    func testResetClearsEverything() {
        let (store, _) = makeStore()
        store.completeOnboarding()
        store.certifyRights()
        store.reset()
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertFalse(store.isRightsCertified)
    }

    func testOwnerBindingResetsStateForADifferentAccount() {
        let (store, _) = makeStore()
        store.bindOwner(uid: "uid-alice")
        store.completeOnboarding()
        store.certifyRights()

        // Same account re-binding (fresh launch, re-login) keeps state.
        store.bindOwner(uid: "uid-alice")
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertTrue(store.isRightsCertified)

        // Signed-out (nil) keeps state for the returning capturer.
        store.bindOwner(uid: nil)
        XCTAssertTrue(store.hasCompletedOnboarding)

        // A DIFFERENT account on the same device must start fresh — the
        // previous user's onboarding/rights state cannot carry over.
        store.bindOwner(uid: "uid-bob")
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertFalse(store.isRightsCertified)
    }
}

final class BPStatusPresentationTests: XCTestCase {
    func testCaptureLifecycleSignalsStayHonest() {
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.approved).signal, .proof)
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.approved).label, "Accepted")
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.paid).signal, .proof)
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.underReview).signal, .info)
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.needsRecapture).signal, .caution)
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.needsFix).signal, .caution)
        XCTAssertEqual(BPStatusPresentation.entry(for: CaptureStatus.rejected).signal, .blocker)
    }

    func testEveryCaptureStatusHasLabelAndExplanation() {
        for status in CaptureStatus.allCases {
            let entry = BPStatusPresentation.entry(for: status)
            XCTAssertFalse(entry.label.isEmpty, "\(status) needs a label")
            XCTAssertFalse(entry.explanation.isEmpty, "\(status) needs an explanation")
        }
    }

    func testGlossaryCoversLifecycleAndExceptionStates() {
        let order = BPStatusPresentation.glossaryOrder
        XCTAssertTrue(order.contains(.approved))
        XCTAssertTrue(order.contains(.needsRecapture))
        XCTAssertTrue(order.contains(.rejected))
        XCTAssertTrue(order.contains(.paid))
        XCTAssertEqual(order.count, Set(order).count, "Glossary entries must be unique")
    }

    func testPayoutLedgerSignals() {
        XCTAssertEqual(BPStatusPresentation.entry(for: PayoutLedgerStatus.paid).signal, .proof)
        XCTAssertEqual(BPStatusPresentation.entry(for: PayoutLedgerStatus.inTransit).signal, .info)
        XCTAssertEqual(BPStatusPresentation.entry(for: PayoutLedgerStatus.failed).signal, .blocker)
        XCTAssertEqual(BPStatusPresentation.entry(for: PayoutLedgerStatus.pending).signal, .neutral)
    }

    func testUploadStateShowsProgressPercent() {
        let entry = BPStatusPresentation.entry(for: UploadQueueViewModel.UploadStatus.State.uploading(progress: 0.42))
        XCTAssertEqual(entry.label, "Uploading 42%")
        XCTAssertEqual(entry.signal, .info)

        let failed = BPStatusPresentation.entry(for: UploadQueueViewModel.UploadStatus.State.failed(message: "x"))
        XCTAssertEqual(failed.signal, .blocker)
    }
}

@MainActor
final class BPIdentityDerivationTests: XCTestCase {
    func testFirstNameExtraction() {
        XCTAssertEqual(RedesignCoordinator.firstName(from: "Maya Chen"), "Maya")
        XCTAssertEqual(RedesignCoordinator.firstName(from: "Prince"), "Prince")
        XCTAssertEqual(RedesignCoordinator.firstName(from: "Ana Sofia Ruiz Vega"), "Ana")
    }

    func testCapturerReferenceUsesUppercasedUidSuffix() {
        XCTAssertEqual(RedesignCoordinator.reference(fromUserId: "abcd1234wxyz"), "CAPTURER · WXYZ")
        XCTAssertEqual(RedesignCoordinator.reference(fromUserId: ""), "")
    }
}

@MainActor
final class BPActivityMappingTests: XCTestCase {
    func testCaptureHistoryEventCarriesStatusTruth() {
        let entry = CaptureHistoryEntry(
            id: UUID(),
            targetAddress: "12 Dock Rd",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .needsRecapture,
            estimatedPayoutCents: 4800,
            thumbnailURL: nil
        )
        let event = BPActivityModel.event(for: entry)
        XCTAssertTrue(event.title.contains("Recapture"))
        XCTAssertTrue(event.title.contains("12 Dock Rd"))
        XCTAssertEqual(event.signal, .caution)
        XCTAssertEqual(event.date, entry.capturedAt)
    }

    func testPayoutEventFormatsAmount() {
        let entry = PayoutLedgerEntry(
            id: UUID(),
            scheduledFor: Date(),
            amountCents: 12550,
            status: .paid,
            description: nil
        )
        let event = BPActivityModel.event(for: entry)
        XCTAssertTrue(event.title.contains("$125.50"))
        XCTAssertEqual(event.signal, .proof)
    }
}
