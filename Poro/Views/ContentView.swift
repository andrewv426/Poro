import SwiftUI

struct ContentView: View {
  @Bindable var poroController: PoroController
  let context: AssistantPanelContext
  @FocusState private var isInputFocused: Bool

  private let onDismissRequest: () -> Void
  private let onPanelHeightChange: (CGFloat) -> Void
  private let onFocusTabDragChanged: () -> Void
  private let onFocusTabDragEnded: () -> Void

  init(
    poroController: PoroController,
    context: AssistantPanelContext = .normal,
    onDismissRequest: @escaping () -> Void = {},
    onPanelHeightChange: @escaping (CGFloat) -> Void = { _ in },
    onFocusTabDragChanged: @escaping () -> Void = {},
    onFocusTabDragEnded: @escaping () -> Void = {}
  ) {
    self.poroController = poroController
    self.context = context
    self.onDismissRequest = onDismissRequest
    self.onPanelHeightChange = onPanelHeightChange
    self.onFocusTabDragChanged = onFocusTabDragChanged
    self.onFocusTabDragEnded = onFocusTabDragEnded
  }

  private var totalHeight: CGFloat {
    if context == .focus, poroController.isFocusPanelTucked { return PoroTheme.tabHeight }
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

  private var surfaceHeight: CGFloat {
    let focus = context == .focus
    switch poroController.route(for: context) {
    case .chat:
      if poroController.isChatExpanded(in: context) {
        return focus ? PoroTheme.focusExpandedSurfaceHeight : PoroTheme.expandedSurfaceHeight
      }
      return focus ? PoroTheme.focusCollapsedSurfaceHeight : PoroTheme.collapsedSurfaceHeight
    case .focusSetup:
      return PoroTheme.focusSetupHeight
    case .summary:
      return PoroTheme.summaryHeight
    }
  }

  var body: some View {
    Group {
      if context == .focus, poroController.isFocusPanelTucked {
        FocusTabView(
          isSessionActive: poroController.isFocusSessionActive,
          onDragChanged: onFocusTabDragChanged,
          onDragEnded: onFocusTabDragEnded
        )
        .frame(width: PoroTheme.focusWidth, height: PoroTheme.tabHeight, alignment: .leading)
      } else {
        let panelWidth = context == .focus ? PoroTheme.focusWidth : PoroTheme.width
        VStack(spacing: showsFooterStrip ? 12 : 0) {
          surface
            .frame(width: panelWidth, height: surfaceHeight, alignment: .top)

          if showsFooterStrip {
            footerStrip
              .transition(.opacity)
          }
        }
        .frame(width: panelWidth, height: totalHeight, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: didShowNotificationName)) { _ in
          focusInputSoon()
        }
        .onExitCommand {
          handleEscape()
        }
      }
    }
    .background(Color.clear)
    .preferredColorScheme(.dark)
    .animation(PoroTheme.shellAnimation, value: poroController.route(for: context))
    .animation(PoroTheme.shellAnimation, value: poroController.isChatExpanded(in: context))
    .animation(PoroTheme.shellAnimation, value: poroController.isFocusPanelTucked)
    .animation(PoroTheme.fadeAnimation, value: poroController.composerHint(for: context))
    .onAppear {
      onPanelHeightChange(totalHeight)
      focusInputSoon()
    }
    .onChange(of: totalHeight) { _, height in
      onPanelHeightChange(height)
    }
  }

