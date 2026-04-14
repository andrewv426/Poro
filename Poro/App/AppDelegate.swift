import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var assistantWindowController: AssistantWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    assistantWindowController = AssistantWindowController()

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
