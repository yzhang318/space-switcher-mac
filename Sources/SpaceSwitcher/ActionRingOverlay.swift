import AppKit

/// Transparent, click-through overlay window that draws a ring surrounding the cursor
/// with a numbered slot per available Space. Slots are placed on the diagonals so
/// that the four cardinal axes (up/down/left/right) remain free for swipe gestures.
///
/// While the gesture button is held the host (`GestureEngine`) feeds the current
/// cursor position via `updateCursor(_:)`. When the cursor enters a slot the slot
/// enlarges and inverts colors. The host reads `selectedIndex` on button-up to
/// decide whether to switch to the corresponding Space instead of running the
/// normal swipe / click-repost logic.
final class ActionRingOverlay {

    private var window: NSWindow?
    private var view: ActionRingView?
    private(set) var ringCenter: CGPoint = .zero

    private let diameter: CGFloat = 200

    /// 0-based index of the slot currently under the cursor, or nil.
    var selectedIndex: Int? { view?.selectedIndex }

    func show(at screenPoint: CGPoint, slotCount: Int, currentIndex: Int) {
        let win = window ?? makeWindow()
        let frame = NSRect(x: screenPoint.x - diameter / 2,
                           y: screenPoint.y - diameter / 2,
                           width: diameter,
                           height: diameter)
        win.setFrame(frame, display: false)
        view?.configure(slotCount: slotCount, currentIndex: currentIndex)
        view?.selectedIndex = nil
        ringCenter = screenPoint
        win.orderFrontRegardless()
        window = win
    }

    /// Update the hovered-slot state given the cursor's global Cocoa position.
    func updateCursor(_ globalPoint: CGPoint) {
        let offset = CGPoint(x: globalPoint.x - ringCenter.x,
                             y: globalPoint.y - ringCenter.y)
        view?.updateSelection(cursorOffsetFromCenter: offset)
    }

    func hide() {
        view?.selectedIndex = nil
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                  .fullScreenAuxiliary, .ignoresCycle]
        win.isReleasedWhenClosed = false
        let v = ActionRingView(frame: NSRect(x: 0, y: 0,
                                             width: diameter,
                                             height: diameter))
        win.contentView = v
        view = v
        return win
    }
}

/// Custom view that draws the ring + numbered slots and tracks which slot
/// (if any) is under the cursor.
private final class ActionRingView: NSView {

    var slotCount: Int = 0
    var currentIndex: Int = 0
    var selectedIndex: Int? {
        didSet { if oldValue != selectedIndex { needsDisplay = true } }
    }

    private let baseSlotRadius: CGFloat = 17
    private let selectedSlotRadius: CGFloat = 21
    private var ringRadius: CGFloat { bounds.width / 2 - 36 }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(slotCount: Int, currentIndex: Int) {
        self.slotCount = max(0, slotCount)
        self.currentIndex = currentIndex
        needsDisplay = true
    }

    /// Evenly distribute slots clockwise starting from 12 o'clock (π/2).
    private func slotAngle(_ i: Int) -> CGFloat {
        let step = (2 * CGFloat.pi) / CGFloat(max(slotCount, 1))
        return .pi / 2 - step * CGFloat(i)
    }

    private func slotCenter(_ i: Int) -> CGPoint {
        let a = slotAngle(i)
        return CGPoint(x: bounds.midX + cos(a) * ringRadius,
                       y: bounds.midY + sin(a) * ringRadius)
    }

    /// Pick the nearest slot whose center is within hit radius of the cursor.
    func updateSelection(cursorOffsetFromCenter: CGPoint) {
        guard slotCount > 0 else { selectedIndex = nil; return }
        let cursor = CGPoint(x: bounds.midX + cursorOffsetFromCenter.x,
                             y: bounds.midY + cursorOffsetFromCenter.y)
        let hit = baseSlotRadius + 8
        var bestIdx: Int? = nil
        var bestDist2: CGFloat = .greatestFiniteMagnitude
        for i in 0..<slotCount {
            let c = slotCenter(i)
            let dx = c.x - cursor.x
            let dy = c.y - cursor.y
            let d2 = dx * dx + dy * dy
            if d2 <= hit * hit && d2 < bestDist2 {
                bestDist2 = d2
                bestIdx = i
            }
        }
        selectedIndex = bestIdx
    }

    override func draw(_ dirtyRect: NSRect) {
        guard slotCount > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        // ── Ring ────────────────────────────────────────────────────────────
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(2)
        ctx.setShadow(offset: .zero, blur: 8,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.strokeEllipse(in: NSRect(x: center.x - ringRadius,
                                     y: center.y - ringRadius,
                                     width: ringRadius * 2,
                                     height: ringRadius * 2))
        ctx.restoreGState()

        // ── Slots ───────────────────────────────────────────────────────────
        for i in 0..<slotCount {
            drawSlot(index: i, ctx: ctx)
        }
    }

    private func drawSlot(index i: Int, ctx: CGContext) {
        let isSelected = (selectedIndex == i)
        let isCurrent  = (currentIndex == i)
        let radius = isSelected ? selectedSlotRadius : baseSlotRadius

        let c = slotCenter(i)
        let rect = NSRect(x: c.x - radius, y: c.y - radius,
                          width: radius * 2, height: radius * 2)

        // Color scheme:
        //   selected → inverted (white fill, dark text)
        //   current  → faint accent tint
        //   default  → dark translucent fill, white text
        let fill: NSColor
        let stroke: NSColor
        let textColor: NSColor
        if isSelected {
            fill = NSColor.white
            stroke = NSColor.white
            textColor = NSColor.black
        } else if isCurrent {
            fill = NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.85, alpha: 0.85)
            stroke = NSColor.white.withAlphaComponent(0.9)
            textColor = NSColor.white
        } else {
            fill = NSColor(calibratedWhite: 0.10, alpha: 0.78)
            stroke = NSColor.white.withAlphaComponent(0.85)
            textColor = NSColor.white
        }

        ctx.saveGState()
        ctx.setShadow(offset: .zero,
                      blur: isSelected ? 10 : 6,
                      color: NSColor.black.withAlphaComponent(0.5).cgColor)
        fill.setFill()
        stroke.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = isSelected ? 2.0 : 1.5
        path.fill()
        path.stroke()
        ctx.restoreGState()

        let label = "\(i + 1)" as NSString
        let fontSize: CGFloat = isSelected ? 15 : 13
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: textColor
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: c.x - size.width / 2,
                               y: c.y - size.height / 2),
                   withAttributes: attrs)
    }
}
