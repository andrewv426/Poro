import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

  /// Staged image attachments shown as thumbnails; submitted with the next message.
  var attachments: [ChatImage] = []
  var onPickImage: (() -> Void)?
  var onRemoveAttachment: ((ChatImage.ID) -> Void)?
  var onImageData: ((Data) -> Void)?

  /// Slash-menu keyboard navigation. Handled by the composer's persistent key monitor (below) so
  /// it's live the instant the menu opens — no per-appear install race. Delta is -1 (up) / +1 (down).
  var onSlashMenuMove: ((Int) -> Void)?
  var onSlashMenuConfirm: (() -> Void)?
  var onSlashMenuDismiss: (() -> Void)?

  @State private var composerKeyMonitor: Any?
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

  private var isSlashMenuActive: Bool {
    if case let .slashMenu(_, matches) = composerMode?.wrappedValue { return !matches.isEmpty }
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

      uploadButton

      if !attachments.isEmpty {
        HStack(spacing: 4) {
          ForEach(attachments) { attachment in
            AttachmentThumbnailView(
              attachment: attachment,
              onRemove: { onRemoveAttachment?(attachment.id) }
            )
          }
        }
      }

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
      } else if hasText || chipLabel != nil || !attachments.isEmpty {
        Image(systemName: "arrow.turn.down.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(PoroTheme.accent)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: PoroTheme.collapsedSurfaceHeight)
    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
      handleImageDrop(providers)
    }
    .onAppear {
      currentChipText = textFieldBinding.wrappedValue
      installComposerKeyMonitor()
    }
    .onDisappear { removeComposerKeyMonitor() }
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

  // MARK: - Image attachments

  private var uploadButton: some View {
    Button(action: { onPickImage?() }) {
      Image(systemName: "paperclip")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.plain)
    .disabled(isStreaming)
    .help("Attach image")
  }

  /// Stages images dropped onto the composer. Raw bytes are forwarded to the controller, which
  /// decodes and downscales them off the main actor.
  private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let onImageData else { return false }
    var handled = false

    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        handled = true
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
          guard let data else { return }
          Task { @MainActor in onImageData(data) }
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        handled = true
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
          guard
            let data,
            let url = URL(dataRepresentation: data, relativeTo: nil),
            let imageData = try? Data(contentsOf: url)
          else { return }
          Task { @MainActor in onImageData(imageData) }
        }
      }
    }

    return handled
  }

  // MARK: - Composer key handling

  /// One key monitor for the lifetime of the composer row (not per slash-menu appear). Because it's
  /// already live before the menu opens, slash-menu arrow/return/escape keys are handled the instant
  /// the menu appears — fixing the first-open race where the arrow used to fall through to the text
  /// cursor. It also swallows backspace to exit an empty chip.
  private func installComposerKeyMonitor() {
    guard composerKeyMonitor == nil else { return }
    composerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Slash-menu navigation. Gated on the normal composer being focused so this app-wide monitor
      // never swallows keys meant for the focus panel (e.g. if a distraction expands it while the
      // menu is open). Plain keys only — Cmd/Opt arrows belong to the panel-nudge monitor.
      if isSlashMenuActive, isFocused {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !mods.contains(.command), !mods.contains(.option) {
          switch event.keyCode {
          case 126: onSlashMenuMove?(-1); return nil // up
          case 125: onSlashMenuMove?(1); return nil // down
          case 36, 76: onSlashMenuConfirm?(); return nil // return / enter
          case 53: onSlashMenuDismiss?(); return nil // escape
          default: break
          }
        }
      }

      // Backspace on an empty chip exits chip mode.
      if event.keyCode == 51, isFocused, currentChipText.isEmpty {
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

      return event
    }
  }

  private func removeComposerKeyMonitor() {
    if let monitor = composerKeyMonitor {
      NSEvent.removeMonitor(monitor)
      composerKeyMonitor = nil
    }
  }
}

/// Renders the slash-menu list. Keyboard navigation lives in InputRowView's composer key monitor. Positioned
/// by the parent (`ContentView`) so it can sit outside the chat surface's `clipShape` — the
/// previous "render as `InputRowView` overlay with negative offset" structure caused the menu to
/// draw inside the rounded-corner mask and disappear in collapsed-panel mode.
struct SlashCommandMenuOverlay: View {
  let matches: [SlashCommandDescriptor]
  @Binding var selectedIndex: Int
  let onSelect: (SlashCommandDescriptor) -> Void

  var body: some View {
    SlashCommandMenu(
      matches: matches,
      selectedIndex: selectedIndex,
      onSelect: onSelect
    )
    .frame(width: 260)
    // No fade transition: the panel resizes instantly when the slash menu opens/closes
    // (overlay-driven path in setNormalPanelHeight), so an animated fade would linger after
    // the panel has already shrunk and read as the panel "remaining elevated."
    .transition(.identity)
    // Keyboard navigation (up/down/return/escape) is handled by the composer's persistent key
    // monitor in InputRowView, so it's live the instant the menu opens. This view only renders the
    // list and handles mouse selection. Snap the highlight back if the matches list shrinks.
    .onChange(of: matches) { _, newValue in
      if selectedIndex >= newValue.count {
        selectedIndex = 0
      }
    }
  }
}

/// A staged image attachment shown in the composer, with a corner button to remove it.
private struct AttachmentThumbnailView: View {
  let attachment: ChatImage
  let onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      thumbnail
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 11))
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .black.opacity(0.55))
      }
      .buttonStyle(.plain)
      .offset(x: 5, y: -5)
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let nsImage = NSImage(data: attachment.data) {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    } else {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(PoroTheme.mutedText.opacity(0.3))
        .frame(width: 28, height: 28)
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
