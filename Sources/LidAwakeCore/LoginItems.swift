import Foundation

public final class LoginItems {
    private let runner: CommandRunning
    public let bundlePath: String
    public init(runner: CommandRunning, bundleURL: URL) {
        self.runner = runner
        bundlePath = bundleURL.resolvingSymlinksInPath().path
    }

    public func isEnabled() throws -> Bool {
        let output = try execute("""
        tell application "System Events"
            return (count of (login items whose path is appPath)) > 0
        end tell
        """)
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default: throw ControlError.message("Could not read Launch at Login status.")
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard bundlePath.hasSuffix(".app") else {
            throw ControlError.message("Launch the built .app bundle to configure Launch at Login.")
        }
        _ = try execute(enabled ? """
        tell application "System Events"
            delete (login items whose name is "LidAwake")
            make login item at end with properties {path:appPath, hidden:true}
        end tell
        """ : """
        tell application "System Events"
            delete (login items whose path is appPath)
        end tell
        """)
        guard try isEnabled() == enabled else {
            throw ControlError.message("Launch at Login did not change. Check Automation access in System Settings.")
        }
    }

    private func execute(_ body: String) throws -> String {
        // Paths are data, never interpolated into AppleScript source.
        let script = "on run argv\nset appPath to item 1 of argv\n" + body + "\nend run"
        return try runner.run("/usr/bin/osascript", ["-e", script, bundlePath], timeout: 20).stdout
    }
}
