import AppKit
import SwiftUI

final class FloatingWindowController {
    static let shared = FloatingWindowController()
    private var window: NSWindow?

    func show(state: NetworkState) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = PopupContentView()
            .environmentObject(state)

        let controller = NSHostingController(rootView: content)
        let panel = NSPanel(
            contentViewController: controller
        )
        panel.title = "PingBar"
        panel.styleMask = [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.setFrameAutosaveName("PingBarFloatingWindow")
        panel.setContentSize(NSSize(width: 380, height: 760))
        panel.minSize = NSSize(width: 340, height: 560)
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = panel
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
