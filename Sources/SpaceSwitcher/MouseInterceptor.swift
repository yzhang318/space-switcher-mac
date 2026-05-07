import AppKit

/// Placeholder for future mouse interception.
///
/// Intended extension points:
///   - Mouse movement: use `CGEvent.tapCreate` with `.mouseMoved` events
///     to detect edge-of-screen movement and trigger space switching automatically.
///   - Mouse button: tap `NSEvent.EventTypeMask` for `.otherMouseDown`
///     (e.g., thumb buttons on gaming mice) to map them to space switches.
class MouseInterceptor {

    // TODO: add CGEventTap for mouse movement interception
    // TODO: add CGEventTap or NSEvent.addGlobalMonitorForEvents for mouse button interception

    func start() {
        // TODO: install event taps here
    }

    func stop() {
        // TODO: remove event taps here
    }
}
