import Foundation
import Darwin

public final class PrivilegeSetup {
    public let path: String
    private let uid: uid_t
    private let runner: CommandRunning
    private let legacyPath: String

    public init(runner: CommandRunning, uid: uid_t = getuid(), directory: String = "/etc/sudoers.d") {
        self.runner = runner
        self.uid = uid
        path = directory + "/lidawake-\(uid)"
        legacyPath = directory + "/lidawake"
    }

    public var rule: String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    // A readable exact rule detects old installations and rules for another account.
    // Every actual write still uses sudo -n -k and checks its result and live state.
    public var isInstalled: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0,
              (try? String(contentsOfFile: path, encoding: .utf8)) == rule else { return false }
        if FileManager.default.fileExists(atPath: legacyPath) {
            guard let legacy = try? String(contentsOfFile: legacyPath, encoding: .utf8),
                  legacy.range(of: #"^[a-zA-Z0-9._-]+ ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n?$"#,
                               options: .regularExpression) != nil else { return false }
        }
        return true
    }

    public func install() throws {
        _ = try runner.run("/usr/bin/osascript", ["-e",
            "do shell script \(appleScriptString(installationScript)) with administrator privileges"], timeout: 120)
        guard isInstalled else { throw ControlError.message("Sleep setup could not be verified. Try Repair Sleep Setup.") }
    }

    var installationScript: String {
        // Preserve a legacy rule's account while narrowing its commands. Refuse unknown
        // content instead of replacing a file that may have been edited by an administrator.
        let oldPattern = #"^([a-zA-Z0-9._-]+) ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep \*, /usr/bin/pmset -b disablesleep \*, /usr/bin/pmset -c disablesleep \*$"#
        let newPattern = #"^[a-zA-Z0-9._-]+ ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1$"#
        let replacement = #"\1 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"#
        return """
        set -eu
        work=$(/usr/bin/mktemp -d)
        trap '/bin/rm -rf "$work"' EXIT
        /bin/mkdir -p \(shellString(URL(fileURLWithPath: path).deletingLastPathComponent().path))
        if [ -L \(shellString(legacyPath)) ] || [ -L \(shellString(path)) ]; then
            echo 'Refusing a symbolic link in sleep setup.' >&2
            exit 1
        fi
        if [ -e \(shellString(legacyPath)) ]; then
            if [ "$(/usr/bin/awk 'END { print NR }' \(shellString(legacyPath)))" != 1 ]; then
                echo 'Legacy sleep rule has unexpected content; ask your administrator to review it.' >&2
                exit 1
            fi
            if /usr/bin/grep -Eq \(shellString(oldPattern)) \(shellString(legacyPath)); then
                /usr/bin/sed -E \(shellString("s|" + oldPattern + "|" + replacement + "|")) \(shellString(legacyPath)) > "$work/legacy"
            elif /usr/bin/grep -Eq \(shellString(newPattern)) \(shellString(legacyPath)); then
                /bin/cp \(shellString(legacyPath)) "$work/legacy"
            else
                echo 'Legacy sleep rule has unexpected content; ask your administrator to review it.' >&2
                exit 1
            fi
            /usr/sbin/visudo -cf "$work/legacy"
            /usr/bin/install -m 0444 -o root -g wheel "$work/legacy" \(shellString(legacyPath))
        fi
        /usr/bin/printf '%s' \(shellString(rule)) > "$work/rule"
        /usr/sbin/visudo -cf "$work/rule"
        /usr/bin/install -m 0444 -o root -g wheel "$work/rule" \(shellString(path))
        """
    }
}
