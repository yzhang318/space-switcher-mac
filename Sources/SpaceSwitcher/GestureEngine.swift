import AppKit
import CoreGraphics
import IOKit.hid

/// Intercepts a specific mouse button on a specific device via CGEventTap and translates
/// horizontal mouse movement (while the button is held) into macOS Space switches,
/// and vertical mouse movement into mission-control / app-exposé triggers.
///
/// Architecture
/// ────────────
/// • `HIDMouseMonitor` (IOKit HID, read-only) tracks per-device button state.
///   IOKit HID callbacks fire *before* the same physical event becomes a CGEvent,
///   so by the time CGEventTap fires we already know which physical device sent it.
/// • `CGEventTap` (kCGHIDEventTap) intercepts the matching button events and returns nil
///   to suppress them entirely — the original action (e.g. "Back") never reaches apps.
/// • Horizontal mouse-moved/dragged deltas are accumulated while the button is held;
///   when the threshold is crossed a space switch is fired via `/usr/bin/osascript`.
///
/// Space switching method: Process + /usr/bin/osascript -e <AppleScript>
/// DO NOT change to CGKeyboardEvent, AXUIElement, or any other method.
/// This specific approach is tested and verified to work with the shortcut-based
/// Space switching on this machine.
final class GestureEngine {

    private(set) var config: GestureConfig

    // MARK: IOKit — tracks which physical device has the button held
    // IOKit HID callbacks are scheduled on the main run loop and fire before the
    // corresponding CGEvent reaches our tap, so this flag is always current.
    private var hidMonitor: HIDMouseMonitor?
    private var targetDeviceButtonHeld = false

    // MARK: CGEventTap — suppresses the button and detects swipe direction
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: Gesture state  (only touched on the main thread)
    private var gestureButtonHeld  = false
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var lastGestureFiredAt: Date   = .distantPast
    private let gestureCooldown: TimeInterval = 0.35
    /// Set on button-down; used to detect short clicks.
    private var buttonDownTime: Date? = nil
    /// Press+release within this window with minimal movement = short click → repost.
    private let shortClickDuration: TimeInterval = 0.3

    // MARK: Velocity-based (flick) detection
    //
    // A rolling window of recent (dx, timestamp) pairs is maintained.
    // When the instantaneous velocity exceeds `config.velocityThreshold`, a flick fires
    // immediately — no need to travel the full distance threshold.
    //
    // Hysteresis: after a flick fires in a direction, `lastFlickSign` is set so the
    // same continuous motion cannot fire twice.  Once velocity drops below
    // `velocityResetThreshold` the sign resets, allowing the *next* fast motion
    // (e.g. the second "fast" in fast→slow→fast) to fire independently.
    private var motionSamples: [(dx: CGFloat, time: TimeInterval)] = []
    /// Direction of the last velocity-triggered fire: +1 = right, -1 = left, 0 = idle.
    private var lastFlickSign: Int = 0
    /// Rolling window length in seconds used to compute instantaneous velocity.
    private let velocityWindowSec: TimeInterval = 0.12
    /// Velocity (px/s) below which the hysteresis sign resets between flicks.
    private let velocityResetThreshold: CGFloat  = 80

    // MARK: Ring-button state (separate from gesture/swipe button)
    private var ringButtonHeld  = false
    private var targetDeviceRingButtonHeld = false

    // MARK: Visual feedback overlay (shown when ring button is held)
    private let actionRing = ActionRingOverlay()
    /// Snapshot of the Space layout taken at ring-button-down; used to translate the
    /// hovered slot into a left/right delta from the current Space.
    private var spaceLayoutAtDown: (count: Int, currentIndex: Int)?
    private var ringVisible = false

    // MARK: Notifications
    static let didChangeState = Notification.Name("GestureEngineDidChangeState")

    /// True when the user has enabled the gesture but the configured mouse is
    /// not currently connected, so the event tap is suspended.
    private(set) var isAutoDisabled = false

    init(config: GestureConfig) {
        self.config = config
    }

    // MARK: - Public API

    var isRunning: Bool { eventTap != nil }

    /// Apply a new config, persisting it and restarting the engine as needed.
    func apply(_ newConfig: GestureConfig) {
        stop()
        config = newConfig
        newConfig.save()
        start()
        broadcastState()
    }

    func start() {
        if config.enabled {
            startHIDTracker()
            // Whether the event tap actually installs depends on whether the
            // configured device is currently connected.
            evaluateDevicePresence()
        }
    }

