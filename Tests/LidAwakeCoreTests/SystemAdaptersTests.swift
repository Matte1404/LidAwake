import XCTest
import Darwin
@testable import LidAwakeCore

final class RecordingRunner: CommandRunning {
    var calls = [(String, [String])]()
    var respond: ([String]) throws -> CommandOutput = { _ in CommandOutput() }
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        calls.append((executable, arguments))
        return try respond(arguments)
    }
}

final class SystemAdaptersTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testSleepStatusParserRejectsMissingMalformedAndAmbiguousValues() throws {
        XCTAssertTrue(try PMSet.parse("System-wide power settings:\n SleepDisabled\t1\n"))
        XCTAssertFalse(try PMSet.parse(" SleepDisabled   0\n"))
        for output in ["", "pmset failed", "SleepDisabled 10", "NotSleepDisabled 1", "SleepDisabled 1\nSleepDisabled 0"] {
            XCTAssertThrowsError(try PMSet.parse(output), output)
        }
    }

    func testPMSetVerifiesTheActualWriteAndDoesNotUseCachedCredentials() throws {
        let runner = RecordingRunner()
        runner.respond = { args in CommandOutput(stdout: args == ["-g"] ? "SleepDisabled 0" : "") }
        let pmset = PMSet(runner: runner, setup: PrivilegeSetup(runner: runner))
        XCTAssertThrowsError(try pmset.write(true))
        XCTAssertEqual(runner.calls[0].1, ["-n", "-k", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        XCTAssertEqual(runner.calls[1].1, ["-g"])
    }

    func testPMSetProbeWritesTheCurrentValueInsteadOfListingPrivileges() throws {
        let runner = RecordingRunner()
        for value in ["0", "1"] {
            runner.calls = []
            runner.respond = { args in CommandOutput(stdout: args == ["-g"] ? "SleepDisabled \(value)" : "") }
            try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner)).probeRule()
            XCTAssertEqual(runner.calls.map { [$0.0] + $0.1 }, [
                ["/usr/bin/pmset", "-g"],
                ["/usr/bin/sudo", "-n", "-k", "/usr/bin/pmset", "-a", "disablesleep", value]])
        }
    }

    func testPMSetRequiresTheRuleFileBeforeProbing() {
        let runner = RecordingRunner()
        let pmset = PMSet(runner: runner, setup: PrivilegeSetup(runner: runner, uid: 502, directory: directory.path))
        XCTAssertThrowsError(try pmset.requireAutomaticControl())
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testPMSetReadPropagatesProcessFailureEvenWithValidLookingOutput() {
        let runner = RecordingRunner()
        runner.respond = { _ in throw ControlError.message("pmset unavailable") }
        XCTAssertThrowsError(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner)).read())
    }

    func testNewSudoRuleParsesAndContainsOnlyTwoExactCommands() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 501, directory: directory.path)
        let rule = directory.appendingPathComponent("rule")
        try setup.rule.write(to: rule, atomically: true, encoding: .utf8)
        _ = try ProcessCommandRunner().run("/usr/sbin/visudo", ["-cf", rule.path], timeout: 5)
        XCTAssertFalse(setup.rule.contains("*"))
        XCTAssertTrue(setup.rule.hasPrefix("#501 "))
        XCTAssertEqual(setup.rule.components(separatedBy: "/usr/bin/pmset").count, 3)
        XCTAssertFalse(setup.isInstalled) // No rule for this account at its expected path.
    }

    func testInstallerNarrowsLegacyRuleAndPreservesItsAccount() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        let legacy = directory.appendingPathComponent("lidawake")
        try "other_user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *, /usr/bin/pmset -b disablesleep *, /usr/bin/pmset -c disablesleep *\n".write(to: legacy, atomically: true, encoding: .utf8)
        // Exercise the real generated script in a temporary directory; omit chown.
        let script = setup.installationScript.replacingOccurrences(of: "-o root -g wheel", with: "")
        _ = try ProcessCommandRunner().run("/bin/sh", ["-c", script], timeout: 10)
        let result = try String(contentsOf: legacy)
        XCTAssertTrue(result.hasPrefix("other_user ALL="))
        XCTAssertFalse(result.contains("*"))
        XCTAssertEqual(try String(contentsOfFile: setup.path), setup.rule)
    }

    func testInstallerPreservesUnknownLegacyContentAndPropagatesValidationFailure() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), directory: directory.path)
        let legacy = directory.appendingPathComponent("lidawake")
        let custom = "custom administrator rule\n"
        try custom.write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", setup.installationScript], timeout: 5))
        XCTAssertEqual(try String(contentsOf: legacy), custom)
        try FileManager.default.removeItem(at: legacy)
        let badValidation = setup.installationScript.replacingOccurrences(of: "/usr/sbin/visudo", with: "/usr/bin/false")
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", badValidation], timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.path))
    }

    func testInstallerRefusesLegacySymlink() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), directory: directory.path)
        let target = directory.appendingPathComponent("untouched")
        try "original".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("lidawake"), withDestinationURL: target)
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", setup.installationScript], timeout: 5))
        XCTAssertEqual(try String(contentsOf: target), "original")
    }

    func testCommandRunnerHandlesLaunchFailureExitFailureAndCancellation() throws {
        let runner = ProcessCommandRunner()
        XCTAssertThrowsError(try runner.run("/missing/lidawake-command", [], timeout: 1))
        XCTAssertThrowsError(try runner.run("/bin/sh", ["-c", "echo deliberate-error >&2; exit 7"], timeout: 2)) {
            XCTAssertTrue($0.localizedDescription.contains("deliberate-error"))
        }
        XCTAssertThrowsError(try runner.run("/bin/sh", ["-c", "echo 'execution error: User canceled. (-128)' >&2; exit 1"], timeout: 2)) {
            XCTAssertEqual($0 as? ControlError, .canceled)
        }
    }

    func testCommandTimeoutAndLargeOutputDoNotHang() throws {
        let runner = ProcessCommandRunner()
        let start = Date()
        XCTAssertThrowsError(try runner.run("/bin/sleep", ["10"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        let result = try runner.run("/bin/sh", ["-c", "/usr/bin/yes x | /usr/bin/head -c 262144; /usr/bin/yes y | /usr/bin/head -c 262144 >&2"], timeout: 5)
        XCTAssertEqual(result.stdout.utf8.count, 262144)
        XCTAssertEqual(result.stderr.utf8.count, 262144)
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(appleScriptString("a\\b\"c\nd"), "\"a\\\\b\\\"c\\nd\"")
    }

    func testLoginUsesResolvedBundlePathAsAnArgumentAndVerifiesRegistration() throws {
        let runner = RecordingRunner()
        let bundle = directory.appendingPathComponent("My \"LidAwake\".app")
        let login = LoginItems(runner: runner, bundleURL: bundle)
        var responses = ["", "true"]
        runner.respond = { _ in CommandOutput(stdout: responses.removeFirst()) }
        try login.setEnabled(true)
        XCTAssertEqual(runner.calls.count, 2)
        for call in runner.calls {
            XCTAssertEqual(call.1.last, bundle.path)
            XCTAssertFalse(call.1[1].contains(bundle.path))
        }
    }

    func testLoginFailureAndUnknownStatusAreReported() throws {
        let runner = RecordingRunner()
        let login = LoginItems(runner: runner, bundleURL: directory.appendingPathComponent("LidAwake.app"))
        XCTAssertThrowsError(try login.isEnabled())
        runner.respond = { args in CommandOutput(stdout: args[1].contains("return") ? "false" : "") }
        XCTAssertThrowsError(try login.setEnabled(true))
        runner.respond = { _ in throw ControlError.message("Automation denied") }
        XCTAssertThrowsError(try login.isEnabled())
    }

    func testRecoveryJournalSurvivesReopenAndRefusesSymlinks() throws {
        var journal: FileRecoveryJournal? = try FileRecoveryJournal(directory: directory)
        try journal?.save(true)
        journal = nil
        journal = try FileRecoveryJournal(directory: directory)
        XCTAssertTrue(try journal!.load())
        try journal?.save(false)
        XCTAssertFalse(try journal!.load())
        journal = nil
        let path = directory.appendingPathComponent("restore-sleep")
        try FileManager.default.removeItem(at: path)
        let target = directory.appendingPathComponent("untouched")
        try "data".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        XCTAssertThrowsError(try FileRecoveryJournal(directory: directory))
        XCTAssertEqual(try String(contentsOf: target), "data")
    }

    func testOnlyOneSessionCanOwnTheGlobalSetting() throws {
        let path = directory.appendingPathComponent("lock").path
        var first: SessionLock? = try SessionLock(path: path)
        try withExtendedLifetime(first) { XCTAssertThrowsError(try SessionLock(path: path)) }
        first = nil
        _ = try SessionLock(path: path)
    }

    func testWorkerStartupFailureCanQuitWithoutTouchingAnotherSession() throws {
        let script = directory.appendingPathComponent("busy-worker")
        try "#!/bin/sh\necho '{\"error\":\"Another session owns sleep\",\"fatal\":true}'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = SleepWorkerClient(executable: script)
        XCTAssertThrowsError(try client.start())
        XCTAssertNoThrow(try client.stop())
    }

    func testWorkerClientCommunicatesWithoutWaitingForPipeEOF() throws {
        let script = directory.appendingPathComponent("worker")
        try """
        #!/bin/sh
        echo '{"awake":false}'
        while IFS= read -r line; do
            case "$line" in
                *shutdown*) echo '{"awake":false}'; exit 0 ;;
                *) echo '{"awake":true}' ;;
            esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = SleepWorkerClient(executable: script)
        try client.start()
        try client.setAwake(true)
        XCTAssertTrue(try client.isAwake())
        try client.stop()
    }
}
