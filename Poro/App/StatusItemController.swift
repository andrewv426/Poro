import AppKit

@MainActor
final class StatusItemController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let focusSessionController: FocusSessionController
  private let onActivate: () -> Void

  init(focusSessionController: FocusSessionController, onActivate: @escaping () -> Void) {
    self.focusSessionController = focusSessionController
    self.onActivate = onActivate

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(handleActivate)
      button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    statusItem.isVisible = false
    focusSessionController.onStatusItemUpdate = { [weak self] in
      self?.update()
    }
    update()
  }

  func update() {
    let isVisible = focusSessionController.hasActiveSession
    statusItem.isVisible = isVisible
    statusItem.button?.title = focusSessionController.statusItemText ?? ""
  }

  @objc private func handleActivate() {
    onActivate()
  }
}
