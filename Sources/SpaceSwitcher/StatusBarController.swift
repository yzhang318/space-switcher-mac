import AppKit

class StatusBarController {

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let gestureEngine: GestureEngine
    private var testWindowController: TestWindowController?
    private var remapConfigController: RemapConfigController?

    // AppleScript snippets for switching macOS Spaces.
    // key code 123 = Left arrow, 124 = Right arrow (with Control held).
    private static let scriptSpaceLeft = """
        tell application "System Events"
            key down control
            delay 0.05
            key code 123
            delay 0.05
            key up control
        end tell
        """

    private static let scriptSpaceRight = """
        tell application "System Events"
            key down control
            delay 0.05
            key code 124
            delay 0.05
            key up control
        end tell
        """

    init(gestureEngine: GestureEngine) {
        self.gestureEngine = gestureEngine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        configureIcon()
        configureMenu()
        statusItem.menu = menu
    }

    // MARK: - Icon

    private func configureIcon() {
        guard let button = statusItem.button else { return }
        // SF Symbol "cursorarrow.motionlines" — cursor with motion trails,
        // conveys mouse-gesture movement. Available on macOS 12+.
        let image = NSImage(
            systemSymbolName: "cursorarrow.motionlines",
            accessibilityDescription: "Space Switcher"
        )
        image?.isTemplate = true   // adapts to dark/light menu bar automatically
        button.image = image
        button.toolTip = "Space Switcher"
    }

    // MARK: - Menu

    private func configureMenu() {
        let leftItem = NSMenuItem(
            title: "Space Left",
            action: #selector(switchSpaceLeft),
            keyEquivalent: ""
        )
        leftItem.target = self

        let rightItem = NSMenuItem(
            title: "Space Right",
            action: #selector(switchSpaceRight),
            keyEquivalent: ""
        )
        rightItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let testItem = NSMenuItem(
            title: "Test Mouse Buttons…",
            action: #selector(openTestWindow),
            keyEquivalent: ""
        )
        testItem.target = self

        let remapItem = NSMenuItem(
            title: "Gesture Remap…",
            action: #selector(openRemapConfig),
            keyEquivalent: ""
        )
        remapItem.target = self

        menu.addItem(leftItem)
        menu.addItem(rightItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(remapItem)
        menu.addItem(testItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func openRemapConfig() {
        if remapConfigController == nil {
            let wc = RemapConfigController(engine: gestureEngine)
            wc.onClose = { [weak self] in self?.remapConfigController = nil }
            remapConfigController = wc
        }
        remapConfigController?.showWindow(nil)
        remapConfigController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openTestWindow() {
        if testWindowController == nil {
            let wc = TestWindowController()
            wc.onClose = { [weak self] in self?.testWindowController = nil }
            testWindowController = wc
        }
        testWindowController?.showWindow(nil)
        testWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func switchSpaceLeft() {
        runAppleScript(StatusBarController.scriptSpaceLeft)
    }

    @objc private func switchSpaceRight() {
        runAppleScript(StatusBarController.scriptSpaceRight)
    }

    // MARK: - AppleScript runner

    /// Runs an AppleScript string by spawning `/usr/bin/osascript`.
    private func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        // Capture stderr so it doesn't leak into the console in release builds
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            // Fire-and-forget — don't wait; the delay inside the script is short
        } catch {
            NSLog("SpaceSwitcher: failed to launch osascript — %@", error.localizedDescription)
        }
    }
}