    func stop() {
        removeEventTap()
        stopHIDTracker()
        gestureButtonHeld  = false
        ringButtonHeld     = false
        accumulatedDeltaX  = 0
        accumulatedDeltaY  = 0
        motionSamples.removeAll()
        lastFlickSign      = 0
        buttonDownTime     = nil
        targetDeviceButtonHeld     = false
        targetDeviceRingButtonHeld = false
        isAutoDisabled     = false
        actionRing.hide()
    }

    // MARK: - Accessibility check

    /// Prompts for Accessibility if not yet granted; returns current trust status.
    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - IOKit device tracker

    private func startHIDTracker() {
        let monitor = HIDMouseMonitor()
        monitor.devicesChangedCallback = { [weak self] in
            self?.evaluateDevicePresence()
        }
        monitor.startMonitoring { [weak self] event in
            guard let self else { return }
            // If no device filter is set, treat any device as a match.
            if let targetKey = self.config.deviceKey {
                guard event.device.uniqueKey == targetKey else { return }
            }
            if event.button == self.config.buttonNumber {
                self.targetDeviceButtonHeld = event.pressed
            }
            if event.button == self.config.ringButtonNumber {
                self.targetDeviceRingButtonHeld = event.pressed
            }
        }
        hidMonitor = monitor
    }

    private func stopHIDTracker() {
        hidMonitor?.stopMonitoring()
        hidMonitor = nil
        targetDeviceButtonHeld = false
    }

    // MARK: - Device presence

