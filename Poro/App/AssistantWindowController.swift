import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
  private let panel: FloatingAssistantPanel
  private let poroController: PoroController
  private var currentTotalHeight: CGFloat

  init(poroController: PoroController) {
    self.poroController = poroController
    currentTotalHeight = PoroTheme.collapsedTotalHeight

    panel = FloatingAssistantPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: PoroTheme.width,
        height: currentTotalHeight
      ),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = false
    panel.contentViewController = NSHostingController(
      rootView: ContentView(
        poroController: poroController,
        onDismissRequest: { [weak self] in
          self?.hide(animated: true)
        },
        onPanelHeightChange: { [weak self] totalHeight in
          self?.setPanelHeight(totalHeight, animated: true)
        }
      )
    )

    poroController.onDismissRequested = { [weak self] in
      self?.hide(animated: true)
    }
    poroController.onPresentRequested = { [weak self] in
      self?.show()
    }

    applyFrame(animated: false)
    panel.orderOut(nil)
  }

  func show() {
    poroController.prepareForPresentation()
    let targetFrame = frameForCurrentState()
    var startFrame = targetFrame
    startFrame.origin.y += 8

    panel.alphaValue = 0
    panel.setFrame(startFrame, display: true)
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
      panel.animator().setFrame(targetFrame, display: true)
    } completionHandler: {
      NotificationCenter.default.post(name: .assistantWindowDidShow, object: nil)
    }
  }

  func hide(animated: Bool) {
    guard panel.isVisible else {
      return
    }

    let finalFrame = panel.frame.offsetBy(dx: 0, dy: 8)

    let finishHide = {
      self.panel.orderOut(nil)
      self.panel.alphaValue = 1
      self.panel.setFrame(self.frameForCurrentState(), display: false)
    }

    guard animated else {
      finishHide()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 0
      panel.animator().setFrame(finalFrame, display: true)
    } completionHandler: {
      finishHide()
    }
  }

  func toggleVisibility() {
    if panel.isVisible {
      hide(animated: true)
    } else {
      show()
    }
  }

  private func setPanelHeight(_ totalHeight: CGFloat, animated: Bool) {
    guard abs(currentTotalHeight - totalHeight) > 0.5 else {
      return
    }

    currentTotalHeight = totalHeight
    applyFrame(animated: animated)
  }

  private func applyFrame(animated: Bool) {
    let frame = frameForCurrentState()

    guard animated, panel.isVisible else {
      panel.setFrame(frame, display: true)
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
      panel.animator().setFrame(frame, display: true)
    }
  }

  private func frameForCurrentState() -> NSRect {
    let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let x = screenFrame.midX - (PoroTheme.width / 2)
    let top = screenFrame.maxY - (screenFrame.height * PoroTheme.topAnchorRatio)
    let y = top - currentTotalHeight

    return NSRect(x: x, y: y, width: PoroTheme.width, height: currentTotalHeight)
  }
}
