import AppKit

final class RemapConfigController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

    private let engine: GestureEngine

    // UI controls
    private var enableCheckbox:   NSButton!
    private var mousePopup:       NSPopUpButton!
    private var buttonPopup:      NSPopUpButton!
    private var ringButtonPopup:  NSPopUpButton!
    private var thresholdSlider:  NSSlider!
    private var thresholdLabel:   NSTextField!
    private var velocitySlider:   NSSlider!
    private var velocityLabel:    NSTextField!
    private var spaceDelaySlider: NSSlider!
    private var spaceDelayLabel:  NSTextField!
    private var statusLabel:      NSTextField!
    private var accessHintLabel:  NSTextField!

    private var stateObserver: NSObjectProtocol?

    // MARK: - Init

    init(engine: GestureEngine) {
        self.engine = engine
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gesture Remap"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        populateFromConfig()
        refreshMice()
        subscribeToEngine()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let obs = stateObserver { NotificationCenter.default.removeObserver(obs) }
        onClose?()
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ── Enable toggle ─────────────────────────────────────────────────
        enableCheckbox = NSButton(
            checkboxWithTitle: "Enable gesture remap",
            target: self,
            action: #selector(controlChanged)
        )
        enableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        // ── Mouse row ─────────────────────────────────────────────────────
        mousePopup = NSPopUpButton()
        mousePopup.target = self
        mousePopup.action = #selector(controlChanged)
        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refreshMice))
        refreshBtn.bezelStyle = .rounded

        let mouseRow = hstack([label("Mouse:", width: 76), mousePopup, refreshBtn])

        // ── Button row ────────────────────────────────────────────────────
        buttonPopup = NSPopUpButton()
        buttonPopup.addItems(withTitles: (1...8).map { Self.buttonTitle($0) })
        buttonPopup.target = self
        buttonPopup.action = #selector(controlChanged)
        let buttonRow = hstack([label("Button:", width: 90), buttonPopup])

        // ── Ring button row ───────────────────────────────────────────────
        ringButtonPopup = NSPopUpButton()
        ringButtonPopup.addItems(withTitles: (1...8).map { Self.buttonTitle($0) })
        ringButtonPopup.target = self
        ringButtonPopup.action = #selector(controlChanged)
        let ringButtonRow = hstack([label("Ring button:", width: 90), ringButtonPopup])

        // ── Threshold / sensitivity row ───────────────────────────────────
        thresholdSlider = NSSlider(value: 150, minValue: 20, maxValue: 600,
                                   target: self, action: #selector(sliderMoved))
        thresholdSlider.isContinuous = true

        thresholdLabel = NSTextField(labelWithString: " 150 px")
        thresholdLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        thresholdLabel.alignment = .right
        thresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        thresholdLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let thrRow = hstack([label("Distance:", width: 76), thresholdSlider, thresholdLabel])

        // ── Velocity / speed row ──────────────────────────────────────────
        // Controls the flick-speed threshold (px/s).  Set to minimum to effectively
        // disable velocity detection and rely on distance only.
        velocitySlider = NSSlider(value: 800, minValue: 100, maxValue: 3000,
                                  target: self, action: #selector(sliderMoved))
        velocitySlider.isContinuous = true

        velocityLabel = NSTextField(labelWithString: " 800 px/s")
        velocityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        velocityLabel.alignment = .right
        velocityLabel.translatesAutoresizingMaskIntoConstraints = false
        velocityLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let velRow = hstack([label("Speed:", width: 76), velocitySlider, velocityLabel])

        // ── Space delay row ───────────────────────────────────────────────
        // Controls the inter-press delay (ms) when switching multiple spaces at once.
        spaceDelaySlider = NSSlider(value: 280, minValue: 100, maxValue: 600,
                                    target: self, action: #selector(sliderMoved))
        spaceDelaySlider.isContinuous = true

        spaceDelayLabel = NSTextField(labelWithString: " 280 ms")
        spaceDelayLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        spaceDelayLabel.alignment = .right
        spaceDelayLabel.translatesAutoresizingMaskIntoConstraints = false
        spaceDelayLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let delayRow = hstack([label("Space delay:", width: 90), spaceDelaySlider, spaceDelayLabel])

        // ── Status ────────────────────────────────────────────────────────
        statusLabel = NSTextField(labelWithString: "—")
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let statusRow = hstack([label("Status:", width: 76), statusLabel])

        // ── Hint text ─────────────────────────────────────────────────────
        let hintLabel = NSTextField(wrappingLabelWithString:
            "Hold the trigger button and move the mouse left or right to switch spaces.\n" +
            "Fast flick: fires as soon as the speed threshold is crossed (distance is ignored).\n" +
            "Slow drag: fires when accumulated movement exceeds the distance threshold.\n" +
            "Fast → slow → fast fires twice (velocity resets during the slow phase).\n" +
            "A short click (< 0.3 s) without significant movement re-fires the original button action.\n" +
            "Ring button: hold to show the space-picker ring; release on a slot to jump to that space.\n" +
            "Space delay: minimum gap between arrow presses when jumping multiple spaces."
        )
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor

        accessHintLabel = NSTextField(wrappingLabelWithString:
            "⚠  Accessibility permission required: System Settings → Privacy & Security → Accessibility."
        )
        accessHintLabel.font = NSFont.systemFont(ofSize: 11)
        accessHintLabel.textColor = .systemOrange
        accessHintLabel.isHidden = true

        // ── Outer stack ───────────────────────────────────────────────────────────
        let sep1 = separator()
        let sep2 = separator()

        let stack = NSStackView(views: [
            enableCheckbox,
            sep1,
            mouseRow,
            buttonRow,
            ringButtonRow,
            thrRow,
            velRow,
            delayRow,
            sep2,
            statusRow,
            hintLabel,
            accessHintLabel,
        ])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 10
        stack.edgeInsets  = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stack)

        let w = stack.widthAnchor
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cv.topAnchor),
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor),

            sep1.widthAnchor.constraint(equalTo: w, constant: -32),
            sep2.widthAnchor.constraint(equalTo: w, constant: -32),
            mouseRow.widthAnchor.constraint(equalTo: w, constant: -32),
            buttonRow.widthAnchor.constraint(equalTo: w, constant: -32),
            ringButtonRow.widthAnchor.constraint(equalTo: w, constant: -32),
            thrRow.widthAnchor.constraint(equalTo: w, constant: -32),
            velRow.widthAnchor.constraint(equalTo: w, constant: -32),
            delayRow.widthAnchor.constraint(equalTo: w, constant: -32),
            statusRow.widthAnchor.constraint(equalTo: w, constant: -32),
            hintLabel.widthAnchor.constraint(equalTo: w, constant: -32),
            accessHintLabel.widthAnchor.constraint(equalTo: w, constant: -32),
        ])
    }

    // MARK: - Populate from current engine config

    private func populateFromConfig() {
        let cfg = engine.config
        enableCheckbox.state         = cfg.enabled ? .on : .off
        buttonPopup.selectItem(at: max(0, cfg.buttonNumber - 1))
        ringButtonPopup.selectItem(at: max(0, cfg.ringButtonNumber - 1))
        thresholdSlider.integerValue = Int(cfg.movementThreshold)
        thresholdLabel.stringValue   = "\(Int(cfg.movementThreshold)) px"
        velocitySlider.integerValue  = Int(cfg.velocityThreshold)
        velocityLabel.stringValue    = "\(Int(cfg.velocityThreshold)) px/s"
        let delayMs = Int(cfg.multiSpaceDelay * 1000)
        spaceDelaySlider.integerValue = delayMs
        spaceDelayLabel.stringValue   = "\(delayMs) ms"
        refreshStatus()
    }

    @objc private func refreshMice() {
        let mice = HIDMouseMonitor().enumerateMice()
        mousePopup.removeAllItems()

        let anyItem = NSMenuItem(title: "Any Mouse", action: nil, keyEquivalent: "")
        mousePopup.menu?.addItem(anyItem)

        for mouse in mice {
            let item = NSMenuItem(title: mouse.name, action: nil, keyEquivalent: "")
            item.representedObject = mouse
            mousePopup.menu?.addItem(item)
        }

        // Re-select previously saved device
        if let savedKey = engine.config.deviceKey {
            for i in 1..<mousePopup.numberOfItems {
                if let d = mousePopup.item(at: i)?.representedObject as? HIDMouseDevice,
                   d.uniqueKey == savedKey {
                    mousePopup.selectItem(at: i)
                    return
                }
            }
        }
        mousePopup.selectItem(at: 0)
    }

    // MARK: - Actions

    @objc private func controlChanged() {
        saveAndApply()
    }

    @objc private func sliderMoved() {
        thresholdLabel.stringValue  = "\(thresholdSlider.integerValue) px"
        velocityLabel.stringValue   = "\(velocitySlider.integerValue) px/s"
        spaceDelayLabel.stringValue = "\(spaceDelaySlider.integerValue) ms"
        saveAndApply()
    }

    private func saveAndApply() {
        let selectedDevice = mousePopup.indexOfSelectedItem > 0
            ? mousePopup.selectedItem?.representedObject as? HIDMouseDevice
            : nil

        let cfg = GestureConfig(
            enabled:           enableCheckbox.state == .on,
            deviceKey:         selectedDevice?.uniqueKey,
            deviceName:        selectedDevice?.name,
            buttonNumber:      buttonPopup.indexOfSelectedItem + 1,
            ringButtonNumber:  ringButtonPopup.indexOfSelectedItem + 1,
            movementThreshold: CGFloat(thresholdSlider.integerValue),
            velocityThreshold: CGFloat(velocitySlider.integerValue),
            multiSpaceDelay:   Double(spaceDelaySlider.integerValue) / 1000.0
        )
        cfg.save()
        engine.apply(cfg)
        // Prompt for Accessibility permission the first time the user enables
        if cfg.enabled { engine.requestAccessibilityIfNeeded() }
        refreshStatus()
    }

    // MARK: - Engine state subscription

    private func subscribeToEngine() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: GestureEngine.didChangeState,
            object: engine,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let held = note.userInfo?["buttonHeld"] as? Bool ?? false
            if held {
                self.statusLabel.stringValue = "● Button held — move mouse horizontally"
                self.statusLabel.textColor   = .systemGreen
            } else {
                self.refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        let trusted = AXIsProcessTrusted()
        if !engine.config.enabled {
            statusLabel.stringValue   = "Disabled"
            statusLabel.textColor     = .secondaryLabelColor
            accessHintLabel.isHidden  = true
        } else if !trusted {
            statusLabel.stringValue   = "Waiting for Accessibility permission…"
            statusLabel.textColor     = .systemOrange
            accessHintLabel.isHidden  = false
        } else if engine.isRunning {
            statusLabel.stringValue   = "● Idle — waiting for button hold"
            statusLabel.textColor     = .secondaryLabelColor
            accessHintLabel.isHidden  = true
        } else {
            statusLabel.stringValue   = "Not running"
            statusLabel.textColor     = .secondaryLabelColor
            accessHintLabel.isHidden  = true
        }
    }

    // MARK: - View helpers

    private static func buttonTitle(_ n: Int) -> String {
        switch n {
        case 1: return "Button 1 (Left)"
        case 2: return "Button 2 (Right)"
        case 3: return "Button 3 (Middle)"
        case 4: return "Button 4 (Back)"
        case 5: return "Button 5 (Forward)"
        default: return "Button \(n)"
        }
    }

    private func label(_ text: String, width: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing     = 8
        s.alignment   = .centerY
        return s
    }

    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }
}
