/// Orders Quit against an in-flight uninstall. Main-thread only. A quit requested
/// while an uninstall runs waits for its outcome, so the result is never dropped
/// by the app's terminating guard (Trash + quit on success, restore + message on failure).
public struct TerminationGate {
    public enum QuitDecision: Equatable { case start, alreadyTerminating, afterUninstall, terminateNow }
    public private(set) var terminating = false
    public private(set) var uninstalling = false
    private var quitDeferred = false
    private var uninstalled = false

    /// Menu actions stay unavailable from the start of an uninstall until its outcome
    /// is handled (or the app is quitting).
    public var locksMenuActions: Bool { terminating || uninstalling }

    public init() {}

    public mutating func requestQuit() -> QuitDecision {
        guard !terminating else { return .alreadyTerminating }
        if uninstalling { quitDeferred = true; return .afterUninstall }
        terminating = true
        return uninstalled ? .terminateNow : .start
    }

    /// "Stay Open" after a failed restore.
    public mutating func cancelQuit() { terminating = false }

    public mutating func beginUninstall() -> Bool {
        guard !terminating, !uninstalling else { return false }
        uninstalling = true
        return true
    }

    /// Returns true when a quit requested during the uninstall must now start.
    /// `succeeded` records that the uninstall already restored sleep and stopped the worker,
    /// so the app's own quit afterwards is `.terminateNow`: a restore round-trip would wait
    /// for a main-queue reply from inside the main-queue block that calls terminate.
    public mutating func endUninstall(succeeded: Bool = false) -> Bool {
        uninstalling = false
        uninstalled = succeeded
        guard quitDeferred else { return false }
        quitDeferred = false
        terminating = true
        return true
    }
}
