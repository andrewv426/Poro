import AppKit
import SwiftUI

/// Single, persistent composer row. To kill the SwiftUI identity-churn flicker that used to fire
/// every time a chip mode opened or closed, this view uses ONE TextField across all modes. The
/// chip prefix (`/play`, `/focus`) is a sibling `Text` whose opacity animates in and out — it's
/// never inserted or removed via conditional content. The TextField's text binding pivots
/// between the freeform draft and the chip's query/args based on the current `ComposerMode`, but
/// the field itself stays mounted: same identity, same FocusState, no remount.
struct InputRowView: View {
  @Binding var draft: String
  @FocusState.Binding var isFocused: Bool

  let isStreaming: Bool
  let onSubmit: () -> Void
  let onStop: () -> Void

  /// Optional composer-mode binding (slash menu, /play chip, /focus chip, picker). When non-nil
  /// the row shows the appropriate chip prefix. The TextField's text binding routes through this
  /// in chip modes so the SAME field can edit either the freeform draft or a chip query.
  var composerMode: Binding<ComposerMode>?
  var onExitSpotifyMode: (() -> Void)?
  var onExitFocusMode: (() -> Void)?
  /// Invoked pre-keystroke when the user types space after `/play` or `/focus` — see
  /// `.onKeyPress(.space)` below. Lets the parent transition into chip mode without the
  /// NSTextField briefly displaying "/play " before SwiftUI re-renders.
  var onChipTriggerSpace: ((String) -> Bool)?

  @State private var backspaceMonitor: Any?
  /// Mirror of `currentChipQuery` for the NSEvent monitor closure (which captures by reference
  /// at install time). SwiftUI re-creates the view struct on every keystroke, so a plain `let`
  /// capture inside the closure would read the install-time value forever.
  @State private var currentChipText: String = ""

