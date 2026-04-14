import SwiftUI

struct ContentView: View {
  @State private var chatController: ChatController
  @State private var draftMessage = ""
  @FocusState private var isInputFocused: Bool

  private let onDismissRequest: () -> Void
  private let onExpansionChange: (Bool) -> Void

  @MainActor
  init(
    chatController: ChatController? = nil,
    onDismissRequest: @escaping () -> Void = {},
    onExpansionChange: @escaping (Bool) -> Void = { _ in }
  ) {
    _chatController = State(initialValue: chatController ?? ChatController())
    self.onDismissRequest = onDismissRequest
    self.onExpansionChange = onExpansionChange
  }

  private var isExpanded: Bool {
    chatController.hasConversation
  }

  private var surfaceHeight: CGFloat {
    isExpanded ? PoroTheme.expandedSurfaceHeight : PoroTheme.collapsedSurfaceHeight
  }

  private var totalHeight: CGFloat {
    isExpanded ? PoroTheme.expandedSurfaceHeight : PoroTheme.collapsedTotalHeight
  }

  var body: some View {
    VStack(spacing: isExpanded ? 0 : 12) {
      surface
        .frame(width: PoroTheme.width, height: surfaceHeight, alignment: .top)

      if !isExpanded {
        HintView()
          .transition(.opacity)
      }
    }
    .frame(width: PoroTheme.width, height: totalHeight, alignment: .top)
    .background(Color.clear)
    .preferredColorScheme(.dark)
    .animation(PoroTheme.shellAnimation, value: isExpanded)
    .animation(PoroTheme.fadeAnimation, value: chatController.errorMessage)
    .onAppear {
      onExpansionChange(isExpanded)
      focusInputSoon()
    }
    .onChange(of: isExpanded) { _, expanded in
      onExpansionChange(expanded)
    }
    .onReceive(NotificationCenter.default.publisher(for: .assistantWindowDidShow)) { _ in
      focusInputSoon()
    }
    .onExitCommand {
      handleEscape()
    }
  }

  private var surface: some View {
    ZStack {
      HUDMaterialView()
      PoroTheme.windowTint

      VStack(spacing: 0) {
        if isExpanded {
          TopToolbarView(
            onNewConversation: startNewConversation,
            onHistory: {},
            onSettings: {}
          )
          .padding(.top, 8)
          .transition(.opacity.combined(with: .move(edge: .top)))

          MessagesListView(
            messages: chatController.messages,
            isStreaming: chatController.isSending
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          if let errorMessage = chatController.errorMessage {
            Text(errorMessage)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(PoroTheme.stopColor)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 20)
              .padding(.bottom, 10)
              .transition(.opacity)
          }

          Rectangle()
            .fill(PoroTheme.divider)
            .frame(height: 1)
            .transition(.opacity)
        }

        InputRowView(
          draft: $draftMessage,
          isFocused: $isInputFocused,
          isStreaming: chatController.isSending,
          onSubmit: submitCurrentDraft,
          onStop: chatController.stopStreaming
        )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: PoroTheme.windowCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: PoroTheme.windowCornerRadius, style: .continuous)
        .stroke(PoroTheme.innerBorder, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.45), radius: 30, y: 10)
    .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
    .shadow(color: .black.opacity(0.50), radius: 0.5)
  }

  private func submitCurrentDraft() {
    let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty, chatController.canSendMessage else {
      return
    }

    draftMessage = ""
    chatController.send(text)
  }

  private func startNewConversation() {
    chatController.startNewConversation()
    draftMessage = ""
    focusInputSoon()
  }

  private func handleEscape() {
    if chatController.isSending {
      chatController.stopStreaming()
    } else {
      onDismissRequest()
    }
  }

  private func focusInputSoon() {
    DispatchQueue.main.async {
      isInputFocused = true
    }
  }
}

#Preview {
  ContentView()
}
