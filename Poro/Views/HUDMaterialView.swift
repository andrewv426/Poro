import AppKit
import SwiftUI

struct HUDMaterialView: NSViewRepresentable {
  func makeNSView(context _: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .withinWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
    nsView.material = .hudWindow
    nsView.blendingMode = .withinWindow
    nsView.state = .active
  }
}