  private var hasText: Bool {
    !textFieldBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isPickerActive: Bool {
    if case .spotifyOptionPicker = composerMode?.wrappedValue { return true }
    return false
  }

  /// The chip label to show ("play"/"focus") and whether the chip is visible. nil = no chip.
  /// The chip persists into the picker mode so the user retains context for what they
  /// searched while the picker is up.
  private var chipLabel: String? {
    guard let mode = composerMode?.wrappedValue else { return nil }
    switch mode {
    case .spotifyPlay: return "play"
    case .focusStart: return "focus"
    case .spotifyPlaylistChip: return "play playlist"
    case let .spotifyOptionPicker(state):
      return state.kind == .playlist ? "play playlist" : "play"
    case .normal, .slashMenu: return nil
    }
  }

  /// Routes the TextField text between the freeform draft (normal/slashMenu modes) and the chip
  /// query (spotifyPlay/focusStart modes). Both directions stay on the SAME TextField — no
  /// SwiftUI remount, no FocusState bounce.
  ///
  /// In picker mode the binding reads the picker's original query so the field continues to
  /// show what the user searched, and silently ignores writes (the picker has its own arrow-key
  /// monitor; the field is keyboard-disabled).
  private var textFieldBinding: Binding<String> {
    Binding(
      get: {
        guard let mode = composerMode?.wrappedValue else { return draft }
        switch mode {
        case let .spotifyPlay(query): return query
        case let .focusStart(args): return args
        case let .spotifyPlaylistChip(query): return query
        case let .spotifyOptionPicker(state): return state.query
        case .normal, .slashMenu: return draft
        }
      },
      set: { newValue in
        guard let modeBinding = composerMode else {
          draft = newValue
          return
        }
        switch modeBinding.wrappedValue {
        case .spotifyPlay: modeBinding.wrappedValue = .spotifyPlay(query: newValue)
        case .focusStart: modeBinding.wrappedValue = .focusStart(args: newValue)
        case .spotifyPlaylistChip: modeBinding.wrappedValue = .spotifyPlaylistChip(query: newValue)
        case .spotifyOptionPicker: break // read-only during picker
        case .normal, .slashMenu: draft = newValue
        }
      }
    )
  }

  private var placeholder: String {
    switch chipLabel {
    case "play": "What do you want to play?"
    case "play playlist": "Which playlist?"
    case "focus": "e.g. 25m on writing"
    default: "Ask anything…"
    }
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

      // Chip + TextField sit in a tight inner HStack. The chip is always in the tree; its
      // opacity and frame animate when it shows/hides. SwiftUI doesn't remount the TextField,
      // so the focus signal and text don't flicker.
      HStack(spacing: chipLabel != nil ? 6 : 0) {
        chipPrefix
        TextField(
          "",
          text: textFieldBinding,
          prompt: Text(placeholder).foregroundStyle(PoroTheme.mutedText)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(PoroTheme.bodyText)
        .focused($isFocused)
        .submitLabel(.send)
        .onSubmit(onSubmit)
        .disabled(isStreaming || isPickerActive)
        // Intercept space BEFORE AppKit inserts it into the field editor when the draft is a
        // bare slash verb. Without this, AppKit synchronously renders "/play " for one frame
        // before SwiftUI re-evaluates and clears the field — visible as a ghost-text flicker
        // as the chip slides in.
        .onKeyPress(.space) {
          if let onChipTriggerSpace, onChipTriggerSpace(draft) {
            return .handled
          }
          return .ignored
        }
      }

      if isStreaming {
        StopStreamingButton(action: onStop)
      } else if hasText || chipLabel != nil {
        Image(systemName: "arrow.turn.down.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(PoroTheme.accent)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: PoroTheme.collapsedSurfaceHeight)
    .onAppear {
      currentChipText = textFieldBinding.wrappedValue
      installBackspaceMonitor()
    }
    .onDisappear { removeBackspaceMonitor() }
    .onChange(of: textFieldBinding.wrappedValue) { _, newValue in
      currentChipText = newValue
    }
  }

  /// Visual-only chip prefix. Always present in the view tree — opacity and width animate.
  private var chipPrefix: some View {
    Text(chipLabel.map { "/\($0)" } ?? "")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(PoroTheme.accent)
      .padding(.horizontal, chipLabel != nil ? 8 : 0)
      .padding(.vertical, chipLabel != nil ? 3 : 0)
      .background(
        Capsule(style: .continuous)
          .fill(PoroTheme.accent.opacity(chipLabel != nil ? 0.18 : 0))
      )
      .opacity(chipLabel != nil ? 1 : 0)
      .frame(width: chipLabel != nil ? nil : 0)
      .allowsHitTesting(chipLabel != nil)
  }

  // MARK: - Backspace handling

  /// Single global backspace monitor: when the chip is active, the field is focused, and the
  /// chip query is empty, swallow the backspace and exit chip mode. Lives on InputRowView so
  /// it's installed once for the lifetime of the row — no install/teardown per chip swap.
  private func installBackspaceMonitor() {
    backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.keyCode == 51, isFocused, currentChipText.isEmpty else {
        return event
      }
      switch composerMode?.wrappedValue {
      case .spotifyPlay:
        onExitSpotifyMode?()
        return nil
      case .focusStart:
        onExitFocusMode?()
        return nil
      default:
        return event
      }
    }
  }

  private func removeBackspaceMonitor() {
    if let monitor = backspaceMonitor {
      NSEvent.removeMonitor(monitor)
      backspaceMonitor = nil
    }
  }
}

/// Overlay container that owns the keyboard monitor and renders the slash-menu list. Positioned
/// by the parent (`ContentView`) so it can sit outside the chat surface's `clipShape` — the
/// previous "render as `InputRowView` overlay with negative offset" structure caused the menu to
/// draw inside the rounded-corner mask and disappear in collapsed-panel mode.
struct SlashCommandMenuOverlay: View {
  let matches: [SlashCommandDescriptor]
  @Binding var selectedIndex: Int
  let onSelect: (SlashCommandDescriptor) -> Void
  let onDismiss: () -> Void

  // State mirrors so the NSEvent monitor closure reads current values, not stale captures.
  @State private var currentMatches: [SlashCommandDescriptor] = []
  @State private var keyMonitor: Any?

  var body: some View {
    SlashCommandMenu(
      matches: matches,
      selectedIndex: selectedIndex,
      onSelect: { selection in
        removeMonitor()
        onSelect(selection)
      }
    )
    .frame(width: 260)
    // No fade transition: the panel resizes instantly when the slash menu opens/closes
    // (overlay-driven path in setNormalPanelHeight), so an animated fade would linger after
    // the panel has already shrunk and read as the panel "remaining elevated."
    .transition(.identity)
    .onAppear {
      currentMatches = matches
      installMonitor()
    }
    .onDisappear { removeMonitor() }
    .onChange(of: matches) { _, newValue in
      currentMatches = newValue
      // If the selected row no longer exists, snap back to 0.
      if selectedIndex >= newValue.count {
        selectedIndex = 0
      }
    }
  }

  private func installMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let count = currentMatches.count
      guard count > 0 else { return event }

      switch event.keyCode {
      case 126: // up arrow
        selectedIndex = max(0, selectedIndex - 1)
        return nil
      case 125: // down arrow
        selectedIndex = min(count - 1, selectedIndex + 1)
        return nil
      case 36, 76: // return, enter
        let idx = max(0, min(count - 1, selectedIndex))
        removeMonitor()
        onSelect(currentMatches[idx])
        return nil
      case 53: // escape
        removeMonitor()
        onDismiss()
        return nil
      default:
        return event
      }
    }
  }

  private func removeMonitor() {
    if let monitor = keyMonitor {
      NSEvent.removeMonitor(monitor)
      keyMonitor = nil
    }
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
