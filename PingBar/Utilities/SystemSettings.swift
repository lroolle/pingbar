import AppKit

enum SystemSettings {
    static func openNetwork() {
        open([
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network",
        ])
    }

    static func openWiFi() {
        open([
            "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
            "x-apple.systempreferences:com.apple.preference.network?Wi-Fi",
        ])
    }

    private static func open(_ urls: [String]) {
        for raw in urls {
            guard let url = URL(string: raw), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }
}
