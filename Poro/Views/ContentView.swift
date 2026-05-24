import SwiftUI

struct ContentView: View {
  @Bindable var poroController: PoroController
  let context: AssistantPanelContext
  @FocusState private var isInputFocused: Bool
  @State private var slashSelectedIndex: Int = 0

  private let onDismissRequest: () -> Void
  /// Reports `(baseline, overlayContribution, belowInputRow)` so the window controller can
  /// position the panel correctly. Baseline transitions (chat collapse↔expand, route changes)
  /// animate; overlay growth (slash menu, picker) is instant. `belowInputRow` is the portion of
  /// baseline that sits *below* the input row — the composer-hint footer strip block when
  /// shown. The controller drops the panel bottom by this amount so the input row's top edge
  /// stays put on screen.
  private let onPanelHeightChange: (CGFloat, CGFloat, CGFloat) -> Void
  private let onFocusTabDragChanged: () -> Void
  private let onFocusTabDragEnded: () -> Void

  init(
    poroController: PoroController,
    context: AssistantPanelContext = .normal,
    onDismissRequest: @escaping () -> Void = {},
    onPanelHeightChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void = { _, _, _ in },
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
    baseTotalHeight + overlayContribution
  }

  private var baseTotalHeight: CGFloat {
    if context == .focus, poroController.isFocusPanelTucked { return PoroTheme.tabHeight }
    let focus = context == .focus
    switch poroController.route(for: context) {
    case .chat:
      if poroController.isChatExpanded(in: context) {
        return focus ? PoroTheme.focusExpandedSurfaceHeight : PoroTheme.expandedSurfaceHeight
      }
      // Collapsed chat baseline ALWAYS includes the 32-px footer slot below the input row.
      // The slot is reserved permanently — empty when no hint, fading in/out as the hint text
      // appears/disappears. Panel height stays constant; only the content inside the slot
      // changes. This was the lesson from earlier flicker attempts: any time the panel grew
      // or shrank for the hint, the visual transition betrayed itself.
      return focus ? PoroTheme.focusCollapsedTotalHeight : PoroTheme.collapsedTotalHeight
    case .focusSetup:
      return PoroTheme.focusSetupHeight
    case .summary:
      return PoroTheme.summaryHeight
    case .settings:
      return PoroTheme.settingsHeight
    }
  }

  /// Total vertical space occupied by the footer hint strip + the 12-px VStack spacing above it.
  /// Currently a magic constant; matches the value used in `overlayBottomPadding`.
  private var footerStripBlock: CGFloat {
    32
  }

  /// Part of `baseTotalHeight` that lives BELOW the input row. In normal collapsed chat the
  /// 32-px footer slot is permanently reserved (constant), so `belowInputRow` is constant too.
  /// `normalFrame` uses this to anchor the panel bottom: input row top stays put on screen,
  /// the footer slot always extends below it regardless of whether a hint is currently visible.
  private var belowInputRow: CGFloat {
    guard context == .normal, poroController.route(for: context) == .chat,
          !poroController.isChatExpanded(in: context)
    else { return 0 }
    return footerStripBlock
  }

