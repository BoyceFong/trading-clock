import Foundation
import ServiceManagement

/// Launch-at-login management. Primary: modern SMAppService (System Settings →
/// General → Login Items). Fallback: the osascript System Events flow, which
/// also works with ad-hoc signing. Ported from the economic-calendar widget.
enum LoginItemService {
    private static let appName = "TradingClock"

    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func isEnabled() -> Bool {
        if isBundled {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        return osascriptIsEnabled()
    }

    /// Toggle; returns the new state.
    @discardableResult
    static func toggle() -> Bool {
        if isEnabled() {
            disable()
        } else {
            enable()
        }
        return isEnabled()
    }

    private static func enable() {
        if isBundled {
            do {
                try SMAppService.mainApp.register()
                return
            } catch {
                NSLog("SMAppService register failed: \(error.localizedDescription)")
            }
        }
        _ = osascriptEnable()
    }

    private static func disable() {
        if isBundled {
            do {
                try SMAppService.mainApp.unregister()
                return
            } catch {
                NSLog("SMAppService unregister failed: \(error.localizedDescription)")
            }
        }
        _ = osascriptDisable()
    }

    // MARK: - osascript fallback

    private static func appBundlePath() -> String? {
        guard isBundled else { return nil }
        return Bundle.main.bundleURL.path
    }

    private static func runOSA(_ script: String) -> (code: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        } catch {
            NSLog("osascript failed to launch: \(error.localizedDescription)")
            return nil
        }
    }

    private static func osascriptIsEnabled() -> Bool {
        guard let result = runOSA("tell application \"System Events\" to get the name of every login item"),
              result.code == 0 else {
            return false
        }
        let names = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return names.contains(appName)
    }

    private static func osascriptEnable() -> Bool {
        guard let appPath = appBundlePath() else { return false }
        _ = osascriptDisable()
        guard let result = runOSA(
            "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false}"
        ) else { return false }
        return result.code == 0
    }

    private static func osascriptDisable() -> Bool {
        guard appBundlePath() != nil else { return false }
        guard let result = runOSA(
            "tell application \"System Events\" to delete login item \"\(appName)\""
        ) else { return false }
        if result.code == 0 { return true }
        return result.stderr.contains("not exist") || result.stderr.contains("Can't get")
    }
}
