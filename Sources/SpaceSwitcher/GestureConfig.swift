import Foundation
import CoreGraphics

struct GestureConfig {
    /// Whether the gesture remap is active.
    var enabled: Bool
    /// `HIDMouseDevice.uniqueKey` of the target mouse. `nil` = match any device.
    var deviceKey: String?
    /// Human-readable name of the target mouse (display only).
    var deviceName: String?
    /// 1-indexed button number on the target mouse (e.g. 4 = typical "Back" button).
    var buttonNumber: Int
    /// Horizontal pixel movement required to trigger a space switch (slow/drag gesture).
    var movementThreshold: CGFloat
    /// Instantaneous velocity (px/s) required to trigger a flick gesture.
    /// A flick fires immediately when this speed is reached; no need to travel the full
    /// movementThreshold distance.  Set to 0 to disable velocity detection.
    var velocityThreshold: CGFloat

    static let `default` = GestureConfig(
        enabled: false,
        deviceKey: nil,
        deviceName: nil,
        buttonNumber: 4,
        movementThreshold: 150,
        velocityThreshold: 800
    )
}

// MARK: - UserDefaults persistence

extension GestureConfig {
    private enum Key {
        static let enabled          = "gesture.enabled"
        static let deviceKey        = "gesture.deviceKey"
        static let devName          = "gesture.deviceName"
        static let button           = "gesture.button"
        static let threshold        = "gesture.threshold"
        static let velocityThreshold = "gesture.velocityThreshold"
    }

    static func load() -> GestureConfig {
        let d = UserDefaults.standard
        let btn = d.integer(forKey: Key.button)
        let thr = d.double(forKey: Key.threshold)
        let vel = d.double(forKey: Key.velocityThreshold)
        return GestureConfig(
            enabled:               d.bool(forKey: Key.enabled),
            deviceKey:             d.string(forKey: Key.deviceKey),
            deviceName:            d.string(forKey: Key.devName),
            buttonNumber:          btn > 0 ? btn : 4,
            movementThreshold:     thr > 0 ? CGFloat(thr) : 150,
            velocityThreshold:     vel > 0 ? CGFloat(vel) : 800
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(enabled,                    forKey: Key.enabled)
        d.set(deviceKey,                  forKey: Key.deviceKey)
        d.set(deviceName,                 forKey: Key.devName)
        d.set(buttonNumber,               forKey: Key.button)
        d.set(Double(movementThreshold),  forKey: Key.threshold)
        d.set(Double(velocityThreshold),  forKey: Key.velocityThreshold)
    }
}
