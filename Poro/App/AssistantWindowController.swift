import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
  private enum PanelPlacement: Equatable {
    case automatic
    case manual(topLeft: CGPoint)
  }

  private enum KeyboardMove {
    static let step: CGFloat = 24
  }

  private enum DefaultsKey {
    static let panelPlacementMode = "poro.panelPlacement.mode"
    static let panelPlacementX = "poro.panelPlacement.x"
    static let panelPlacementY = "poro.panelPlacement.y"
  }

  private let panel: FloatingAssistantPanel
  private let poroController: PoroController
  private var currentTotalHeight: CGFloat
  private var panelPlacement: PanelPlacement
  private var localKeyMonitor: Any?

  init(poroController: PoroController) {
    self.poroController = poroController
    currentTotalHeight = PoroTheme.collapsedTotalHeight
    panelPlacement = Self.loadPanelPlacement()

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

  deinit {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
  }

  func show() {
    poroController.prepareForPresentation()
    installKeyboardMonitorIfNeeded()
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

    removeKeyboardMonitor()
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
    let topLeft: CGPoint

    switch panelPlacement {
    case .automatic:
      topLeft = automaticTopLeft(in: screenFrame)
    case .manual(let storedTopLeft):
      topLeft = clampedTopLeft(storedTopLeft, in: screenFrame)
    }

    let y = topLeft.y - currentTotalHeight

    return NSRect(x: topLeft.x, y: y, width: PoroTheme.width, height: currentTotalHeight)
  }

  private func automaticTopLeft(in screenFrame: NSRect) -> CGPoint {
    CGPoint(
      x: screenFrame.midX - (PoroTheme.width / 2),
      y: screenFrame.maxY - (screenFrame.height * PoroTheme.topAnchorRatio)
    )
  }

  private func clampedTopLeft(_ topLeft: CGPoint, in screenFrame: NSRect) -> CGPoint {
    let minX = screenFrame.minX
    let maxX = screenFrame.maxX - PoroTheme.width
    let minTopY = screenFrame.minY + currentTotalHeight
    let maxTopY = screenFrame.maxY

    return CGPoint(
      x: min(max(topLeft.x, minX), maxX),
      y: min(max(topLeft.y, minTopY), maxTopY)
    )
  }

  private func installKeyboardMonitorIfNeeded() {
    guard localKeyMonitor == nil else {
      return
    }

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else {
        return event
      }

      return self.handleKeyboardEvent(event)
    }
  }

  private func removeKeyboardMonitor() {
    guard let localKeyMonitor else {
      return
    }

    NSEvent.removeMonitor(localKeyMonitor)
    self.localKeyMonitor = nil
  }

  private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
    guard panel.isVisible, event.window === panel else {
      return event
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    guard flags.contains(.command), flags.contains(.option) else {
      return event
    }

    switch event.keyCode {
    case 123:
      nudgePanel(dx: -KeyboardMove.step, dy: 0)
      return nil
    case 124:
      nudgePanel(dx: KeyboardMove.step, dy: 0)
      return nil
    case 125:
      nudgePanel(dx: 0, dy: -KeyboardMove.step)
      return nil
    case 126:
      nudgePanel(dx: 0, dy: KeyboardMove.step)
      return nil
    default:
      return event
    }
  }

  private func nudgePanel(dx: CGFloat, dy: CGFloat) {
    let currentFrame = panel.isVisible ? panel.frame : frameForCurrentState()
    let movedTopLeft = CGPoint(
      x: currentFrame.origin.x + dx,
      y: currentFrame.maxY + dy
    )

    panelPlacement = .manual(topLeft: movedTopLeft)
    persistPanelPlacement()

    let frame = frameForCurrentState()

    if panel.isVisible {
      panel.setFrame(frame, display: true, animate: false)
    } else {
      panel.setFrame(frame, display: true)
    }
  }

  private func persistPanelPlacement() {
    let defaults = UserDefaults.standard

    switch panelPlacement {
    case .automatic:
      defaults.set("automatic", forKey: DefaultsKey.panelPlacementMode)
      defaults.removeObject(forKey: DefaultsKey.panelPlacementX)
      defaults.removeObject(forKey: DefaultsKey.panelPlacementY)
    case .manual(let topLeft):
      defaults.set("manual", forKey: DefaultsKey.panelPlacementMode)
      defaults.set(topLeft.x, forKey: DefaultsKey.panelPlacementX)
      defaults.set(topLeft.y, forKey: DefaultsKey.panelPlacementY)
    }
  }

  private static func loadPanelPlacement() -> PanelPlacement {
    let defaults = UserDefaults.standard

    guard defaults.string(forKey: DefaultsKey.panelPlacementMode) == "manual" else {
      return .automatic
    }

    let x = defaults.double(forKey: DefaultsKey.panelPlacementX)
    let y = defaults.double(forKey: DefaultsKey.panelPlacementY)

    guard x != 0 || y != 0 else {
      return .automatic
    }

    return .manual(topLeft: CGPoint(x: x, y: y))
  }
}
