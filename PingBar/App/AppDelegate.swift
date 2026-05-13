import Cocoa
import SwiftUI
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var state: NetworkState!
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        state = NetworkState()

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let contentView = PopupContentView().environmentObject(state)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        if let button = statusBarItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        state.objectWillChange
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLabel() }
            }
            .store(in: &cancellables)

        updateLabel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func updateLabel() {
        guard let button = statusBarItem.button else { return }

        let config = state.config
        let dl = state.downloadBytesPerSec
        let ul = state.uploadBytesPerSec
        let health = state.health

        let text = NSMutableAttributedString()
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        if config.showHealthDot {
            let (dot, color) = healthIndicator(health)
            text.append(NSAttributedString(string: "\(dot) ", attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 9),
            ]))
        }

        let (dlVal, dlUnit) = Fmt.bytesPerSec(dl)

        switch config.menuBarStyle {
        case .compact:
            if config.showUploadInMenuBar {
                let (ulVal, ulUnit) = Fmt.bytesPerSec(ul)
                text.append(styled("↑\(ulVal)\(ulUnit) ↓\(dlVal)\(dlUnit)", font: mono))
            } else {
                text.append(styled("↓\(dlVal)\(dlUnit)", font: mono))
            }

        case .detailed:
            let (ulVal, ulUnit) = Fmt.bytesPerSec(ul)
            var detail = "↑\(ulVal)\(ulUnit) ↓\(dlVal)\(dlUnit)"
            if let gw = state.cachedGateway, let ping = state.pingResults[gw], let ms = ping.latencyMs {
                detail += " \(Int(ms))ms"
            }
            text.append(styled(detail, font: mono))

        case .iconOnly:
            break
        }

        button.attributedTitle = text
    }

    private func healthIndicator(_ health: NetworkHealth) -> (String, NSColor) {
        switch health {
        case .good:     return ("●", .systemGreen)
        case .degraded: return ("●", .systemYellow)
        case .poor:     return ("●", .systemRed)
        case .unknown:  return ("○", .secondaryLabelColor)
        }
    }

    private func styled(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.controlTextColor,
        ])
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            if popover.isShown {
                popover.performClose(sender)
            } else if let button = statusBarItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PingBar", action: #selector(quit), keyEquivalent: "q")

        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
        statusBarItem.menu = nil
    }

    @objc func openSettings() {
        let settingsView = SettingsView().environmentObject(state)
        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "PingBar Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 320))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        NSApp.terminate(self)
    }
}
