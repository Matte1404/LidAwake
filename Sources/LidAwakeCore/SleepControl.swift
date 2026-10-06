import Foundation

public protocol SleepControlling {
    func isAwake() throws -> Bool
    func setAwake(_ awake: Bool) throws
    func stop() throws
}

protocol PowerSettings {
    func read() throws -> Bool
    func requireAutomaticControl() throws
    func write(_ awake: Bool) throws
}

final class PMSet: PowerSettings {
    let runner: CommandRunning
    let setup: PrivilegeSetup
    init(runner: CommandRunning, setup: PrivilegeSetup) {
        self.runner = runner
        self.setup = setup
    }

    func read() throws -> Bool {
        try Self.parse(runner.run("/usr/bin/pmset", ["-g"], timeout: 10).stdout)
    }

    static func parse(_ output: String) throws -> Bool {
        let matches = output.split(separator: "\n").compactMap { line -> Bool? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, fields[0] == "SleepDisabled" else { return nil }
            return fields[1] == "1" ? true : (fields[1] == "0" ? false : nil)
        }
        guard matches.count == 1 else { throw ControlError.message("Could not read the current sleep setting.") }
        return matches[0]
    }

    func requireAutomaticControl() throws {
        guard setup.isInstalled else {
            throw ControlError.message("Enable or repair Sleep Setup before turning on keep-awake.")
        }
        try probeRule()
    }

    /// `sudo -l` succeeds for any command once an admin account has any NOPASSWD rule,
    /// so prove the rule by running the commands. Both directions are needed: the rule must also
    /// allow the restore. Writing the current value changes nothing; the opposite value is
    /// written only when that is sleep-preventing (0 -> 1 -> 0), because writing 0 could put the
    /// Mac to sleep while something else holds it awake. Starting from 0 the order also leaves
    /// the setting unchanged when the rule is one-sided: a denied 1 changes nothing, and a
    /// restore to 0 is only attempted after 0 was proven.
    func probeRule() throws {
        let current = try read()
        try sudoWrite(current)
        guard !current else { return }
        do { try sudoWrite(true) } catch {
            _ = try? sudoWrite(false)
            throw error
        }
        try write(false)
    }

    private func sudoWrite(_ awake: Bool) throws {
        // -k ignores cached admin authentication; recovery must work without it.
        _ = try runner.run("/usr/bin/sudo", ["-n", "-k", "/usr/bin/pmset", "-a", "disablesleep", awake ? "1" : "0"], timeout: 10)
    }

    func write(_ awake: Bool) throws {
        try sudoWrite(awake)
        guard try read() == awake else {
            throw ControlError.message("macOS did not apply the sleep setting. Try Repair Sleep Setup.")
        }
    }
}

protocol RecoveryJournal {
    func load() throws -> Bool
    func save(_ pending: Bool) throws
}

/// Sole writer for a running app. Its journal is committed before enabling sleep
/// prevention, so even a crash during the command leaves a recoverable obligation.
final class SleepSession: SleepControlling {
    private let settings: PowerSettings
    private let journal: RecoveryJournal
    private var ownsOverride: Bool
    private var needsRecovery: Bool

    init(settings: PowerSettings, journal: RecoveryJournal) throws {
        self.settings = settings
        self.journal = journal
        ownsOverride = try journal.load()
        needsRecovery = ownsOverride
    }

    func recover() throws {
        if needsRecovery {
            try stop()
            needsRecovery = false
        }
    }

    func isAwake() throws -> Bool { try settings.read() }

    func setAwake(_ awake: Bool) throws {
        try recover()
        let current = try settings.read()
        if awake {
            // Check both directions before accepting ownership, even if already awake.
            if !ownsOverride {
                try settings.requireAutomaticControl()
                try journal.save(true)
                ownsOverride = true
            }
            if !current { try settings.write(true) }
        } else {
            if current { try settings.write(false) }
            if ownsOverride { try journal.save(false) }
            ownsOverride = false
        }
    }

    func stop() throws {
        guard ownsOverride else { return }
        if try settings.read() { try settings.write(false) }
        try journal.save(false)
        ownsOverride = false
        needsRecovery = false
    }
}

public struct SleepPolicy: Codable, Equatable {
    public var isEnabled: Bool
    public var onAC: Bool
    public var onBattery: Bool
    public init(isEnabled: Bool = true, onAC: Bool = false, onBattery: Bool = false) {
        self.isEnabled = isEnabled
        self.onAC = onAC
        self.onBattery = onBattery
    }
    public func desired(onACPower: Bool) -> Bool { isEnabled && (onACPower ? onAC : onBattery) }
}

/// Policy preferences commit only after a successful change for the active source.
/// Inactive-source edits never touch the current global setting.
public final class PolicyController {
    public private(set) var policy: SleepPolicy
    private let sleep: SleepControlling
    private let onACPower: () -> Bool
    private let persist: (SleepPolicy) -> Void

    public init(policy: SleepPolicy, sleep: SleepControlling, onACPower: @escaping () -> Bool,
                persist: @escaping (SleepPolicy) -> Void) {
        self.policy = policy
        self.sleep = sleep
        self.onACPower = onACPower
        self.persist = persist
    }

    public func reconcile() throws { try sleep.setAwake(policy.desired(onACPower: onACPower())) }

    public func setEnabled(_ enabled: Bool) throws {
        var candidate = policy
        candidate.isEnabled = enabled
        try sleep.setAwake(candidate.desired(onACPower: onACPower()))
        policy = candidate
        persist(candidate)
    }

    public func toggle(onAC: Bool) throws {
        var candidate = policy
        if onAC { candidate.onAC.toggle() } else { candidate.onBattery.toggle() }
        if candidate.isEnabled && onACPower() == onAC {
            try sleep.setAwake(candidate.desired(onACPower: onAC))
        }
        policy = candidate
        persist(candidate)
    }

    public func stop() throws { try sleep.stop() }
}
