import Foundation
import IOKit.hid

// MARK: - Data types

struct HIDMouseDevice {
    let uniqueKey: String   // "vendorID:productID:locationID"
    let name: String
    let vendorID: Int
    let productID: Int
    fileprivate let ref: IOHIDDevice
}

struct MouseButtonEvent {
    let device: HIDMouseDevice
    let button: Int         // 1-indexed: 1=left, 2=right, 3=middle, 4+=extra
    let pressed: Bool
    let timestamp: Date

    var buttonLabel: String {
        switch button {
        case 1: return "Button 1 (Left)"
        case 2: return "Button 2 (Right)"
        case 3: return "Button 3 (Middle)"
        default: return "Button \(button)"
        }
    }
}

// MARK: - Monitor

final class HIDMouseMonitor {
    typealias EventCallback = (MouseButtonEvent) -> Void

    private var hidManager: IOHIDManager?
    private var deviceEntries: [(ref: IOHIDDevice, device: HIDMouseDevice)] = []
    private(set) var devices: [HIDMouseDevice] = []
    private var callback: EventCallback?

    /// nil = all mice
    var filterDeviceKey: String?
    /// nil = all buttons
    var filterButton: Int?

    // MARK: Enumeration (one-shot, no persistent manager)

    func enumerateMice() -> [HIDMouseDevice] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, mouseMatchingDict())
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let cfSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        return cfSet.compactMap(makeDevice(from:)).sorted { $0.name < $1.name }
    }

    // MARK: Persistent monitoring

    func startMonitoring(callback: @escaping EventCallback) {
        guard hidManager == nil else { return }
        self.callback = callback
        deviceEntries = []
        devices = []

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, mouseMatchingDict())

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        // Called immediately for already-connected devices, then again as new ones connect
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, deviceRef in
            guard let ctx else { return }
            let monitor = Unmanaged<HIDMouseMonitor>.fromOpaque(ctx).takeUnretainedValue()
            guard let dev = monitor.makeDevice(from: deviceRef) else { return }
            guard !monitor.deviceEntries.contains(where: { CFEqual($0.ref, deviceRef) }) else { return }
            monitor.deviceEntries.append((ref: deviceRef, device: dev))
            monitor.devices = monitor.deviceEntries.map(\.device)
        }, ctx)

        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<HIDMouseMonitor>.fromOpaque(ctx).takeUnretainedValue().handleValue(value)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = mgr
    }

    func stopMonitoring() {
        guard let mgr = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        callback = nil
        deviceEntries = []
        devices = []
    }

    // MARK: - Private

    private func handleValue(_ value: IOHIDValue) {
        let elem = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(elem) == kHIDPage_Button else { return }

        let button  = Int(IOHIDElementGetUsage(elem))
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        let ref     = IOHIDElementGetDevice(elem)

        guard let entry = deviceEntries.first(where: { CFEqual($0.ref, ref) }) else { return }
        if let key = filterDeviceKey, entry.device.uniqueKey != key { return }
        if let btn = filterButton,    button != btn                  { return }

        let event = MouseButtonEvent(
            device: entry.device, button: button, pressed: pressed, timestamp: Date()
        )
        DispatchQueue.main.async { [weak self] in self?.callback?(event) }
    }

    private func mouseMatchingDict() -> CFDictionary {
        // kHIDPage_GenericDesktop = 0x01, kHIDUsage_GD_Mouse = 0x02
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
         kIOHIDDeviceUsageKey:     kHIDUsage_GD_Mouse] as [String: Any] as CFDictionary
    }

    private func makeDevice(from ref: IOHIDDevice) -> HIDMouseDevice? {
        let name = IOHIDDeviceGetProperty(ref, kIOHIDProductKey    as CFString) as? String ?? "Unknown Mouse"
        let vid  = IOHIDDeviceGetProperty(ref, kIOHIDVendorIDKey   as CFString) as? Int    ?? 0
        let pid  = IOHIDDeviceGetProperty(ref, kIOHIDProductIDKey  as CFString) as? Int    ?? 0
        let loc  = IOHIDDeviceGetProperty(ref, kIOHIDLocationIDKey as CFString) as? Int    ?? 0
        return HIDMouseDevice(
            uniqueKey: "\(vid):\(pid):\(loc)", name: name, vendorID: vid, productID: pid, ref: ref
        )
    }
}
