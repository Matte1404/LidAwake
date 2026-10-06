/// Orders Quit against an in-flight uninstall. Main-thread only. A quit requested
/// while an uninstall runs waits for its outcome, so the result is never dropped
/// by the app's terminating guard (Trash + quit on success, restore + message on failure).
public struct TerminationGate {
    public enum QuitDecision: Equatable { case start, alreadyTerminating, afterUninstall }
    public private(set) var terminating = false
    public private(set) var uninstalling = false
    private var quitDeferred = false

    /// Menu actions stay unavailable from the start of an uninstall until its outcome
    /// is handled (or the app is quitting).
    public var locksMenuActions: Bool { terminating || uninstalling }

    public init() {}

    public mutating func requestQuit() -> QuitDecision {
        guard !terminating else { return .alreadyTerminating }
        if uninstalling { quitDeferred = true; return .afterUninstall }
        terminating = true
        return .start
    }

    /// "Stay Open" after a failed restore.
    public mutating func cancelQuit() { terminating = false }

    public mutating func beginUninstall() -> Bool {
        guard !terminating, !uninstalling else { return false }
        uninstalling = true
        return true
    }

    /// Returns true when a quit requested during the uninstall must now start.
    public mutating func endUninstall() -> Bool {
        uninstalling = false
        guard quitDeferred else { return false }
        quitDeferred = false
        terminating = true
        return true
    }
}
