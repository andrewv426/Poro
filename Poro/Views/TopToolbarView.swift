import SwiftUI

struct TopToolbarView: View {
  let onNewConversation: () -> Void
  let onHistory: () -> Void
  let onSettings: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      Image("Poro")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 18, height: 18)
        .opacity(0.85)

      Spacer()

      HStack(spacing: 4) {
        iconButton("square.and.pencil", action: onNewConversation)
        iconButton("clock", action: onHistory)
        iconButton("gearshape", action: onSettings)
      }
    }
    .frame(height: 32)
    .padding(.horizontal, 16)
  }

  private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(ToolbarIconButtonStyle())
  }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            configuration.isPressed
              ? PoroTheme.hoverBackground.opacity(1.3) : PoroTheme.hoverBackground
          )
          .opacity(configuration.isPressed ? 1 : 0)
      )
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
      .onHover { _ in }
  }
}
