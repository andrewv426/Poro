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
    AppearanceController.shared.onPresetChange = { [weak self] in
      self?.update()
    }
    update()
  }

  func update() {
    let isVisible = focusSessionController.hasActiveSession
    statusItem.isVisible = isVisible
    guard let button = statusItem.button else { return }

    let text = focusSessionController.statusItemText ?? ""
    button.attributedTitle = NSAttributedString(
      string: text,
      attributes: [
        .foregroundColor: AppearanceController.shared.preset.nsAccent,
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
      ]
    )
  }

  @objc private func handleActivate() {
    onActivate()
  }
}
