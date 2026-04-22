import AppKit
import SwiftUI

@MainActor
final class NudgeWindowController {
  private let panel: FloatingAssistantPanel
  private let focusSessionController: FocusSessionController

  init(focusSessionController: FocusSessionController) {
    self.focusSessionController = focusSessionController
    panel = FloatingAssistantPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 190),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.contentViewController = NSHostingController(
      rootView: FocusNudgeView(focusSessionController: focusSessionController)
    )
    panel.orderOut(nil)

    focusSessionController.onNudgeChange = { [weak self] nudge in
      if nudge == nil {
        self?.hide()
      } else {
        self?.show()
      }
    }
  }

  func show() {
    guard let screenFrame = NSScreen.main?.visibleFrame else {
      panel.orderFrontRegardless()
      return
    }

    let width: CGFloat = 340
    let height: CGFloat = 190
    let x = screenFrame.maxX - width - 20
    let y = screenFrame.maxY - height - 32
    panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    panel.alphaValue = 1
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }
}
