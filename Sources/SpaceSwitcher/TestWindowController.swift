import AppKit

final class TestWindowController: NSWindowController, NSWindowDelegate {

    // Called by StatusBarController so it can nil out its reference when the window closes
    var onClose: (() -> Void)?

    private let monitor = HIDMouseMonitor()

    // UI outlets
    private var mousePopup:   NSPopUpButton!
    private var buttonPopup:  NSPopUpButton!
    private var logScrollView: NSScrollView!
    private var logTextView:   NSTextView!
    private var statusLabel:   NSTextField!

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mouse Button Tester"
        window.minSize = NSSize(width: 420, height: 320)
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        refreshDevices()
        startMonitoring()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        monitor.stopMonitoring()
        onClose?()
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // ── Mouse row ──────────────────────────────────────────────────────
        let mouseLabel = makeLabel("Mouse:")
        mousePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        mousePopup.addItem(withTitle: "All Mice")
        mousePopup.target = self
        mousePopup.action = #selector(mouseSelectionChanged)
        mousePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refreshDevices))
        refreshBtn.bezelStyle = .rounded

        let mouseRow = hstack([mouseLabel, mousePopup, refreshBtn])

        // ── Button filter row ──────────────────────────────────────────────
        let buttonLabel = makeLabel("Button:")
        buttonPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        buttonPopup.addItems(withTitles: [
            "All Buttons",
            "Button 1 (Left)",
            "Button 2 (Right)",
            "Button 3 (Middle)",
            "Button 4",
            "Button 5",
            "Button 6",
            "Button 7",
            "Button 8",
        ])
        buttonPopup.target = self
        buttonPopup.action = #selector(buttonSelectionChanged)
        buttonPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonRow = hstack([buttonLabel, buttonPopup])

        // Align the two label columns
        NSLayoutConstraint.activate([
            mouseLabel.widthAnchor.constraint(equalToConstant: 52),
            buttonLabel.widthAnchor.constraint(equalToConstant: 52),
        ])

        // ── Event log ──────────────────────────────────────────────────────
        logScrollView = NSScrollView()
        logScrollView.hasVerticalScroller = true
        logScrollView.hasHorizontalScroller = false
        logScrollView.autohidesScrollers = true
        logScrollView.borderType = .bezelBorder

        logTextView = NSTextView()
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = NSColor.textBackgroundColor
        logTextView.isVerticallyResizable = true
        logTextView.isHorizontallyResizable = false
        logTextView.autoresizingMask = [.width]
        logTextView.textContainer?.widthTracksTextView = true
        logTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        logScrollView.documentView = logTextView

        // ── Status + Clear row ─────────────────────────────────────────────
        statusLabel = makeLabel("● Monitoring active")
        statusLabel.textColor = .systemGreen
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearLog))
        clearBtn.bezelStyle = .rounded

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY
        bottomRow.addView(statusLabel, in: .leading)
        bottomRow.addView(clearBtn,    in: .trailing)

        // ── Hint ───────────────────────────────────────────────────────────
        let hintLabel = NSTextField(
            wrappingLabelWithString:
                "If no events appear: System Settings → Privacy & Security → Input Monitoring — add this app."
        )
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor

        // ── Outer vertical stack ───────────────────────────────────────────
        let outer = NSStackView(views: [mouseRow, buttonRow, logScrollView, bottomRow, hintLabel])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 10
        outer.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        outer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Stretch rows to full width
            mouseRow.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -32),
            buttonRow.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -32),
            logScrollView.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -32),
            logScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            bottomRow.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -32),
            hintLabel.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -32),
        ])
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return s
    }

    // MARK: - Actions

    @objc private func refreshDevices() {
        let found = monitor.enumerateMice()
        mousePopup.removeAllItems()
        mousePopup.addItem(withTitle: "All Mice")
        for dev in found {
            let item = NSMenuItem(title: dev.name, action: nil, keyEquivalent: "")
            item.representedObject = dev.uniqueKey
            mousePopup.menu?.addItem(item)
        }
        mouseSelectionChanged()
    }

    @objc private func mouseSelectionChanged() {
        monitor.filterDeviceKey = mousePopup.indexOfSelectedItem == 0
            ? nil
            : mousePopup.selectedItem?.representedObject as? String
    }

    @objc private func buttonSelectionChanged() {
        let idx = buttonPopup.indexOfSelectedItem
        // index 0 = "All Buttons" → nil; index N = button N
        monitor.filterButton = idx == 0 ? nil : idx
    }

    @objc private func clearLog() {
        logTextView.string = ""
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.startMonitoring { [weak self] event in
            self?.appendEvent(event)
        }
    }

    private func appendEvent(_ event: MouseButtonEvent) {
        let time   = timeFormatter.string(from: event.timestamp)
        let arrow  = event.pressed ? "▼" : "▲"
        let state  = event.pressed ? "pressed " : "released"
        let line   = "\(time)  \(event.device.name.padding(toLength: 32, withPad: " ", startingAt: 0))  \(event.buttonLabel.padding(toLength: 20, withPad: " ", startingAt: 0))  \(arrow) \(state)\n"

        let color: NSColor = event.pressed ? .labelColor : .secondaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: line, attributes: attrs)

        logTextView.textStorage?.append(attrStr)
        logTextView.scrollToEndOfDocument(nil)
    }
}
