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
    private var settingsWindow: NSWindow?
    private var settingsWindowController: NSWindowController?
    private var stackedStatusView: StackedStatusItemView?
    private var currentStatusItemLength: CGFloat?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        state = NetworkState()

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let contentView = PopupContentView().environmentObject(state)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 760)
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

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit PingBar", action: #selector(quit), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func updateLabel() {
        guard let button = statusBarItem.button else { return }

        let config = state.config
        applyStatusItemLength(length(for: config))

        if config.menuBarStyle == .stacked {
            updateStackedStatusView(config: config)
            return
        }

        removeStackedStatusView()

        let dl = state.downloadBytesPerSec
        let ul = state.uploadBytesPerSec
        let health = state.health

        let text = NSMutableAttributedString()
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        if config.showHealthDot {
            let (dot, color) = healthIndicator(health)
            text.append(NSAttributedString(string: "\(dot) ", attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .baselineOffset: 0.5,
            ]))
        }

        let (dlVal, dlUnit) = Fmt.bytesPerSec(dl)

        switch config.menuBarStyle {
        case .stacked:
            break

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

    private func length(for config: AppConfig) -> CGFloat {
        switch config.menuBarStyle {
        case .stacked:
            return CGFloat(config.stackedMenuBarWidth)
        case .iconOnly:
            return 22
        case .compact, .detailed:
            return config.menuBarFixedWidth ? CGFloat(config.menuBarWidth) : NSStatusItem.variableLength
        }
    }

    private func applyStatusItemLength(_ length: CGFloat) {
        if let currentStatusItemLength, abs(currentStatusItemLength - length) < 0.5 { return }
        statusBarItem.length = length
        currentStatusItemLength = length
    }

    private func updateStackedStatusView(config: AppConfig) {
        guard let button = statusBarItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        let view: StackedStatusItemView
        if let stackedStatusView {
            view = stackedStatusView
        } else {
            let newView = StackedStatusItemView(frame: button.bounds)
            newView.autoresizingMask = [.width, .height]
            button.addSubview(newView)
            stackedStatusView = newView
            view = newView
        }

        view.frame = button.bounds
        view.update(
            upload: state.uploadBytesPerSec,
            download: state.downloadBytesPerSec,
            health: state.health,
            showsHealthDot: config.showHealthDot
        )
    }

    private func removeStackedStatusView() {
        stackedStatusView?.removeFromSuperview()
        stackedStatusView = nil
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

        let pinItem = NSMenuItem(title: "Pin Window", action: #selector(pinWindow), keyEquivalent: "p")
        pinItem.target = self
        menu.addItem(pinItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let networkItem = NSMenuItem(title: "Open Network Settings", action: #selector(openNetworkSettings), keyEquivalent: "")
        networkItem.target = self
        menu.addItem(networkItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PingBar", action: #selector(quit), keyEquivalent: "q")

        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
        statusBarItem.menu = nil
    }

    @objc func openSettings() {
        showSettingsWindow()
    }

    func showSettingsWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        if let settingsWindow {
            if settingsWindow.isMiniaturized {
                settingsWindow.deminiaturize(nil)
            }
            settingsWindowController?.showWindow(nil)
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKeyAndOrderFront(nil)
            activateSettingsWindow()
            return
        }

        NSApp.setActivationPolicy(.accessory)
        let settingsView = SettingsView().environmentObject(state)
        let controller = NSHostingController(rootView: settingsView)
        let window = NSPanel(contentViewController: controller)
        window.title = "PingBar Settings"
        window.styleMask = [.titled, .closable, .resizable, .utilityWindow]
        window.setContentSize(NSSize(width: 780, height: 540))
        window.minSize = NSSize(width: 700, height: 480)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        settingsWindow = window
        windowController.showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        activateSettingsWindow()
    }

    private func activateSettingsWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        NSApp.terminate(self)
    }

    @objc func openNetworkSettings() {
        SystemSettings.openNetwork()
    }

    @objc func pinWindow() {
        popover.performClose(nil)
        FloatingWindowController.shared.show(state: state)
    }
}
