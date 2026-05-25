import Cocoa
import SwiftUI
import Combine

private struct MenuBarEgressIdentity {
    let id: String
    let label: String
    let route: String
    let endpoint: PublicEndpointInfo?
    let isHealthy: Bool
}

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
        popover.contentSize = NSSize(width: 380, height: 820)
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

    func applicationWillTerminate(_ notification: Notification) {
        state?.flushTrafficUsage()
        state?.flushNetworkMetrics()
    }

    private func updateLabel() {
        guard let button = statusBarItem.button else { return }

        let config = state.config
        applyStatusItemLength(length(for: config))

        if config.menuBarStyle == .stacked {
            updateStackedStatusView(config: config)
            return
        }

        removeStackedStatusView()

        let text = NSMutableAttributedString()
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        if config.showHealthDot {
            let (dot, color) = healthIndicator(state.health)
            text.append(NSAttributedString(string: "\(dot) ", attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .baselineOffset: 0.5,
            ]))
        }

        switch config.menuBarStyle {
        case .stacked:
            break

        case .compact, .detailed:
            text.append(styled(clippedMenuBarTitle(config: config), font: mono))

        case .iconOnly:
            break
        }

        button.attributedTitle = text
    }

    private func length(for config: AppConfig) -> CGFloat {
        switch config.menuBarStyle {
        case .stacked:
            let minimumWidth = config.menuBarContentMode == .hybrid ? 184 : 96
            return CGFloat(max(config.stackedMenuBarWidth, Double(minimumWidth)))
        case .iconOnly:
            return 22
        case .compact, .detailed:
            guard config.menuBarContentMode == .speed else { return NSStatusItem.variableLength }
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
        if config.menuBarStyle == .stacked, config.menuBarContentMode == .hybrid {
            view.update(
                leading: speedStatusLines(config: config),
                trailing: egressIdentityLines(config: config),
                health: state.health,
                showsHealthDot: config.showHealthDot
            )
            return
        }

        view.update(
            lines: stackedMenuBarLines(config: config),
            health: state.health,
            showsHealthDot: config.showHealthDot,
            layout: .rows
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

    private func clippedMenuBarTitle(config: AppConfig) -> String {
        let title = menuBarTitle(config: config, detailed: config.menuBarStyle == .detailed)
        guard title.count > 30 else { return title }
        return "\(title.prefix(29))…"
    }

    private func menuBarTitle(config: AppConfig, detailed: Bool) -> String {
        switch config.menuBarContentMode {
        case .speed:
            return speedMenuBarTitle(config: config, includeGateway: detailed)
        case .egress:
            return egressIdentityTitle(config: config, detailed: detailed)
        case .hybrid:
            return "\(downloadMenuBarTitle()) \(egressIdentityTitle(config: config, detailed: false))"
        }
    }

    private func speedMenuBarTitle(config: AppConfig, includeGateway: Bool) -> String {
        let (dlVal, dlUnit) = Fmt.bytesPerSec(state.downloadBytesPerSec)
        var title: String
        if config.showUploadInMenuBar {
            let (ulVal, ulUnit) = Fmt.bytesPerSec(state.uploadBytesPerSec)
            title = "↑\(ulVal)\(ulUnit) ↓\(dlVal)\(dlUnit)"
        } else {
            title = "↓\(dlVal)\(dlUnit)"
        }

        if includeGateway,
           let gw = state.cachedGateway,
           let ping = state.pingResults[gw],
           let ms = ping.latencyMs {
            title += " \(Int(ms))ms"
        }
        return title
    }

    private func downloadMenuBarTitle() -> String {
        let (dlVal, dlUnit) = Fmt.bytesPerSec(state.downloadBytesPerSec)
        return "↓\(dlVal)\(dlUnit)"
    }

    private func stackedMenuBarLines(config: AppConfig) -> [StatusItemLine] {
        switch config.menuBarContentMode {
        case .speed:
            return speedStatusLines(config: config)
        case .egress:
            return egressIdentityLines(config: config)
        case .hybrid:
            return [
                StatusItemLine(symbol: "↓", text: speedValue(state.downloadBytesPerSec), color: .systemGreen),
                egressIdentityLines(config: config).first ?? StatusItemLine(symbol: "@", text: "Egress --", color: .secondaryLabelColor),
            ]
        }
    }

    private func speedStatusLines(config: AppConfig) -> [StatusItemLine] {
        if config.showUploadInMenuBar {
            return [
                StatusItemLine(symbol: "↑", text: speedValue(state.uploadBytesPerSec), color: .systemBlue),
                StatusItemLine(symbol: "↓", text: speedValue(state.downloadBytesPerSec), color: .systemGreen),
            ]
        }
        return [
            StatusItemLine(symbol: "↓", text: speedValue(state.downloadBytesPerSec), color: .systemGreen),
        ]
    }

    private func speedValue(_ bytes: Int64) -> String {
        let (value, unit) = Fmt.bytesPerSec(bytes)
        return "\(value)\(unit)"
    }

    private func egressIdentityTitle(config: AppConfig, detailed: Bool) -> String {
        guard let identity = selectedEgressIdentity(config: config) else { return "Egress --" }
        return detailed
            ? "\(egressIdentityTop(identity, config: config)) \(egressIdentityBottom(identity, config: config))"
            : "\(egressIdentityTop(identity, config: config)) \(egressIdentityBottom(identity, config: config, compact: true))"
    }

    private func egressIdentityLines(config: AppConfig) -> [StatusItemLine] {
        guard let identity = selectedEgressIdentity(config: config) else {
            return [
                StatusItemLine(symbol: "@", text: "Egress --", color: .secondaryLabelColor),
                StatusItemLine(symbol: "IP", text: "--", color: .secondaryLabelColor),
            ]
        }

        return [
            StatusItemLine(symbol: "@", text: egressIdentityTop(identity, config: config), color: egressIdentityColor(identity)),
            StatusItemLine(symbol: ipFamilySymbol(identity.endpoint?.ip), text: egressIdentityBottom(identity, config: config), color: .secondaryLabelColor),
        ]
    }

    private func selectedEgressIdentity(config: AppConfig) -> MenuBarEgressIdentity? {
        let identities = egressIdentities(config: config)
        if !config.menuBarEgressSourceID.isEmpty,
           let selected = identities.first(where: { $0.id == config.menuBarEgressSourceID }) {
            return selected
        }
        if let selectedTrace = identities.first(where: { $0.id.hasPrefix("trace:") && $0.isHealthy }) {
            return selectedTrace
        }
        return identities.first(where: { $0.id == "route:system-settings" }) ?? identities.first
    }

    private func egressIdentities(config: AppConfig) -> [MenuBarEgressIdentity] {
        let routeIdentities = state.egressRoutes.map { route in
            MenuBarEgressIdentity(
                id: "route:\(route.id)",
                label: route.label,
                route: route.detail ?? "route probe",
                endpoint: route.endpoint,
                isHealthy: route.endpoint != nil
            )
        }

        let resultsByID = state.egressTraceResults.reduce(into: [String: EgressTraceResult]()) { results, result in
            results[result.id] = result
        }
        let traceIdentities = config.egressTraceTargets.filter(\.enabled).map { target in
            let result = resultsByID[target.id]
            return MenuBarEgressIdentity(
                id: "trace:\(target.id)",
                label: target.displayName,
                route: "\(target.route.label) app edge",
                endpoint: result?.endpoint,
                isHealthy: result?.isHealthy == true
            )
        }

        return routeIdentities + traceIdentities
    }

    private func egressIdentityTop(_ identity: MenuBarEgressIdentity, config: AppConfig) -> String {
        guard let endpoint = identity.endpoint else { return "\(shortTraceName(identity.label)) --" }
        var parts: [String] = []
        if config.menuBarTraceShowDestination {
            parts.append(shortTraceName(identity.label))
        }
        if config.menuBarTraceShowFlag, let flag = endpoint.flagEmoji {
            parts.append(flag)
        }
        if config.menuBarTraceShowCountryCode, let country = endpoint.countryCode {
            parts.append(country)
        }
        if config.menuBarTraceShowColo, let colo = endpoint.colo, !colo.isEmpty {
            parts.append(colo)
        }
        return parts.isEmpty ? shortTraceName(identity.label) : parts.joined(separator: " ")
    }

    private func egressIdentityBottom(_ identity: MenuBarEgressIdentity, config: AppConfig, compact: Bool = false) -> String {
        guard let endpoint = identity.endpoint else { return identity.route }
        var parts = [
            displayIP(endpoint.ip, masked: config.menuBarTraceMaskIP, compact: compact || config.menuBarTraceCompact)
        ]
        if config.menuBarTraceShowWarp, let warp = endpoint.warp, warp == "on" || warp == "plus" {
            parts.append(warp == "plus" ? "WARP+" : "WARP")
        }
        if !compact || !config.menuBarTraceCompact {
            if config.menuBarTraceShowGateway, let gateway = endpoint.gatewayLabel {
                parts.append(gateway)
            }
            if config.menuBarTraceShowHTTP, let http = endpoint.httpProtocol, !http.isEmpty {
                parts.append(http)
            }
        }
        return parts.joined(separator: " ")
    }

    private func egressIdentityColor(_ identity: MenuBarEgressIdentity) -> NSColor {
        identity.isHealthy ? .systemBlue : .systemOrange
    }

    private func ipFamilySymbol(_ ip: String?) -> String {
        guard let ip else { return "IP" }
        return ip.contains(":") ? "v6" : "v4"
    }

    private func shortTraceName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: " Trace", with: "")
            .replacingOccurrences(of: " Direct", with: "D")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 10 else { return cleaned }
        return String(cleaned.prefix(10))
    }

    private func displayIP(_ ip: String, masked: Bool, compact: Bool) -> String {
        if masked { return maskedIP(ip) }
        guard compact, ip.contains(":") else { return ip }
        let parts = ip.split(separator: ":", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        guard let first = parts.first, let last = parts.last, first != last else { return ip }
        return "\(first):...\(last)"
    }

    private func maskedIP(_ ip: String) -> String {
        if ip.contains(":") {
            let parts = ip.split(separator: ":", omittingEmptySubsequences: false).filter { !$0.isEmpty }
            guard !parts.isEmpty else { return "IPv6 ..." }
            return "\(parts.prefix(2).joined(separator: ":")):..."
        }

        let parts = ip.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return "IP ..." }
        return "\(parts[0]).\(parts[1]).x.x"
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
        window.setContentSize(NSSize(width: 820, height: 600))
        window.minSize = NSSize(width: 760, height: 520)
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
