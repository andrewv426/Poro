import AppKit
import CoreText
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var poroController: PoroController?
  private var assistantWindowController: AssistantWindowController?
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_: Notification) {
    registerBundledFonts()

    let poroController = PoroController()
    self.poroController = poroController

    assistantWindowController = AssistantWindowController(poroController: poroController)

    if let focusSessionController = self.poroController?.focusSessionController {
      statusItemController = StatusItemController(
        focusSessionController: focusSessionController
      ) { [weak self] in
        Task { @MainActor in
          self?.assistantWindowController?.showFocusPanel()
        }
      }
    }

    if KeyboardShortcuts.getShortcut(for: .toggleAssistantWindow) == nil {
      KeyboardShortcuts.setShortcut(
        .init(.t, modifiers: [.command, .option]),
        for: .toggleAssistantWindow
      )
    }

    KeyboardShortcuts.onKeyUp(for: .toggleAssistantWindow) { [weak self] in
      Task { @MainActor in
        self?.assistantWindowController?.toggleVisibility()
      }
    }
  }

  private func registerBundledFonts() {
    let names = ["RadioCanada-Regular", "RadioCanada-Medium", "RadioCanada-SemiBold", "RadioCanada-Bold"]
    for name in names {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}
