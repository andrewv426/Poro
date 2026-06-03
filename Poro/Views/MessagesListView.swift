import AppKit
import SwiftUI

struct MessagesListView: View {
  let messages: [ChatMessage]
  let isStreaming: Bool

  private var scrollSignal: String {
    let lastCount = messages.last?.text.count ?? 0
    return "\(messages.count)-\(lastCount)-\(isStreaming)"
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(messages) { message in
            MessageBlockView(
              message: message,
              showStreamingCursor: isStreaming && message.id == messages.last?.id
            )
            .id(message.id)
          }
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
      }
      .scrollIndicators(.visible)
      .onAppear {
        scrollToBottom(with: proxy)
      }
      .onChange(of: scrollSignal) { _, _ in
        scrollToBottom(with: proxy)
      }
    }
  }

  private func scrollToBottom(with proxy: ScrollViewProxy) {
    guard let lastID = messages.last?.id else {
      return
    }

    withAnimation(.easeOut(duration: 0.18)) {
      proxy.scrollTo(lastID, anchor: .bottom)
    }
  }
}

private struct MessageBlockView: View {
  let message: ChatMessage
  let showStreamingCursor: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message.role == .assistant ? "PORO" : "YOU")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(message.role == .assistant ? PoroTheme.accent : PoroTheme.mutedText)

      if !message.images.isEmpty {
        HStack(alignment: .top, spacing: 6) {
          ForEach(message.images) { image in
            attachmentView(for: image)
          }
        }
      }

      if !message.text.isEmpty || showStreamingCursor {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
          Text(message.text.isEmpty && showStreamingCursor ? " " : message.text)
            .font(PoroTheme.font(size: 14.5, weight: .regular))
            .lineSpacing(5)
            .foregroundStyle(
              message.role == .assistant ? PoroTheme.assistantBodyText : PoroTheme.bodyText
            )
            .textSelection(.enabled)

          if showStreamingCursor {
            StreamingCursorView()
              .padding(.bottom, 2)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, PoroTheme.messageSpacing)
  }

  @ViewBuilder
  private func attachmentView(for image: ChatImage) -> some View {
    if let nsImage = NSImage(data: image.data) {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

private struct StreamingCursorView: View {
  @State private var isVisible = true

  var body: some View {
    Rectangle()
      .fill(PoroTheme.accent)
      .frame(width: 2, height: 14)
      .opacity(isVisible ? 1 : 0)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
          isVisible = false
        }
      }
  }
}
