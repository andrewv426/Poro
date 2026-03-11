import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
    //NSPanel is built on top of NSWindow ; designed for floating utility based ui
    private let panel: NSPanel

    init() {
        
        panel = NSPanel(
            //creates panel ; with size
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            //type of window controls (i.e exit buttons, resize, etc.)
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
    
    
    //Visibility toggles
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
