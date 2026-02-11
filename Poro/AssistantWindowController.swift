import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
    
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Poro"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.contentViewController = NSHostingController(rootView: ContentView())
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggleVisibility() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }
}
