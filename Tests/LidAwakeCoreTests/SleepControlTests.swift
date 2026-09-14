import XCTest
@testable import LidAwakeCore

final class FakePower: PowerSettings {
    var awake = false
    var readError: Error?
    var writeError: Error?
    var permissionError: Error?
    var writes = [Bool]()
    var beforeWrite: ((Bool) -> Void)?
    func read() throws -> Bool { if let error = readError { throw error }; return awake }
    func requireAutomaticControl() throws { if let error = permissionError { throw error } }
    func write(_ value: Bool) throws {
        beforeWrite?(value)
        writes.append(value)
        if let error = writeError { throw error }
        awake = value
    }
}
final class MemoryJournal: RecoveryJournal {
    var pending = false
    var failure: Error?
    func load() throws -> Bool { pending }
    func save(_ value: Bool) throws { if let error = failure { throw error }; pending = value }
}
final class FakeSleep: SleepControlling {
    var awake = false
    var writes = [Bool]()
    var failure: Error?
    func isAwake() throws -> Bool { awake }
    func setAwake(_ value: Bool) throws {
        if let failure = failure { throw failure }
        awake = value
        writes.append(value)
    }
    func stop() throws { try setAwake(false) }
}

final class SleepControlTests: XCTestCase {
    func testQuitRestoresOwnedOverride() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        power.beforeWrite = { if $0 { XCTAssertTrue(journal.pending) } }
        try session.setAwake(true)
        XCTAssertTrue(power.awake)
        try session.stop()
        XCTAssertFalse(power.awake)
        XCTAssertFalse(journal.pending)
        XCTAssertEqual(power.writes, [true, false])
    }

    func testQuitDoesNotClearAnOverrideItNeverOwned() throws {
        let power = FakePower()
        power.awake = true
        try SleepSession(settings: power, journal: MemoryJournal()).stop()
        XCTAssertTrue(power.awake)
        XCTAssertTrue(power.writes.isEmpty)
    }

    func testFailedRestoreKeepsJournalAndCanBeRetried() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        try session.setAwake(true)
        power.writeError = ControlError.message("permission revoked")
        XCTAssertThrowsError(try session.stop())
        XCTAssertTrue(journal.pending)
        power.writeError = nil
        try session.stop()
        XCTAssertFalse(journal.pending)
        XCTAssertFalse(power.awake)
    }

    func testRelaunchRecoversBeforeEnablingAgain() throws {
        let power = FakePower(), journal = MemoryJournal()
        power.awake = true
        journal.pending = true
        let session = try SleepSession(settings: power, journal: journal)
        try session.setAwake(true)
        XCTAssertEqual(power.writes, [false, true])
        XCTAssertTrue(journal.pending)
    }

    func testFailedEnableStillLeavesRecoveryObligation() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        power.beforeWrite = { value in power.awake = value }
        power.writeError = ControlError.message("verification failed after write")
        XCTAssertThrowsError(try session.setAwake(true))
        XCTAssertTrue(journal.pending)
        power.writeError = nil
        try session.stop()
        XCTAssertFalse(power.awake)
    }

    func testCannotEnableWithoutDurableRecoveryOrPermission() throws {
        for failure in ["journal", "permission"] {
            let power = FakePower(), journal = MemoryJournal()
            if failure == "journal" { journal.failure = ControlError.message("disk full") }
            else { power.permissionError = ControlError.message("setup missing") }
            let session = try SleepSession(settings: power, journal: journal)
            XCTAssertThrowsError(try session.setAwake(true))
            XCTAssertTrue(power.writes.isEmpty)
            XCTAssertFalse(journal.pending)
        }
    }

    func testUnknownStatusNeverBecomesSleepEnabled() throws {
        let power = FakePower()
        power.readError = ControlError.message("pmset failed")
        let session = try SleepSession(settings: power, journal: MemoryJournal())
        XCTAssertThrowsError(try session.isAwake())
        XCTAssertThrowsError(try session.setAwake(false))
        XCTAssertTrue(power.writes.isEmpty)
    }

    func testRedundantReconciliationDoesNotWritePowerSettings() throws {
        let power = FakePower()
        let session = try SleepSession(settings: power, journal: MemoryJournal())
        try session.setAwake(false)
        try session.setAwake(true)
        try session.setAwake(true)
        XCTAssertEqual(power.writes, [true])
    }

    func testCanceledOrFailedToggleDoesNotPersistPreference() throws {
        for error in [ControlError.canceled, .message("sudo failed")] {
            let sleep = FakeSleep()
            sleep.failure = error
            var saved = [SleepPolicy]()
            let controller = PolicyController(policy: SleepPolicy(), sleep: sleep, onACPower: { true }, persist: { saved.append($0) })
            XCTAssertThrowsError(try controller.toggle(onAC: true))
            XCTAssertFalse(controller.policy.onAC)
            XCTAssertTrue(saved.isEmpty)
        }
    }

    func testUnplugAndReplugApplyIndependentPolicies() throws {
        let sleep = FakeSleep()
        var onAC = true
        let controller = PolicyController(policy: SleepPolicy(onAC: true), sleep: sleep, onACPower: { onAC }, persist: { _ in })
        try controller.reconcile()
        onAC = false
        try controller.reconcile()
        onAC = true
        try controller.reconcile()
        XCTAssertEqual(sleep.writes, [true, false, true])
    }

    func testInactivePreferenceDoesNotChangeCurrentPowerState() throws {
        let sleep = FakeSleep()
        var saved: SleepPolicy?
        let controller = PolicyController(policy: SleepPolicy(), sleep: sleep, onACPower: { true }, persist: { saved = $0 })
        try controller.toggle(onAC: false)
        XCTAssertEqual(saved, SleepPolicy(onBattery: true))
        XCTAssertTrue(sleep.writes.isEmpty)
    }

    func testPowerSourceIsReadWhenQueuedReconciliationRuns() throws {
        let sleep = FakeSleep()
        var onAC = true
        let controller = PolicyController(policy: SleepPolicy(onAC: true), sleep: sleep, onACPower: { onAC }, persist: { _ in })
        onAC = false
        try controller.reconcile()
        XCTAssertEqual(sleep.writes, [false])
    }

    func testMasterOffRestoresSleepAndSurvivesPollingAndPowerChanges() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        var onAC = true
        var saved: SleepPolicy?
        let controller = PolicyController(policy: SleepPolicy(onAC: true, onBattery: true),
                                          sleep: session, onACPower: { onAC }, persist: { saved = $0 })
        try controller.reconcile()
        XCTAssertTrue(power.awake)
        XCTAssertTrue(journal.pending)

        try controller.setEnabled(false)
        XCTAssertFalse(power.awake)
        XCTAssertFalse(journal.pending)
        XCTAssertEqual(saved, SleepPolicy(isEnabled: false, onAC: true, onBattery: true))
        for source in [true, false, false, true] {
            onAC = source
            try controller.reconcile()
            XCTAssertFalse(power.awake)
        }
        XCTAssertEqual(power.writes, [true, false])
        try controller.setEnabled(true)
        XCTAssertTrue(power.awake)
        XCTAssertTrue(journal.pending)
        XCTAssertEqual(saved, SleepPolicy(onAC: true, onBattery: true))
    }

    func testMasterOnUsesTheCurrentPowerSourceWithoutOverridingSavedChoices() throws {
        let sleep = FakeSleep()
        var onAC = true
        let controller = PolicyController(policy: SleepPolicy(isEnabled: false, onAC: true),
                                          sleep: sleep, onACPower: { onAC }, persist: { _ in })
        // The source can change while the master-enable action waits in the queue.
        onAC = false
        try controller.setEnabled(true)
        XCTAssertTrue(controller.policy.isEnabled)
        XCTAssertFalse(sleep.awake)
        XCTAssertTrue(controller.policy.onAC)
        XCTAssertFalse(controller.policy.onBattery)
        onAC = true
        try controller.reconcile()
        XCTAssertTrue(sleep.awake)
    }

    func testSavedMasterOffRemainsOffAfterRelaunch() throws {
        let sleep = FakeSleep()
        var saved = SleepPolicy(onAC: true, onBattery: true)
        let controller = PolicyController(policy: saved, sleep: sleep, onACPower: { true }, persist: { saved = $0 })
        try controller.setEnabled(false)
        let relaunched = PolicyController(policy: saved, sleep: sleep, onACPower: { false }, persist: { _ in })
        try relaunched.reconcile()
        XCTAssertFalse(sleep.awake)
        XCTAssertEqual(relaunched.policy, SleepPolicy(isEnabled: false, onAC: true, onBattery: true))
    }

    func testFailedMasterChangeKeepsPreviousStateAndCanBeRetried() throws {
        for enabled in [false, true] {
            for error in [ControlError.canceled, .message("permission denied")] {
                let sleep = FakeSleep()
                sleep.awake = enabled
                sleep.failure = error
                let original = SleepPolicy(isEnabled: enabled, onAC: true)
                var saved = [SleepPolicy]()
                let controller = PolicyController(policy: original, sleep: sleep, onACPower: { true }, persist: { saved.append($0) })
                XCTAssertThrowsError(try controller.setEnabled(!enabled))
                XCTAssertEqual(controller.policy, original)
                XCTAssertEqual(sleep.awake, enabled)
                XCTAssertTrue(saved.isEmpty)
                sleep.failure = nil
                try controller.setEnabled(!enabled)
                XCTAssertEqual(controller.policy.isEnabled, !enabled)
                XCTAssertEqual(sleep.awake, !enabled)
                XCTAssertEqual(saved.count, 1)
            }
        }
    }

    func testEditingSourcePreferencesWhileDisabledCannotEnableSleepPrevention() throws {
        let sleep = FakeSleep()
        sleep.failure = ControlError.message("No power command should run")
        var saved: SleepPolicy?
        let controller = PolicyController(policy: SleepPolicy(isEnabled: false), sleep: sleep,
                                          onACPower: { true }, persist: { saved = $0 })
        try controller.toggle(onAC: true)
        try controller.toggle(onAC: false)
        XCTAssertEqual(saved, SleepPolicy(isEnabled: false, onAC: true, onBattery: true))
        XCTAssertTrue(sleep.writes.isEmpty)
    }

    func testWorkerRestoresOnParentEOF() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        var requests = [#"{"operation":"set","awake":true}"#]
        var replies = [WorkerReply]()
        let result = SleepWorker.serve(session: session, receive: { requests.isEmpty ? nil : requests.removeFirst() }, reply: { replies.append($0) })
        XCTAssertEqual(result, 0)
        XCTAssertEqual(power.writes, [true, false])
        XCTAssertFalse(journal.pending)
        XCTAssertEqual(replies.last?.awake, true)
    }

    func testWorkerRefusesFailedQuitThenAcceptsRetry() throws {
        let power = FakePower(), journal = MemoryJournal()
        let session = try SleepSession(settings: power, journal: journal)
        var step = 0
        var replies = [WorkerReply]()
        let result = SleepWorker.serve(session: session, receive: {
            step += 1
            switch step {
            case 1: return #"{"operation":"set","awake":true}"#
            case 2: power.writeError = ControlError.message("denied"); return #"{"operation":"shutdown"}"#
            case 3: power.writeError = nil; return #"{"operation":"shutdown"}"#
            default: return nil
            }
        }, reply: { replies.append($0) })
        XCTAssertEqual(result, 0)
        XCTAssertEqual(replies[2].error, "denied")
        XCTAssertNil(replies[3].error)
        XCTAssertFalse(power.awake)
    }
}
