import AppKit
import KeyboardShortcuts
//Object getting lifecycle callbacks from macOS
//Allows us to respond to OS level events such as app launching, closing ,etc
final class AppDelegate: NSObject, NSApplicationDelegate {
    //assistatWindowController allows us to toggle visibility
    private var assistantWindowController: AssistantWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        assistantWindowController = AssistantWindowController()
        assistantWindowController?.show()

        KeyboardShortcuts.setShortcut(
            .init(.t, modifiers: [.command, .option]),
            for: .toggleAssistantWindow
        )

        KeyboardShortcuts.onKeyUp(for: .toggleAssistantWindow) { [weak self] in
            Task { @MainActor in
                self?.assistantWindowController?.toggleVisibility()
            }
        }
    }
}
