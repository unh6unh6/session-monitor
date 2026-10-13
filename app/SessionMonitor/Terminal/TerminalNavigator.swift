import AppKit
import ApplicationServices
import Darwin

/// Brings a session's terminal to the front (docs/plan.md §3.5, DECISIONS.md D7, D16).
///
/// - Warp: no scripting and no tabs in AX, so the best target is a window whose title (the active
///   tab's title, which Claude Code sets to the session title) matches; otherwise activate Warp.
/// - Terminal.app: AppleScript selects the tab with the session's tty.
/// - Anything else: activate the app.
/// Activating an app or raising a window also switches to its Space (macOS default behaviour).
@MainActor
enum TerminalNavigator {
    enum Outcome: Equatable {
        /// The exact tab was selected.
        case tab
        /// A matching window was raised.
        case window
        /// Only the terminal app was activated.
        case app
        case failed(String)
    }

    static let warpBundleID = "dev.warp.Warp-Stable"
    static let appleTerminalBundleID = "com.apple.Terminal"

    static func canFocus(_ session: Session) -> Bool {
        !session.state.isEnded && session.process != nil
    }

    @discardableResult
    static func focus(_ session: Session) -> Outcome {
        guard canFocus(session), let process = session.process else { return .failed("세션이 종료되었습니다") }
        guard let app = terminalApp(hosting: process.pid) ?? terminalApp(program: process.terminal.program) else {
            return .failed("터미널 앱을 찾지 못했습니다")
        }
        let outcome: Outcome
        switch app.bundleIdentifier {
        case appleTerminalBundleID:
            outcome = focusAppleTerminalTab(tty: process.tty) ? .tab : activate(app)
        case warpBundleID:
            outcome = raiseWindow(of: app, titled: session.title) ? .window : activate(app)
        default:
            outcome = activate(app)
        }
        return outcome
    }

    // MARK: Finding the terminal

    /// Walks up from the claude process to the first ancestor that is a GUI app.
    static func terminalApp(hosting pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            guard current > 1 else { return nil }
            if current != pid, let app = NSRunningApplication(processIdentifier: current), app.bundleIdentifier != nil {
                return app
            }
            guard let parent = parentPID(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    /// Fallback from TERM_PROGRAM when the process tree can't be walked.
    static func terminalApp(program: String) -> NSRunningApplication? {
        let bundleID: String
        switch program {
        case "WarpTerminal": bundleID = warpBundleID
        case "Apple_Terminal": bundleID = appleTerminalBundleID
        case "iTerm.app": bundleID = "com.googlecode.iterm2"
        default: return nil
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    // MARK: Focusing

    private static func activate(_ app: NSRunningApplication) -> Outcome {
        NSApp.yieldActivation(to: app)
        return app.activate() ? .app : .failed("\(app.localizedName ?? "터미널")을 활성화하지 못했습니다")
    }

    /// Terminal.app: select the tab whose tty matches and bring its window forward.
    private static func focusAppleTerminalTab(tty: String?) -> Bool {
        guard let tty, tty.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let source = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("SessionMonitor: Terminal.app focus failed: \(error)") }
        return result?.booleanValue == true
    }

    /// Warp: press the Window menu item whose title matches the session title.
    /// Needs Accessibility; returns false (so the caller just activates the app) without it.
    private static func raiseWindow(of app: NSRunningApplication, titled title: String?) -> Bool {
        guard let title, !title.isEmpty, AXIsProcessTrusted() else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar: AXUIElement = attribute(axApp, kAXMenuBarAttribute),
              let windowMenu = children(menuBar).first(where: { self.title(of: $0) == "Window" }),
              let menu = children(windowMenu).first,
              let item = children(menu).first(where: { windowTitle(self.title(of: $0), matches: title) })
        else { return false }
        NSApp.yieldActivation(to: app)
        app.activate()
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Claude Code prefixes the terminal title with a spinner/status glyph ("◐ my-session").
    static func windowTitle(_ windowTitle: String, matches sessionTitle: String) -> Bool {
        let trimmed = windowTitle.drop { !$0.isLetter && !$0.isNumber }
        return !trimmed.isEmpty && trimmed == Substring(sessionTitle)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    private static func title(of element: AXUIElement) -> String {
        attribute(element, kAXTitleAttribute) ?? ""
    }
}
