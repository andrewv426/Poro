import SwiftUI

/// Dropdown that lists matching slash commands while the user is mid-typing a slash verb.
/// Selection (Enter / click) routes through `PoroController.selectSlashCommand`.
struct SlashCommandMenu: View {
  let matches: [SlashCommandDescriptor]
  let selectedIndex: Int
  let onSelect: (SlashCommandDescriptor) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(matches.enumerated()), id: \.element.id) { idx, command in
        SlashCommandRow(
          command: command,
          isSelected: idx == selectedIndex,
          onTap: { onSelect(command) }
        )
      }
    }
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(PoroTheme.windowTint)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(PoroTheme.innerBorder, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
  }
}

private struct SlashCommandRow: View {
  let command: SlashCommandDescriptor
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        Text(command.title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(PoroTheme.accent)
        Text(command.subtitle)
          .font(.system(size: 12))
          .foregroundStyle(PoroTheme.mutedText)
        Spacer(minLength: 0)
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
