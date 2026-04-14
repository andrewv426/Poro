import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
  private let panel: FloatingAssistantPanel
  private let chatController = ChatController()
  private var isExpanded = false

  init() {
    panel = FloatingAssistantPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: PoroTheme.width,
        height: PoroTheme.collapsedTotalHeight
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
        chatController: chatController,
        onDismissRequest: { [weak self] in
          self?.hide(animated: true)
        },
        onExpansionChange: { [weak self] expanded in
          self?.setExpanded(expanded, animated: true)
        }
      )
    )

    applyFrame(animated: false)
    panel.orderOut(nil)
  }

  func show() {
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

  private func setExpanded(_ expanded: Bool, animated: Bool) {
    guard isExpanded != expanded else {
      return
    }

    isExpanded = expanded
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
    let height = isExpanded ? PoroTheme.expandedSurfaceHeight : PoroTheme.collapsedTotalHeight
    let x = screenFrame.midX - (PoroTheme.width / 2)
    let top = screenFrame.maxY - (screenFrame.height * PoroTheme.topAnchorRatio)
    let y = top - height

    return NSRect(x: x, y: y, width: PoroTheme.width, height: height)
  }
}