  private var surface: some View {
    ZStack {
      HUDMaterialView()
      PoroTheme.windowTint

      switch poroController.route(for: context) {
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
      if poroController.isChatExpanded(in: context) {
        TopToolbarView(
          onNewConversation: poroController.chatController(for: context).startNewConversation,
          onHistory: {},
          onSettings: {},
          statusLine: poroController.sessionStatusLine,
          onEndSession: poroController.isFocusSessionActive ? {
            _ = poroController.focusSessionController.handleSessionCommand(.end)
          } : nil
        )
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))

        if context == .focus, let pendingDistraction = poroController.focusSessionController.pendingDistraction {
          DistractionDecisionView(
            pendingDistraction: pendingDistraction,
            justificationDraft: pendingDistractionJustificationBinding,
            onCloseTab: {
              poroController.focusSessionController.closePendingDistraction(manual: true)
            },
            onExplain: {
              poroController.focusSessionController.beginExplainingPendingDistraction()
            },
            onSubmitJustification: {
              poroController.focusSessionController.allowPendingDistraction()
            }
          )
          .padding(.horizontal, 14)
          .padding(.bottom, 8)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }

        MessagesListView(
          messages: poroController.chatController(for: context).messages,
          isStreaming: poroController.chatController(for: context).isSending
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let errorMessage = poroController.chatController(for: context).errorMessage {
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
        draft: composerDraftBinding,
        isFocused: $isInputFocused,
        isStreaming: poroController.chatController(for: context).isSending,
        onSubmit: { poroController.submitComposer(in: context) },
        onStop: poroController.chatController(for: context).stopStreaming
      )
    }
  }

  private var showsFooterStrip: Bool {
    poroController.route(for: context) == .chat && !poroController.isChatExpanded(in: context)
  }

  @ViewBuilder
  private var footerStrip: some View {
    if let composerHint = poroController.composerHint(for: context) {
      ComposerHintStripView(title: composerHint.title)
    } else if context == .focus, poroController.isFocusSessionActive,
              let statusLine = poroController.sessionStatusLine
    {
      SessionStatusStripView(statusLine: statusLine)
    } else {
      HintView()
    }
  }

  private func handleEscape() {
    // During an active focus session, Esc always tucks — never fully hides.
    if context == .focus, poroController.isFocusSessionActive {
      if poroController.chatController(for: context).isSending {
        poroController.chatController(for: context).stopStreaming()
      }
      onDismissRequest()
      return
    }

    switch poroController.route(for: context) {
    case .chat:
      if poroController.chatController(for: context).isSending {
        poroController.chatController(for: context).stopStreaming()
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
    guard poroController.route(for: context) == .chat else {
      return
    }

    DispatchQueue.main.async {
      isInputFocused = true
    }
  }

  private var composerDraftBinding: Binding<String> {
    Binding(
      get: {
        poroController.composerDraft(for: context)
      },
      set: { draft in
        poroController.updateComposerDraft(draft, in: context)
      }
    )
  }

  private var didShowNotificationName: Notification.Name {
    context == .focus ? .focusAssistantWindowDidShow : .normalAssistantWindowDidShow
  }

  private var pendingDistractionJustificationBinding: Binding<String> {
    Binding(
      get: {
        poroController.focusSessionController.pendingDistraction?.justificationDraft ?? ""
      },
      set: { draft in
        poroController.focusSessionController.updatePendingDistractionJustification(draft)
      }
    )
  }
}

private struct DistractionDecisionView: View {
  let pendingDistraction: PendingDistraction
  @Binding var justificationDraft: String
  let onCloseTab: () -> Void
  let onExplain: () -> Void
  let onSubmitJustification: () -> Void

  private var canSubmitJustification: Bool {
    !justificationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isClosing: Bool {
    if case .closing = pendingDistraction.resolution {
      return true
    }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Distracting tab")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PoroTheme.accent)
            .textCase(.uppercase)

          Text(pendingDistraction.label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PoroTheme.bodyText)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        if pendingDistraction.resolution == .pending, !pendingDistraction.isExplaining {
          Text("\(pendingDistraction.remainingSeconds)s")
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(PoroTheme.stopColor)
        }
      }

      switch pendingDistraction.resolution {
      case .pending, .closing:
        if pendingDistraction.isExplaining {
          explanationControls
        } else {
          decisionControls
        }
      case .closed:
        statusText("Tab closed.")
      case .allowed:
        statusText("Allowed for now.")
      case let .failed(message):
        statusText(message)
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.055))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    )
  }

  private var decisionControls: some View {
    HStack(spacing: 8) {
      decisionButton(
        title: isClosing ? "Closing..." : "Close tab",
        foreground: .black,
        background: PoroTheme.accent,
        isDisabled: isClosing,
        action: onCloseTab
      )

      decisionButton(
        title: "Explain why",
        foreground: PoroTheme.bodyText,
        background: PoroTheme.hoverBackground,
        isDisabled: isClosing,
        action: onExplain
      )
    }
  }

  private var explanationControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(
        "Break, emergency, educational content...",
        text: $justificationDraft
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(PoroTheme.bodyText)
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.black.opacity(0.18))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .onSubmit {
        if canSubmitJustification {
          onSubmitJustification()
        }
      }

      HStack(spacing: 8) {
        decisionButton(
          title: "Allow 5m",
          foreground: .black,
          background: PoroTheme.accent,
          isDisabled: !canSubmitJustification,
          action: onSubmitJustification
        )

        decisionButton(
          title: isClosing ? "Closing..." : "Close tab",
          foreground: PoroTheme.bodyText,
          background: PoroTheme.hoverBackground,
          isDisabled: isClosing,
          action: onCloseTab
        )
      }
    }
  }

  private func statusText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(PoroTheme.mutedText)
      .lineLimit(2)
  }

  private func decisionButton(
    title: String,
    foreground: Color,
    background: Color,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(foreground.opacity(isDisabled ? 0.5 : 1))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(background.opacity(isDisabled ? 0.45 : 1))
        )
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
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

// MARK: - Focus Tab

private struct FocusTabView: View {
  let isSessionActive: Bool
  let onDragChanged: () -> Void
  let onDragEnded: () -> Void

  @State private var pulse = false

  var body: some View {
    HStack(spacing: 0) {
      Spacer()

      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(red: 22 / 255, green: 22 / 255, blue: 28 / 255).opacity(0.88))
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(PoroTheme.innerBorder, lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.45), radius: 12, y: 4)

        if isSessionActive {
          Circle()
            .stroke(PoroTheme.accent.opacity(pulse ? 0.55 : 0.15), lineWidth: pulse ? 1.5 : 3)
            .frame(width: 28, height: 28)
            .scaleEffect(pulse ? 1.35 : 1.0)
            .animation(
              Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
              value: pulse
            )
        }

        Image("Poro")
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
      }
      .frame(width: PoroTheme.tabVisibleWidth, height: PoroTheme.tabHeight)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 1)
          .onChanged { _ in
            onDragChanged()
          }
          .onEnded { _ in
            onDragEnded()
          }
      )
      .onAppear { pulse = true }
    }
  }
}

#Preview {
  ContentView(poroController: PoroController())
}
