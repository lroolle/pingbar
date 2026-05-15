import AppKit
import Foundation

struct NetworkProcessSample: Identifiable, Equatable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let downloadBytesPerSec: Int64
    let uploadBytesPerSec: Int64

    var totalBytesPerSec: Int64 {
        downloadBytesPerSec + uploadBytesPerSec
    }

    var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let icon = app.icon {
            return icon
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}
