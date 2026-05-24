import AppKit

final class FloatingAssistantPanel: NSPanel {
  var dragEnabledProvider: (() -> Bool)?
  var onDragEnded: ((CGPoint) -> Void)?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    guard
      dragEnabledProvider?() == true,
      let hit = contentView?.hitTest(event.locationInWindow),
      isDraggableBackground(hit)
    else {
      super.mouseDown(with: event)
      return
    }

    performDrag(with: event)
    onDragEnded?(CGPoint(x: frame.minX, y: frame.maxY))
  }

  private func isDraggableBackground(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
      if candidate is NSControl || candidate is NSTextView {
        return false
      }
      current = candidate.superview
    }
    return true
  }
}
