// Compiled only by scripts/test-recovery.sh alongside the production core.
// Power settings are files in a temporary directory; this never runs pmset/sudo.
import Foundation
import Darwin

final class FilePower: PowerSettings {
    let path: URL
    init(directory: URL) { path = directory.appendingPathComponent("awake") }
    func read() throws -> Bool { try String(contentsOf: path, encoding: .utf8) == "1" }
    func requireAutomaticControl() throws {}
    func write(_ awake: Bool) throws {
        try (awake ? "1" : "0").write(to: path, atomically: true, encoding: .utf8)
        if awake { Thread.sleep(forTimeInterval: 0.4) }
    }
}

signal(SIGPIPE, SIG_IGN)
let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIDAWAKE_RECOVERY_TEST_DIR"]!)
let mode = CommandLine.arguments[1]
if mode == "--sleep-worker" {
    let lock = try SessionLock(path: directory.appendingPathComponent("lock").path)
    let session = try SleepSession(settings: FilePower(directory: directory), journal: FileRecoveryJournal(directory: directory))
    let status = withExtendedLifetime(lock) {
        SleepWorker.serve(session: session, receive: { readLine() }, reply: { reply in
            let data = try! JSONEncoder().encode(reply) + Data([10])
            try? FileHandle.standardOutput.write(contentsOf: data)
        })
    }
    exit(status)
}
let client = SleepWorkerClient(executable: URL(fileURLWithPath: CommandLine.arguments[0]))
try client.start()
if mode == "crash-during-write" {
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { kill(getpid(), SIGKILL) }
}
try client.setAwake(true)
if mode == "crash" { kill(getpid(), SIGKILL) }
try client.stop()