    /// Checks whether the configured mouse is currently connected and
    /// installs / removes the event tap accordingly. When the device is
    /// missing while the user has the gesture enabled, the engine enters
    /// the `isAutoDisabled` state — the saved `enabled` flag in the config
    /// is **not** changed, so the gesture resumes automatically once the
    /// device reappears.
    private func evaluateDevicePresence() {
        guard config.enabled, let key = config.deviceKey else {
            if eventTap != nil { removeEventTap() }
            if isAutoDisabled {
                isAutoDisabled = false
                broadcastState()
            }
            return
        }
        let present = hidMonitor?.devices.contains(where: { $0.uniqueKey == key }) ?? false
        if present {
            let wasAuto = isAutoDisabled
            isAutoDisabled = false
            if eventTap == nil { installEventTap() }
            if wasAuto { broadcastState() }
        } else {
            if eventTap != nil { removeEventTap() }
            let wasAuto = isAutoDisabled
            isAutoDisabled = true
            if !wasAuto { broadcastState() }
        }
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.rightMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseUp.rawValue)      |
            (1 << CGEventType.otherMouseDown.rawValue)    |
            (1 << CGEventType.otherMouseUp.rawValue)      |
            (1 << CGEventType.mouseMoved.rawValue)        |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let eng = Unmanaged<GestureEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return eng.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("GestureEngine: CGEvent.tapCreate failed — grant Accessibility permission in System Settings")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap      = tap
        runLoopSource = src
    }

    private func removeEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap      = nil
        runLoopSource = nil
    }

    // MARK: - Event handling (called on main run loop)

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return onButtonDown(event: event)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return onButtonUp(event: event)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseMoved(event: event)
            return Unmanaged.passUnretained(event)   // movement is never suppressed

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func onButtonDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        // CGEvent button number is 0-indexed; config uses 1-indexed to match IOKit HID.
        let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1

        // ── Gesture / swipe button ────────────────────────────────────────────
        if btn == config.buttonNumber {
            // Device gate: IOKit tracker must confirm this physical device matches.
            if config.deviceKey != nil, !targetDeviceButtonHeld {
                return Unmanaged.passUnretained(event)
            }
            gestureButtonHeld = true
            accumulatedDeltaX = 0
            accumulatedDeltaY = 0
            motionSamples.removeAll()
            lastFlickSign     = 0
            buttonDownTime    = Date()
            // Ring is NOT shown for the swipe button.
            broadcastState()
            return nil   // suppress
        }

        // ── Ring button ───────────────────────────────────────────────────────
        if btn == config.ringButtonNumber {
            // Device gate
            if config.deviceKey != nil, !targetDeviceRingButtonHeld {
                return Unmanaged.passUnretained(event)
            }
            ringButtonHeld = true
            let layout = SpaceQuery.mainDisplayLayout()
            spaceLayoutAtDown = layout
            if let layout, layout.count > 1 {
                actionRing.show(at: NSEvent.mouseLocation,
                                slotCount: layout.count,
                                currentIndex: layout.currentIndex)
                ringVisible = true
            } else {
                ringVisible = false
            }
            broadcastState()
            return nil   // suppress
        }

        return Unmanaged.passUnretained(event)
    }

    private func onButtonUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1

        // ── Gesture / swipe button ────────────────────────────────────────────
        if gestureButtonHeld, btn == config.buttonNumber {
            let elapsed      = buttonDownTime.map { Date().timeIntervalSince($0) } ?? 1.0
            let noSwipe      = abs(accumulatedDeltaX) < config.movementThreshold * 0.3
                            && abs(accumulatedDeltaY) < config.movementThreshold * 0.3
            let isShortClick = elapsed < shortClickDuration && noSwipe

            gestureButtonHeld = false
            accumulatedDeltaX = 0
            accumulatedDeltaY = 0
            motionSamples.removeAll()
            lastFlickSign     = 0
            buttonDownTime    = nil
            broadcastState()

            if isShortClick {
                let position = event.location
                let btn0     = config.buttonNumber - 1
                DispatchQueue.main.async { [weak self] in
                    self?.repostButtonClick(position: position, button0: btn0)
                }
            }
            return nil
        }

        // ── Ring button ───────────────────────────────────────────────────────
        if ringButtonHeld, btn == config.ringButtonNumber {
            // Capture selection before hiding.
            let ringSelection = ringVisible ? actionRing.selectedIndex : nil
            let layout = spaceLayoutAtDown

            ringButtonHeld    = false
            actionRing.hide()
            ringVisible       = false
            spaceLayoutAtDown = nil
            broadcastState()

            if let target = ringSelection, let layout {
                switchToSpace(targetIndex: target, fromIndex: layout.currentIndex)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    /// Re-issues a button down+up pair at cgSessionEventTap level,
    /// bypassing our cghidEventTap so there is no re-entry.
    private func repostButtonClick(position: CGPoint, button0: Int) {
        let downType: CGEventType
        let upType:   CGEventType
        switch button0 {
        case 0:  downType = .leftMouseDown;  upType = .leftMouseUp
        case 1:  downType = .rightMouseDown; upType = .rightMouseUp
        default: downType = .otherMouseDown; upType = .otherMouseUp
        }
        // CGEvent init requires a CGMouseButton for otherMouse events.
        // Create with .center then override mouseEventButtonNumber to the actual value.
        let cgBtn: CGMouseButton = (button0 == 0) ? .left : (button0 == 1) ? .right : .center
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(mouseEventSource: src, mouseType: downType,
                              mouseCursorPosition: position, mouseButton: cgBtn) {
            down.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button0))
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(mouseEventSource: src, mouseType: upType,
                            mouseCursorPosition: position, mouseButton: cgBtn) {
            up.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button0))
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func onMouseMoved(event: CGEvent) {
        // Update the action-ring hover state whenever the ring button is held.
        if ringVisible {
            actionRing.updateCursor(NSEvent.mouseLocation)
        }

        guard gestureButtonHeld else { return }

        let dx  = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        let dy  = CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
        let now = Date()
        accumulatedDeltaX += dx
        accumulatedDeltaY += dy

        // ── Velocity / flick detection ────────────────────────────────────────
        // Maintain a short rolling window of samples and compute px/s velocity.
        // A "flick" fires as soon as the speed threshold is crossed, before the
        // full distance threshold is reached.  Hysteresis via lastFlickSign
        // ensures one continuous motion fires only once, but a fresh fast motion
        // after a slow/idle phase can fire again (fast → slow → fast = 2 fires).
        if config.velocityThreshold > 0 {
            let t = now.timeIntervalSinceReferenceDate
            motionSamples.append((dx: dx, time: t))
            // Prune samples outside the rolling window
            motionSamples.removeAll { t - $0.time > velocityWindowSec }

            if motionSamples.count >= 2 {
                let windowDuration = CGFloat(t - motionSamples[0].time)
                let windowDx       = motionSamples.reduce(CGFloat(0)) { $0 + $1.dx }
                let velocity       = windowDuration > 0.01 ? windowDx / windowDuration : 0

                // Hysteresis reset: speed dropped to idle → allow next flick
                if abs(velocity) < velocityResetThreshold {
                    lastFlickSign = 0
                }

                let flickSign = velocity > 0 ? 1 : (velocity < 0 ? -1 : 0)
                let cooldownOk = now.timeIntervalSince(lastGestureFiredAt) > gestureCooldown * 0.4
                if flickSign != 0
                    && abs(velocity) >= config.velocityThreshold
                    && flickSign != lastFlickSign
                    && cooldownOk
                    // Noise guard: require a small minimum displacement
                    && abs(windowDx) >= max(config.movementThreshold * 0.15, 4)
                {
                    lastFlickSign      = flickSign
                    accumulatedDeltaX  = 0
                    motionSamples.removeAll()
                    lastGestureFiredAt = now
                    triggerSpaceSwitch(right: flickSign > 0)
                    return
                }
            }
        }

        // ── Distance / slow-drag fallback ────────────────────────────────────
        // If the user drags slowly the velocity threshold is never reached;
        // fire once the accumulated displacement crosses movementThreshold.
        guard now.timeIntervalSince(lastGestureFiredAt) > gestureCooldown else { return }

        if accumulatedDeltaX >= config.movementThreshold {
            accumulatedDeltaX  = 0
            accumulatedDeltaY  = 0
            motionSamples.removeAll()
            lastFlickSign      = 1
            lastGestureFiredAt = now
            triggerSpaceSwitch(right: true)
        } else if accumulatedDeltaX <= -config.movementThreshold {
            accumulatedDeltaX  = 0
            accumulatedDeltaY  = 0
            motionSamples.removeAll()
            lastFlickSign      = -1
            lastGestureFiredAt = now
            triggerSpaceSwitch(right: false)
        } else if accumulatedDeltaY >= config.movementThreshold {
            // Down movement (positive dy = downward on screen)
            accumulatedDeltaX  = 0
            accumulatedDeltaY  = 0
            motionSamples.removeAll()
            lastFlickSign      = 0
            lastGestureFiredAt = now
            triggerVerticalSwitch(up: false)
        } else if accumulatedDeltaY <= -config.movementThreshold {
            // Up movement (negative dy = upward on screen)
            accumulatedDeltaX  = 0
            accumulatedDeltaY  = 0
            motionSamples.removeAll()
            lastFlickSign      = 0
            lastGestureFiredAt = now
            triggerVerticalSwitch(up: true)
        }
    }

    // MARK: - Space switching
    //
    // Uses Process + /usr/bin/osascript -e <AppleScript>.
    // Horizontal: key code 123 = Left, 124 = Right (with Control).
    // Vertical:   key code 125 = Down, 126 = Up    (with Control).
    // DO NOT replace with CGKeyboardEvent, AXUIElement, or NSAppleScript.
    // This is the tested, verified method for this project.

    private func triggerSpaceSwitch(right: Bool) {
        let keyCode = right ? 124 : 123
        runControlKey(keyCode)
    }

    private func triggerVerticalSwitch(up: Bool) {
        // key code 126 = Up arrow, 125 = Down arrow (with Control).
        let keyCode = up ? 126 : 125
        runControlKey(keyCode)
    }

    /// Switch directly to a target Space index by firing Control+Arrow N times,
    /// where N is the absolute distance from the current Space.
    /// Direction is right (key code 124) when target > current, otherwise left (123).
    /// Switch directly to a target Space by pressing Ctrl+Arrow N times inside
    /// a single Control-held block.
    ///
    /// Timing note: the macOS Space transition animation is ~300 ms.  Pressing
    /// the arrow again *during* that animation is silently dropped by the WM,
    /// so an inter-key delay shorter than the animation drops every other press
    /// (a 0.15 s gap → only half register).  0.28 s is just past the animation
    /// while still feeling responsive.
    private func switchToSpace(targetIndex: Int, fromIndex: Int) {
        let diff = targetIndex - fromIndex
        guard diff != 0 else { return }
        let keyCode = diff > 0 ? 124 : 123
        let count = abs(diff)

        // Build N key-code lines separated by a short delay.
        // Use `key down` + `key up` for the arrow (instead of `key code`) so each
        // press is unambiguously a fresh event rather than auto-repeat, which the
        // WM treats differently and may coalesce.
        let delayStr = String(format: "%.3f", config.multiSpaceDelay)
        var keyLines = ""
        for i in 0..<count {
            keyLines += "    key down \(keyCode)\n    delay 0.02\n    key up \(keyCode)\n"
            if i < count - 1 {
                keyLines += "    delay \(delayStr)\n"
            }
        }
        let script = """
            tell application "System Events"
                key down control
                delay 0.05
            \(keyLines)    delay 0.05
                key up control
            end tell
            """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments    = ["-e", script]
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            NSLog("GestureEngine: osascript launch failed — %@", error.localizedDescription)
        }
    }

    private func runControlKey(_ keyCode: Int) {
        let script = """
            tell application "System Events"
                key down control
                delay 0.05
                key code \(keyCode)
                delay 0.05
                key up control
            end tell
            """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments    = ["-e", script]
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            NSLog("GestureEngine: osascript launch failed — %@", error.localizedDescription)
        }
    }

    // MARK: - State broadcast

    private func broadcastState() {
        NotificationCenter.default.post(
            name: Self.didChangeState,
            object: self,
            userInfo: ["buttonHeld": gestureButtonHeld, "running": isRunning]
        )
    }
}
