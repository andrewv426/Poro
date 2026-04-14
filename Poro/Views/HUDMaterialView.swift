import AppKit
import SwiftUI

struct HUDMaterialView: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .withinWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = .hudWindow
    nsView.blendingMode = .withinWindow
    nsView.state = .active
  }
}
