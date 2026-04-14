import SwiftUI

struct InputRowView: View {
  @Binding var draft: String
  @FocusState.Binding var isFocused: Bool

  let isStreaming: Bool
  let onSubmit: () -> Void
  let onStop: () -> Void

  private var hasText: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 12) {
      Image("Poro")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 22, height: 22)
        .opacity(0.95)
        .offset(y: isFocused ? -1 : 0)
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(PoroTheme.shellAnimation, value: isFocused)

      TextField(
        "",
        text: $draft,
        prompt: Text("Ask anything…")
          .foregroundStyle(PoroTheme.mutedText)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 15, weight: .regular))
      .foregroundStyle(PoroTheme.bodyText)
      .focused($isFocused)
      .submitLabel(.send)
      .onSubmit(onSubmit)
      .disabled(isStreaming)

      if isStreaming {
        StopStreamingButton(action: onStop)
      } else if hasText {
        Image(systemName: "arrow.turn.down.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(PoroTheme.accent)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: PoroTheme.collapsedSurfaceHeight)
  }
}

private struct StopStreamingButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .stroke(PoroTheme.stopColor.opacity(0.85), lineWidth: 1.5)
          .frame(width: 20, height: 20)

        RoundedRectangle(cornerRadius: 1.25, style: .continuous)
          .fill(PoroTheme.stopColor.opacity(0.85))
          .frame(width: 7, height: 7)
      }
      .frame(width: 24, height: 24)
    }
    .buttonStyle(StopButtonStyle())
  }
}

private struct StopButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(PoroTheme.stopColor.opacity(configuration.isPressed ? 0.18 : 0.10))
      )
      .scaleEffect(configuration.isPressed ? 0.95 : 1.05)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}