  /// Extra panel height needed so the slash-menu / Spotify-picker overlay isn't clipped by the
  /// NSPanel frame in COLLAPSED mode. Mirrors the row geometry hardcoded in `SlashCommandMenu`
  /// (30 px) and `SpotifyOptionPickerOverlay` (38 px) — keep those in sync if either changes.
  ///
  /// In **expanded** chat mode the panel already has enough vertical space, and the menu
  /// renders INSIDE the chat surface as an `.overlay(alignment: .bottom)` (covering the bottom
  /// of the message list, Slack/Discord style). So expanded contributes 0 — no panel growth.
  private var overlayContribution: CGFloat {
    guard context == .normal else { return 0 }
    if poroController.isChatExpanded(in: context) { return 0 }
    let gap: CGFloat = 6 // matches the y-offset gap used by both overlays
    switch poroController.composerMode {
    case let .slashMenu(_, matches):
      return CGFloat(matches.count) * 30 + 8 + gap
    case let .spotifyOptionPicker(state):
      return CGFloat(state.options.count) * 38 + 12 + gap
    default:
      return 0
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
    case .settings:
      return PoroTheme.settingsHeight
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
        // ZStack so the slash menu / Spotify picker can render as a SIBLING of `surface` — i.e.
        // outside `surface`'s rounded-corner clipShape. Previously the menus were `InputRowView`
        // overlays *inside* `surface`, and their negative-y offset drew them into the rounded
        // mask in collapsed-panel mode → invisible. Placing them at this level lets them occupy
        // the height the panel grows by (`overlayContribution`) above the surface.
        //
        // The inner VStack pins to `.bottom` so when the window grows by `overlayContribution`
        // (see `totalHeight`), the grown space appears *above* the surface — exactly where the
        // overlay needs to render. The overlay itself anchors to the bottom of the ZStack and
        // pads up to clear the input row.
        ZStack(alignment: .bottomLeading) {
          VStack(spacing: hasFooterSlot ? 12 : 0) {
            surface
              .frame(width: panelWidth, height: surfaceHeight, alignment: .top)

            // Reserve the footer slot whenever the panel could legitimately show a hint
            // (collapsed normal chat). Its size is constant; only the inner content fades
            // in/out as `composerHint` toggles. This keeps the input row's screen position
            // perfectly stable across hint appearance — no panel resize, no row shift, no
            // flicker. When the slot isn't applicable (chat expanded, focus session active,
            // route is not .chat), the VStack collapses normally.
            if hasFooterSlot {
              footerStrip
                .frame(maxWidth: .infinity)
            }
          }
          .frame(width: panelWidth, height: totalHeight, alignment: .bottom)

          // Collapsed mode: render the slash menu / picker in the panel's grown-upward region
          // (sibling of surface, outside its clipShape). In expanded mode this branch is skipped
          // and the overlay is attached INSIDE the chat surface via `.overlay()` further down,
          // covering the bottom of the message list like Slack / Discord / Notion — see the
          // overlay attached to `surface` in `chatSurface`.
          if !poroController.isChatExpanded(in: context) {
            overlayLayer
              .padding(.leading, 46)
              .padding(.bottom, overlayBottomPadding)
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
      onPanelHeightChange(baseTotalHeight, overlayContribution, belowInputRow)
      focusInputSoon()
    }
    .onChange(of: totalHeight) { _, _ in
      onPanelHeightChange(baseTotalHeight, overlayContribution, belowInputRow)
    }
    .onChange(of: belowInputRow) { _, _ in
      onPanelHeightChange(baseTotalHeight, overlayContribution, belowInputRow)
    }
  }

  private var surface: some View {
    ZStack(alignment: .bottomLeading) {
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
      case .settings:
        SettingsView(poroController: poroController)
      }

      // Expanded chat mode: slash menu / Spotify picker renders INSIDE the surface, anchored
      // above the input row. The surrounding `.clipShape` clips it to the rounded corners so
      // it visually belongs to the chat surface (no floating-popup detachment from the panel,
      // which is what users saw in the prior architecture). Collapsed mode skips this branch
      // and renders the overlay in the panel's grown-upward region — see the outer ZStack.
      if context == .normal, poroController.route(for: context) == .chat,
         poroController.isChatExpanded(in: context)
      {
        overlayLayer
          .padding(.leading, 46)
          .padding(.bottom, PoroTheme.collapsedSurfaceHeight + 6)
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
          onSettings: context == .normal ? { poroController.openSettings() } : {},
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
            .font(PoroTheme.font(size: 12, weight: .medium))
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

      if context == .normal {
        InputRowView(
          draft: composerDraftBinding,
          isFocused: $isInputFocused,
          isStreaming: poroController.chatController(for: context).isSending,
          onSubmit: { poroController.submitComposer(in: context) },
          onStop: poroController.chatController(for: context).stopStreaming,
          composerMode: composerModeBinding,
          onExitSpotifyMode: { poroController.exitSpotifyMode() },
          onExitFocusMode: { poroController.exitFocusMode() },
          onChipTriggerSpace: { draft in poroController.handleChipTriggerSpace(currentDraft: draft) }
        )
      }
    }
  }

  /// True when the panel reserves a permanent footer slot (collapsed normal chat). The slot's
  /// size is constant; only its inner content (hint text) fades in/out.
  private var hasFooterSlot: Bool {
    guard poroController.route(for: context) == .chat,
          !poroController.isChatExpanded(in: context)
    else { return false }
    // Normal panel: always reserve. Focus panel: reserve only when there's content to show
    // (existing behavior — focus session status line).
    if context == .normal { return true }
    return poroController.isFocusSessionActive && poroController.sessionStatusLine != nil
  }

  private var footerStrip: some View {
    // Pin the slot's height so it contributes the SAME vertical space whether or not a hint
    // is currently shown. Without this, the ZStack would collapse to 0pt when its conditional
    // content is nil; the inner VStack's content would fall short of `totalHeight` and
    // `.alignment: .bottom` would push the surface 20pt up to fill the gap — the visible
    // "spring up" the user reported. Content fades inside the fixed-height slot via opacity.
    ZStack {
      if let composerHint = poroController.composerHint(for: context) {
        ComposerHintStripView(title: composerHint.title)
          .transition(.opacity)
      } else if context == .focus, poroController.isFocusSessionActive,
                let statusLine = poroController.sessionStatusLine
      {
        SessionStatusStripView(statusLine: statusLine)
          .transition(.opacity)
      }
    }
    .frame(height: 20)
    .animation(PoroTheme.fadeAnimation, value: poroController.composerHint(for: context))
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
    case .settings:
      poroController.closeSettings()
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

  private var currentSlashMatches: [SlashCommandDescriptor]? {
    if case let .slashMenu(_, matches) = poroController.composerMode {
      return matches
    }
    return nil
  }

  private var currentSpotifyPickerState: SpotifyPickerState? {
    if case let .spotifyOptionPicker(state) = poroController.composerMode {
      return state
    }
    return nil
  }

  /// Slash-menu / Spotify-picker rendered as a sibling of `surface` so it isn't clipped by the
  /// surface's rounded `clipShape`. Combined with `overlayContribution`'s window-height grow,
  /// the overlay always has room above the input row regardless of collapsed/expanded state.
  @ViewBuilder
  private var overlayLayer: some View {
    if let matches = currentSlashMatches, !matches.isEmpty {
      SlashCommandMenuOverlay(
        matches: matches,
        selectedIndex: $slashSelectedIndex,
        onSelect: { descriptor in
          poroController.selectSlashCommand(descriptor)
          slashSelectedIndex = 0
        },
        onDismiss: {
          poroController.dismissSlashMenu()
          slashSelectedIndex = 0
        }
      )
    } else if let pickerState = currentSpotifyPickerState {
      SpotifyOptionPickerOverlay(
        state: pickerState,
        onSelectIndex: { poroController.setPickerSelectedIndex($0) },
        onConfirm: { poroController.confirmPickerSelection() },
        onCancel: { poroController.cancelPicker() }
      )
    }
  }

  /// Aligns the overlay's bottom edge 6 px above the input row's top. In ZStack-from-bottom
  /// coords, the input row's top is at `baseTotalHeight` (since baseline = input row + anything
  /// below it like the footer strip, and overlay grows ABOVE the input row).
  private var overlayBottomPadding: CGFloat {
    baseTotalHeight + 6
  }

  private var composerModeBinding: Binding<ComposerMode> {
    Binding(
      get: { poroController.composerMode },
      set: { newMode in
        switch newMode {
        case let .spotifyPlay(query):
          poroController.setSpotifyQuery(query)
        case let .focusStart(args):
          poroController.setFocusArgs(args)
        case .normal:
          switch poroController.composerMode {
          case .spotifyPlay, .spotifyPlaylistChip: poroController.exitSpotifyMode()
          case .focusStart: poroController.exitFocusMode()
          default: break
          }
        case .slashMenu, .spotifyPlaylistChip, .spotifyOptionPicker:
          break
        }
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
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Distracting tab")
            .font(PoroTheme.font(size: 12, weight: .semibold))
            .foregroundStyle(PoroTheme.accent)
            .textCase(.uppercase)

          Text(pendingDistraction.label)
            .font(PoroTheme.font(size: 16, weight: .semibold))
            .foregroundStyle(PoroTheme.bodyText)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        if pendingDistraction.resolution == .pending, !pendingDistraction.isExplaining {
          Text("\(pendingDistraction.remainingSeconds)s")
            .font(.system(size: 15, weight: .bold, design: .monospaced))
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
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(PoroTheme.hoverBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(PoroTheme.innerBorder, lineWidth: 1)
    )
  }

  private var decisionControls: some View {
    HStack(spacing: 8) {
      decisionButton(
        title: isClosing ? "Closing..." : "Close tab",
        foreground: PoroTheme.onAccent,
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
      .font(PoroTheme.font(size: 14, weight: .medium))
      .foregroundStyle(PoroTheme.bodyText)
      .padding(.horizontal, 10)
      .frame(height: 40)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(PoroTheme.windowTint)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(PoroTheme.innerBorder, lineWidth: 1)
      )
      .onSubmit {
        if canSubmitJustification {
          onSubmitJustification()
        }
      }

      HStack(spacing: 8) {
        decisionButton(
          title: "Allow 5m",
          foreground: PoroTheme.onAccent,
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
      .font(PoroTheme.font(size: 13, weight: .medium))
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
        .font(PoroTheme.font(size: 14, weight: .semibold))
        .foregroundStyle(foreground.opacity(isDisabled ? 0.5 : 1))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
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
      .font(PoroTheme.font(size: 12, weight: .medium))
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
        .font(PoroTheme.font(size: 12, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
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
          .fill(PoroTheme.tabBackground)
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(PoroTheme.innerBorder, lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.45), radius: 12, y: 4)

        if isSessionActive {
          let pulseOpacity = if pulse { 0.55 } else { 0.15 }
          let pulseWidth: CGFloat = if pulse { 1.5 } else { 3 }
          let pulseScale: CGFloat = if pulse { 1.35 } else { 1.0 }
          Circle()
            .stroke(PoroTheme.accent.opacity(pulseOpacity), lineWidth: pulseWidth)
            .frame(width: 28, height: 28)
            .scaleEffect(pulseScale)
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
