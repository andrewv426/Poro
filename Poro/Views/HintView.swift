import SwiftUI

struct HintView: View {
  var body: some View {
    HStack(spacing: 6) {
      Text("Press")
      KBDChipView("⌘")
      KBDChipView("⌥")
      KBDChipView("T")
      Text("to summon,")
      KBDChipView("Esc")
      Text("to dismiss")
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(Color.white.opacity(0.32))
  }
}

private struct KBDChipView: View {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var body: some View {
    Text(label)
      .font(.system(size: 11, weight: .medium, design: .monospaced))
      .foregroundStyle(Color.white.opacity(0.78))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
  }
}
