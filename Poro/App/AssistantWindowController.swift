import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController {
  private enum FocusPanelMode {
    case hidden
    case tucked
    case expanded
  }

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
    static let focusTabTopRatio = "poro.focusPanel.tabTopRatio"
  }

  private enum Tab {
    static let topRatio: CGFloat = 0.30
  }

  private let normalPanel: FloatingAssistantPanel
  private let focusPanel: FloatingAssistantPanel
  private let poroController: PoroController
  private var normalTotalHeight: CGFloat
  private var focusTotalHeight: CGFloat
  private var panelPlacement: PanelPlacement
  private var focusTabTopRatio: CGFloat
  private var focusTabDragMouseOffsetY: CGFloat?
  private var localKeyMonitor: Any?
  private var focusMode: FocusPanelMode = .hidden {
    didSet { poroController.isFocusPanelTucked = (focusMode == .tucked) }
  }

  init(poroController: PoroController) {
    self.poroController = poroController
    normalTotalHeight = PoroTheme.collapsedTotalHeight
    focusTotalHeight = PoroTheme.tabHeight
    panelPlacement = Self.loadPanelPlacement()
    focusTabTopRatio = Self.loadFocusTabTopRatio()

    normalPanel = Self.makePanel(
      width: PoroTheme.width,
      height: normalTotalHeight
    )
    focusPanel = Self.makePanel(
      width: PoroTheme.focusWidth,
      height: focusTotalHeight
    )

    normalPanel.contentViewController = NSHostingController(
      rootView: ContentView(
        poroController: poroController,
        context: .normal,
        onDismissRequest: { [weak self] in
          self?.hideNormal(animated: true)
        },
        onPanelHeightChange: { [weak self] totalHeight in
          self?.setNormalPanelHeight(totalHeight, animated: true)
        }
      )
    )

    focusPanel.contentViewController = NSHostingController(
      rootView: ContentView(
        poroController: poroController,
        context: .focus,
        onDismissRequest: { [weak self] in
          self?.tuckFocus(animated: true)
        },
        onPanelHeightChange: { [weak self] totalHeight in
          self?.setFocusPanelHeight(totalHeight, animated: true)
        },
        onFocusTabDragChanged: { [weak self] in
          self?.dragFocusTab()
        },
        onFocusTabDragEnded: { [weak self] in
          self?.finishDraggingFocusTab()
        }
      )
    )

    poroController.onDismissRequested = { [weak self] in
      self?.hideNormal(animated: true)
    }
    poroController.onPresentRequested = { [weak self] in
      self?.showFocusPanel(animated: true)
    }
    poroController.focusSessionController.onSessionStateChange = { [weak self] in
      self?.handleSessionStateChange()
    }
    poroController.focusSessionController.onDistractionDetected = { [weak self] activity in
      self?.handleDistractionDetected(activity: activity)
    }
    poroController.focusSessionController.onDistractionResolved = { [weak self] in
      self?.handleDistractionResolved()
    }

    applyNormalFrame(animated: false)
    applyFocusFrame(animated: false)
    normalPanel.orderOut(nil)
    focusPanel.orderOut(nil)
  }

  deinit {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
  }

  // MARK: - Public interface

  func show() {
    showNormal()
  }

  func showFocusPanel(animated: Bool = true) {
    focusMode = .expanded
    poroController.prepareForPresentation(in: .focus)
    focusTotalHeight = expectedTotalHeight(for: .focus)

    let targetFrame = focusExpandedFrame()
    focusPanel.setFrame(targetFrame.offsetBy(dx: -20, dy: 0), display: true)
    focusPanel.alphaValue = animated ? 0 : 1
    focusPanel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    guard animated else {
      NotificationCenter.default.post(name: .focusAssistantWindowDidShow, object: nil)
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
      focusPanel.animator().alphaValue = 1
      focusPanel.animator().setFrame(targetFrame, display: true)
    } completionHandler: {
      NotificationCenter.default.post(name: .focusAssistantWindowDidShow, object: nil)
    }
  }

  func hide(animated: Bool) {
    hideNormal(animated: animated)
  }

  func toggleVisibility() {
    if normalPanel.isVisible {
      hideNormal(animated: true)
    } else {
      showNormal()
    }
  }

  // MARK: - Session state changes

  private func handleSessionStateChange() {
    let sessionActive = poroController.focusSessionController.hasActiveSession

    if sessionActive {
      if focusMode == .hidden {
        hideNormal(animated: false)
        enterFocusTuckedMode()
      }
    } else if poroController.focusSessionController.latestSummary == nil {
      hideFocusCompletely(animated: true)
    }
  }

  private func handleDistractionDetected(activity: ActivityContext) {
    poroController.injectDistractionMessage(activity: activity)
    showFocusPanel(animated: true)
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(30))
      self?.poroController.focusSessionController.clearDistractionState()
    }
  }

  private func handleDistractionResolved() {
    guard poroController.focusSessionController.hasActiveSession else { return }
    tuckFocus(animated: true)
  }

  // MARK: - Normal panel

  private func showNormal() {
    poroController.prepareForPresentation(in: .normal)
    normalTotalHeight = expectedTotalHeight(for: .normal)
    installKeyboardMonitorIfNeeded()

    let targetFrame = normalFrame()
    var startFrame = targetFrame
    startFrame.origin.y += 8

    normalPanel.alphaValue = 0
    normalPanel.setFrame(startFrame, display: true)
    normalPanel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      normalPanel.animator().alphaValue = 1
      normalPanel.animator().setFrame(targetFrame, display: true)
    } completionHandler: {
      NotificationCenter.default.post(name: .normalAssistantWindowDidShow, object: nil)
    }
  }

  private func hideNormal(animated: Bool) {
    guard normalPanel.isVisible else { return }

    let finalFrame = normalPanel.frame.offsetBy(dx: 0, dy: 8)
    let finish = {
      self.normalPanel.orderOut(nil)
      self.normalPanel.alphaValue = 1
      self.normalPanel.setFrame(self.normalFrame(), display: false)
      self.removeKeyboardMonitor()
    }

    guard animated else {
      finish()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      normalPanel.animator().alphaValue = 0
      normalPanel.animator().setFrame(finalFrame, display: true)
    } completionHandler: {
      finish()
    }
  }

  // MARK: - Focus panel

  private func tuckFocus(animated: Bool) {
    guard poroController.focusSessionController.hasActiveSession else {
      hideFocusCompletely(animated: animated)
      return
    }

    focusMode = .tucked
    let targetFrame = focusTuckedFrame()

    guard animated, focusPanel.isVisible else {
      focusPanel.setFrame(targetFrame, display: true)
      focusPanel.alphaValue = 1
      focusPanel.orderFrontRegardless()
      return
    }

    focusPanel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      focusPanel.animator().setFrame(targetFrame, display: true)
    }
  }

  private func enterFocusTuckedMode() {
    focusMode = .tucked
    focusPanel.setFrame(focusTuckedFrame(), display: true)
    focusPanel.alphaValue = 1
    focusPanel.orderFrontRegardless()
  }

  private func hideFocusCompletely(animated: Bool) {
    focusMode = .hidden

    guard focusPanel.isVisible else { return }

    let finalFrame = focusPanel.frame.offsetBy(dx: -20, dy: 0)
    let finish = {
      self.focusPanel.orderOut(nil)
      self.focusPanel.alphaValue = 1
      self.focusPanel.setFrame(self.focusTuckedFrame(), display: false)
    }

    guard animated else {
      finish()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      focusPanel.animator().alphaValue = 0
      focusPanel.animator().setFrame(finalFrame, display: true)
    } completionHandler: {
      finish()
    }
  }

  // MARK: - Frame calculations

  private func focusTuckedFrame() -> NSRect {
    guard let screen = focusPanel.screen ?? NSScreen.main else { return .zero }
    let sf = screen.frame
    let topY = focusTopY(in: sf, height: PoroTheme.focusExpandedSurfaceHeight)
    let y = topY - PoroTheme.tabHeight
    let x = sf.minX - (PoroTheme.focusWidth - PoroTheme.tabVisibleWidth)

    return NSRect(x: x, y: y, width: PoroTheme.focusWidth, height: PoroTheme.tabHeight)
  }

  private func focusExpandedFrame() -> NSRect {
    guard let screen = focusPanel.screen ?? NSScreen.main else { return .zero }
    let sf = screen.frame
    let topY = focusTopY(in: sf, height: focusTotalHeight)
    let y = topY - focusTotalHeight

    return NSRect(x: sf.minX, y: y, width: PoroTheme.focusWidth, height: focusTotalHeight)
  }

  private func focusTopY(in screenFrame: NSRect, height: CGFloat) -> CGFloat {
    let unclampedTopY = screenFrame.maxY - (screenFrame.height * focusTabTopRatio)
    return clampedFocusTopY(unclampedTopY, in: screenFrame, height: height)
  }

  private func clampedFocusTopY(_ topY: CGFloat, in screenFrame: NSRect, height: CGFloat) -> CGFloat {
    let minTopY = screenFrame.minY + height
    let maxTopY = screenFrame.maxY
    return min(max(topY, minTopY), maxTopY)
  }

  private func normalFrame() -> NSRect {
    let screenFrame = normalPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let topLeft: CGPoint = switch panelPlacement {
    case .automatic:
      automaticTopLeft(in: screenFrame)
    case let .manual(storedTopLeft):
      clampedTopLeft(storedTopLeft, in: screenFrame)
    }

    return NSRect(
      x: topLeft.x,
      y: topLeft.y - normalTotalHeight,
      width: PoroTheme.width,
      height: normalTotalHeight
    )
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
    let minTopY = screenFrame.minY + normalTotalHeight
    let maxTopY = screenFrame.maxY

    return CGPoint(
      x: min(max(topLeft.x, minX), maxX),
      y: min(max(topLeft.y, minTopY), maxTopY)
    )
  }

  // MARK: - Height changes

  private func setNormalPanelHeight(_ totalHeight: CGFloat, animated: Bool) {
    guard abs(normalTotalHeight - totalHeight) > 0.5 else { return }
    normalTotalHeight = totalHeight
    applyNormalFrame(animated: animated)
  }

  private func setFocusPanelHeight(_ totalHeight: CGFloat, animated: Bool) {
    guard abs(focusTotalHeight - totalHeight) > 0.5 else { return }
    focusTotalHeight = totalHeight
    applyFocusFrame(animated: animated)
  }

  private func applyNormalFrame(animated: Bool) {
    let frame = normalFrame()
    guard animated, normalPanel.isVisible else {
      normalPanel.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
      normalPanel.animator().setFrame(frame, display: true)
    }
  }

  private func applyFocusFrame(animated: Bool) {
    let frame = focusMode == .tucked ? focusTuckedFrame() : focusExpandedFrame()
    guard animated, focusPanel.isVisible else {
      focusPanel.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
      focusPanel.animator().setFrame(frame, display: true)
    }
  }

  private func expectedTotalHeight(for context: AssistantPanelContext) -> CGFloat {
    if context == .focus, poroController.isFocusPanelTucked {
      return PoroTheme.tabHeight
    }

    let focus = context == .focus
    switch poroController.route(for: context) {
    case .chat:
      if poroController.isChatExpanded(in: context) {
        return focus ? PoroTheme.focusExpandedSurfaceHeight : PoroTheme.expandedSurfaceHeight
      }
      return focus ? PoroTheme.focusCollapsedTotalHeight : PoroTheme.collapsedTotalHeight
    case .focusSetup:
      return PoroTheme.focusSetupHeight
    case .summary:
      return PoroTheme.summaryHeight
    }
  }

  // MARK: - Keyboard monitor

  private func installKeyboardMonitorIfNeeded() {
    guard localKeyMonitor == nil else { return }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      return handleKeyboardEvent(event)
    }
  }

  private func removeKeyboardMonitor() {
    guard let localKeyMonitor else { return }
    NSEvent.removeMonitor(localKeyMonitor)
    self.localKeyMonitor = nil
  }

  private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
    guard shouldHandleNormalPanelMove(event) else { return event }

    switch event.keyCode {
    case 123: nudgeNormalPanel(dx: -KeyboardMove.step, dy: 0); return nil
    case 124: nudgeNormalPanel(dx: KeyboardMove.step, dy: 0); return nil
    case 125: nudgeNormalPanel(dx: 0, dy: -KeyboardMove.step); return nil
    case 126: nudgeNormalPanel(dx: 0, dy: KeyboardMove.step); return nil
    default: return event
    }
  }

  private func shouldHandleNormalPanelMove(_ event: NSEvent) -> Bool {
    guard
      normalPanel.isVisible,
      normalPanel.isKeyWindow,
      event.window === normalPanel
    else {
      return false
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command), flags.contains(.option) else {
      return false
    }

    return [123, 124, 125, 126].contains(event.keyCode)
  }

  private func nudgeNormalPanel(dx: CGFloat, dy: CGFloat) {
    let currentFrame = normalPanel.isVisible ? normalPanel.frame : normalFrame()
    let movedTopLeft = CGPoint(
      x: currentFrame.origin.x + dx,
      y: currentFrame.maxY + dy
    )
    panelPlacement = .manual(topLeft: movedTopLeft)
    persistPanelPlacement()
    normalPanel.setFrame(normalFrame(), display: true, animate: false)
  }

  private func dragFocusTab() {
    guard focusMode == .tucked, let screen = focusPanel.screen ?? NSScreen.main else { return }

    let screenFrame = screen.frame
    let mouseY = NSEvent.mouseLocation.y

    if focusTabDragMouseOffsetY == nil {
      focusTabDragMouseOffsetY = focusPanel.frame.maxY - mouseY
    }

    let proposedTopY = mouseY + (focusTabDragMouseOffsetY ?? 0)
    let clampedTopY = clampedFocusTopY(
      proposedTopY,
      in: screenFrame,
      height: PoroTheme.focusExpandedSurfaceHeight
    )
    focusTabTopRatio = (screenFrame.maxY - clampedTopY) / screenFrame.height
    focusPanel.setFrame(focusTuckedFrame(), display: true, animate: false)
  }

  private func finishDraggingFocusTab() {
    dragFocusTab()
    focusTabDragMouseOffsetY = nil
    persistFocusTabPlacement()
  }

  // MARK: - Persistence

  private func persistPanelPlacement() {
    let defaults = UserDefaults.standard
    switch panelPlacement {
    case .automatic:
      defaults.set("automatic", forKey: DefaultsKey.panelPlacementMode)
      defaults.removeObject(forKey: DefaultsKey.panelPlacementX)
      defaults.removeObject(forKey: DefaultsKey.panelPlacementY)
    case let .manual(topLeft):
      defaults.set("manual", forKey: DefaultsKey.panelPlacementMode)
      defaults.set(topLeft.x, forKey: DefaultsKey.panelPlacementX)
      defaults.set(topLeft.y, forKey: DefaultsKey.panelPlacementY)
    }
  }

  private func persistFocusTabPlacement() {
    UserDefaults.standard.set(focusTabTopRatio, forKey: DefaultsKey.focusTabTopRatio)
  }

  private static func loadPanelPlacement() -> PanelPlacement {
    let defaults = UserDefaults.standard
    guard defaults.string(forKey: DefaultsKey.panelPlacementMode) == "manual" else {
      return .automatic
    }
    let x = defaults.double(forKey: DefaultsKey.panelPlacementX)
    let y = defaults.double(forKey: DefaultsKey.panelPlacementY)
    guard x != 0 || y != 0 else { return .automatic }
    return .manual(topLeft: CGPoint(x: x, y: y))
  }

  private static func loadFocusTabTopRatio() -> CGFloat {
    let storedRatio = UserDefaults.standard.double(forKey: DefaultsKey.focusTabTopRatio)

    guard storedRatio > 0, storedRatio < 1 else {
      return Tab.topRatio
    }

    return CGFloat(storedRatio)
  }

  private static func makePanel(width: CGFloat, height: CGFloat) -> FloatingAssistantPanel {
    let panel = FloatingAssistantPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

    return panel
  }
}
