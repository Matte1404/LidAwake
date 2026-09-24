import Foundation

/// Direct-build "Uninstall LidAwake…"; the app moves itself to the Trash afterwards. Each stage
/// runs only after the previous one is verified, so a failure says exactly what was removed.
/// The login item goes first: it is the one step that can fail without an admin prompt
/// (Automation access), and it can be put back if the admin prompt is canceled.
public final class Uninstaller {
    public protocol LoginItem {
        func isEnabled() throws -> Bool
        func setEnabled(_ enabled: Bool) throws
    }
    public enum Failure: Error {
        /// Nothing was removed. `loginItemOff`: Launch at Login was turned off and could not be turned back on.
        case nothingRemoved(Error, loginItemOff: Bool)
        /// The login item and possibly some sleep rules were removed; `remaining` still exist.
        case incomplete(remaining: [String], Error)
    }
    private let login: LoginItem
    private let rules: PrivilegeSetup
    private let dataDirectory: URL

    public init(login: LoginItem, rules: PrivilegeSetup, dataDirectory: URL) {
        self.login = login
        self.rules = rules
        self.dataDirectory = dataDirectory
    }

    /// `resumeSleep` runs after a failure that left the sleep rules in place (or some of them);
    /// its own failure shows in the menu's sleep status, not in place of the uninstall result.
    /// Returns true when the legacy rule was left in place because it is not this account's.
    @discardableResult
    public func run(stopSleep: () throws -> Void, resumeSleep: () throws -> Void, removeSettings: () -> Void) throws -> Bool {
        let loginWasOn: Bool
        do { loginWasOn = try login.isEnabled() } catch { throw Failure.nothingRemoved(error, loginItemOff: false) }
        func nothingRemoved(_ cause: Error) -> Failure {
            guard loginWasOn else { return .nothingRemoved(cause, loginItemOff: false) }
            do {
                if try !login.isEnabled() { try login.setEnabled(true) }
                return .nothingRemoved(cause, loginItemOff: false)
            } catch { return .nothingRemoved(cause, loginItemOff: true) }
        }
        do { if loginWasOn { try login.setEnabled(false) } } catch { throw nothingRemoved(error) }
        do { try stopSleep() } catch {
            try? resumeSleep()
            throw nothingRemoved(error)
        }
        let before = rules.remainingRules
        let keptLegacyRule: Bool
        do { keptLegacyRule = try rules.uninstall() } catch {
            try? resumeSleep()
            let after = rules.remainingRules
            if after == before { throw nothingRemoved(error) }
            throw Failure.incomplete(remaining: after, error)
        }
        removeSettings()
        do {
            if (try? FileManager.default.attributesOfItem(atPath: dataDirectory.path)) != nil {
                try FileManager.default.removeItem(at: dataDirectory)
            }
        } catch { throw Failure.incomplete(remaining: [dataDirectory.path], error) }
        return keptLegacyRule
    }
}

extension LoginItems: Uninstaller.LoginItem {}
