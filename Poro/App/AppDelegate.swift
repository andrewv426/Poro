import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var poroController: PoroController?
  private var assistantWindowController: AssistantWindowController?
  private var statusItemController: StatusItemController?
  private var nudgeWindowController: NudgeWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let poroController = PoroController()
    self.poroController = poroController

    assistantWindowController = AssistantWindowController(poroController: poroController)

    if let focusSessionController = self.poroController?.focusSessionController {
      statusItemController = StatusItemController(
        focusSessionController: focusSessionController
      ) { [weak self] in
        Task { @MainActor in
          self?.assistantWindowController?.show()
        }
      }

      nudgeWindowController = NudgeWindowController(
        focusSessionController: focusSessionController
      )
    }

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
