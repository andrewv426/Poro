import AppKit
import SwiftUI

struct InputRowView: View {
  @Binding var draft: String
  @FocusState.Binding var isFocused: Bool

  let isStreaming: Bool
  let onSubmit: () -> Void
  let onStop: () -> Void

  /// Optional Spotify chip-mode binding. When non-nil and set to `.spotifyPlay`, the row renders a
  /// chip + query field instead of the standard TextField. Only the normal chat surface passes this.
  var composerMode: Binding<ComposerMode>?
  var onExitSpotifyMode: (() -> Void)?

  /// Slash-command menu state. Wired only on the normal chat surface. When `slashMatches` is
  /// non-nil and non-empty, the row overlays a dropdown above the composer.
  var slashMatches: [SlashCommandDescriptor]?
  var slashSelectedIndex: Binding<Int>?
  var onSlashSelect: ((SlashCommandDescriptor) -> Void)?
  var onSlashDismiss: (() -> Void)?

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

      if case let .some(modeBinding) = composerMode,
         case let .spotifyPlay(query) = modeBinding.wrappedValue
      {
        SpotifyChipComposer(
          query: query,
          isStreaming: isStreaming,
          onQueryChange: { newValue in modeBinding.wrappedValue = .spotifyPlay(query: newValue) },
          onSubmit: onSubmit,
          onExitMode: { onExitSpotifyMode?() }
        )
      } else {
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
      }

      if isStreaming {
        StopStreamingButton(action: onStop)
      } else if hasText || isSpotifyMode {
        Image(systemName: "arrow.turn.down.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(PoroTheme.accent)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: PoroTheme.collapsedSurfaceHeight)
    .overlay(alignment: .topLeading) {
      if let matches = slashMatches, !matches.isEmpty, let selIdx = slashSelectedIndex {
        SlashCommandMenuOverlay(
          matches: matches,
          selectedIndex: selIdx,
          onSelect: { onSlashSelect?($0) },
          onDismiss: { onSlashDismiss?() }
        )
      }
    }
  }

  private var isSpotifyMode: Bool {
    if case let .some(mode) = composerMode, case .spotifyPlay = mode.wrappedValue {
      return true
    }
    return false
  }
}

/// Overlay container that positions the menu above the composer and owns the keyboard monitor.
/// Lives inside `InputRowView` so the monitor is installed/torn down with the menu's appearance.
private struct SlashCommandMenuOverlay: View {
  let matches: [SlashCommandDescriptor]
  @Binding var selectedIndex: Int
  let onSelect: (SlashCommandDescriptor) -> Void
  let onDismiss: () -> Void

  // State mirrors so the NSEvent monitor closure reads current values, not stale captures.
  @State private var currentMatches: [SlashCommandDescriptor] = []
  @State private var keyMonitor: Any?

  private var rowCount: CGFloat {
    CGFloat(matches.count)
  }

  private var menuHeight: CGFloat {
    rowCount * 30 + 8
  }

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
    .offset(x: 46, y: -(menuHeight + 6))
    .transition(.opacity.combined(with: .move(edge: .bottom)))
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

private struct SpotifyChipComposer: View {
  let query: String
  let isStreaming: Bool
  let onQueryChange: (String) -> Void
  let onSubmit: () -> Void
  let onExitMode: () -> Void

  @FocusState private var queryFocused: Bool

  // Mirror of the latest query so the backspace monitor closure reads fresh state instead of the
  // value captured at install time (the struct is re-instantiated on every keystroke).
  @State private var currentQuery: String = ""
  @State private var backspaceMonitor: Any?

  var body: some View {
    HStack(spacing: 6) {
      Text("/play")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(PoroTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          Capsule(style: .continuous)
            .fill(PoroTheme.accent.opacity(0.18))
        )

      TextField(
        "",
        text: Binding(get: { query }, set: onQueryChange),
        prompt: Text("What do you want to play?")
          .foregroundStyle(PoroTheme.mutedText)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 15, weight: .regular))
      .foregroundStyle(PoroTheme.bodyText)
      .focused($queryFocused)
      .submitLabel(.send)
      .onSubmit(onSubmit)
      .disabled(isStreaming)
    }
    .onAppear {
      currentQuery = query
      // Defer the focus assignment one runloop tick so SwiftUI has time to register the field in
      // the responder chain. Without this the focus request races view-hierarchy setup and the
      // user has to click into the field to start typing.
      DispatchQueue.main.async { queryFocused = true }
      installBackspaceMonitor()
    }
    .onDisappear { removeBackspaceMonitor() }
    .onChange(of: query) { _, newValue in
      currentQuery = newValue
    }
  }

  private func installBackspaceMonitor() {
    backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // 51 = delete (backspace) on macOS keyboards. Only swallow when the field is focused AND
      // empty *right now* — `currentQuery` is the State-backed mirror that the closure can re-read
      // at fire time. Plain `let query` captured at install would always read the initial value.
      guard event.keyCode == 51, queryFocused, currentQuery.isEmpty else {
        return event
      }
      onExitMode()
      return nil
    }
  }

  private func removeBackspaceMonitor() {
    if let monitor = backspaceMonitor {
      NSEvent.removeMonitor(monitor)
      backspaceMonitor = nil
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
