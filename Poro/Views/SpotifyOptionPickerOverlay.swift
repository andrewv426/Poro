import AppKit
import SwiftUI

/// Inline overlay above the composer that lets the user pick a track or playlist after `/play`
/// fetched multiple Spotify hits. Mirrors `SlashCommandMenuOverlay`'s keyboard model: arrows to
/// navigate, Enter to confirm, Escape to back out to the originating chip.
struct SpotifyOptionPickerOverlay: View {
  let state: SpotifyPickerState
  let onSelectIndex: (Int) -> Void
  let onConfirm: () -> Void
  let onCancel: () -> Void

  // Mirrors so the NSEvent monitor reads current values rather than the captured-once `state`
  // value from install time. SwiftUI re-creates the view struct on every parent re-render, but
  // the monitor closure (installed in onAppear) still holds the *original* struct's `state`.
  @State private var currentOptions: [SpotifyPickerOption] = []
  @State private var currentSelectedIndex: Int = 0
  @State private var keyMonitor: Any?

  var body: some View {
    SpotifyPickerList(state: state, onTap: { idx in
      removeMonitor()
      onSelectIndex(idx)
      onConfirm()
    })
    .frame(width: 320)
    // No fade transition: the panel resizes instantly when the picker opens/closes, so an
    // animated fade would linger after the panel has already shrunk and read as a flicker.
    .transition(.identity)
    .onAppear {
      currentOptions = state.options
      currentSelectedIndex = state.selectedIndex
      installMonitor()
    }
    .onDisappear { removeMonitor() }
    .onChange(of: state.options) { _, newValue in
      currentOptions = newValue
    }
    .onChange(of: state.selectedIndex) { _, newValue in
      currentSelectedIndex = newValue
    }
  }

  private func installMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let count = currentOptions.count
      guard count > 0 else { return event }

      switch event.keyCode {
      case 126: // up arrow
        onSelectIndex(max(0, currentSelectedIndex - 1))
        return nil
      case 125: // down arrow
        onSelectIndex(min(count - 1, currentSelectedIndex + 1))
        return nil
      case 36, 76: // return, enter
        removeMonitor()
        onConfirm()
        return nil
      case 53: // escape
        removeMonitor()
        onCancel()
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

private struct SpotifyPickerList: View {
  let state: SpotifyPickerState
  let onTap: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(state.options.enumerated()), id: \.element.id) { idx, option in
        SpotifyPickerRow(
          option: option,
          isSelected: idx == state.selectedIndex,
          onTap: { onTap(idx) }
        )
      }
    }
    .padding(.vertical, 4)
    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(PoroTheme.innerBorder, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
  }
}

private struct SpotifyPickerRow: View {
  let option: SpotifyPickerOption
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 2) {
        Text(option.title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(PoroTheme.bodyText)
          .lineLimit(1)
        if let subtitle = option.subtitle {
          Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(PoroTheme.mutedText)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected
          ? PoroTheme.accent.opacity(0.12)
          : Color.clear
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
