import SwiftUI

struct ContentView: View {
  @Bindable var poroController: PoroController
  @FocusState private var isInputFocused: Bool

  private let onDismissRequest: () -> Void
  private let onPanelHeightChange: (CGFloat) -> Void

  init(
    poroController: PoroController,
    onDismissRequest: @escaping () -> Void = {},
    onPanelHeightChange: @escaping (CGFloat) -> Void = { _ in }
  ) {
    self.poroController = poroController
    self.onDismissRequest = onDismissRequest
    self.onPanelHeightChange = onPanelHeightChange
  }

  private var totalHeight: CGFloat {
    switch poroController.panelRoute {
    case .chat:
      if poroController.isChatExpanded {
        return PoroTheme.expandedSurfaceHeight
      }

      return poroController.isFocusSessionActive
        ? PoroTheme.activeSessionCollapsedTotalHeight : PoroTheme.collapsedTotalHeight
    case .focusSetup:
      return PoroTheme.focusSetupHeight
    case .summary:
      return PoroTheme.summaryHeight
    }
  }

  private var surfaceHeight: CGFloat {
    switch poroController.panelRoute {
    case .chat:
      return poroController.isChatExpanded ? PoroTheme.expandedSurfaceHeight : PoroTheme.collapsedSurfaceHeight
    case .focusSetup:
      return PoroTheme.focusSetupHeight
    case .summary:
      return PoroTheme.summaryHeight
    }
  }

  var body: some View {
    VStack(spacing: showsFooterStrip ? 12 : 0) {
      surface
        .frame(width: PoroTheme.width, height: surfaceHeight, alignment: .top)

      if showsFooterStrip {
        footerStrip
          .transition(.opacity)
      }
    }
    .frame(width: PoroTheme.width, height: totalHeight, alignment: .top)
    .background(Color.clear)
    .preferredColorScheme(.dark)
    .animation(PoroTheme.shellAnimation, value: poroController.panelRoute)
    .animation(PoroTheme.shellAnimation, value: poroController.isChatExpanded)
    .animation(PoroTheme.fadeAnimation, value: poroController.composerHint)
    .onAppear {
      onPanelHeightChange(totalHeight)
      focusInputSoon()
    }
    .onChange(of: totalHeight) { _, height in
      onPanelHeightChange(height)
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

      switch poroController.panelRoute {
      case .chat:
        chatSurface
      case .focusSetup:
        FocusSetupView(poroController: poroController)
      case .summary:
        if let summary = poroController.focusSessionController.latestSummary {
          SessionSummaryView(summary: summary) {
            poroController.dismissSummary()
            onDismissRequest()
          }
        }
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

  private var chatSurface: some View {
    VStack(spacing: 0) {
      if poroController.isChatExpanded {
        TopToolbarView(
          onNewConversation: poroController.chatController.startNewConversation,
          onHistory: {},
          onSettings: {},
          statusLine: poroController.sessionStatusLine,
          onEndSession: poroController.isFocusSessionActive ? {
            _ = poroController.focusSessionController.handleSessionCommand(.end)
            poroController.panelRoute = .summary
          } : nil
        )
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))

        MessagesListView(
          messages: poroController.chatController.messages,
          isStreaming: poroController.chatController.isSending
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let errorMessage = poroController.chatController.errorMessage {
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
        draft: $poroController.composerDraft,
        isFocused: $isInputFocused,
        isStreaming: poroController.chatController.isSending,
        onSubmit: poroController.submitComposer,
        onStop: poroController.chatController.stopStreaming
      )
      .onChange(of: poroController.composerDraft) { _, draft in
        poroController.updateComposerDraft(draft)
      }
    }
  }

  private var showsFooterStrip: Bool {
    poroController.panelRoute == .chat && !poroController.isChatExpanded
  }

  @ViewBuilder
  private var footerStrip: some View {
    if let composerHint = poroController.composerHint {
      ComposerHintStripView(title: composerHint.title)
    } else if poroController.isFocusSessionActive, let statusLine = poroController.sessionStatusLine {
      SessionStatusStripView(statusLine: statusLine)
    } else {
      HintView()
    }
  }

  private func handleEscape() {
    switch poroController.panelRoute {
    case .chat:
      if poroController.chatController.isSending {
        poroController.chatController.stopStreaming()
      } else {
        onDismissRequest()
      }
    case .focusSetup:
      poroController.cancelFocusSetup()
    case .summary:
      onDismissRequest()
    }
  }

  private func focusInputSoon() {
    guard poroController.panelRoute == .chat else {
      return
    }

    DispatchQueue.main.async {
      isInputFocused = true
    }
  }
}

private struct ComposerHintStripView: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(PoroTheme.accent)
  }
}

private struct SessionStatusStripView: View {
  let statusLine: String

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(PoroTheme.accent)
        .frame(width: 8, height: 8)

      Text(statusLine)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.44))
        .lineLimit(1)
    }
  }
}

#Preview {
  ContentView(poroController: PoroController())
}
