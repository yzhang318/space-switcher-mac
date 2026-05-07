import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    private var mouseInterceptor: MouseInterceptor?    // stub — see MouseInterceptor.swift
    private var gestureEngine: GestureEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app — no Dock icon, no app switcher entry
        NSApp.setActivationPolicy(.accessory)

        let engine = GestureEngine(config: .load())
        gestureEngine = engine
        engine.start()

        statusBarController = StatusBarController(gestureEngine: engine)
        mouseInterceptor = MouseInterceptor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureEngine?.stop()
        mouseInterceptor?.stop()
    }
}
