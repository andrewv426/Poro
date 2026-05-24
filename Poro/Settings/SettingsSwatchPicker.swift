import SwiftUI

struct SettingsSwatchPicker: View {
  @State private var appearance = AppearanceController.shared

  private let columns: [GridItem] = Array(
    repeating: GridItem(.flexible(), spacing: 12, alignment: .center),
    count: 8
  )

  var body: some View {
    LazyVGrid(columns: columns, spacing: 12) {
      ForEach(AccentPalette.all) { preset in
        swatch(for: preset)
      }
    }
  }

  private func swatch(for preset: AccentPreset) -> some View {
    let isSelected = preset.id == appearance.preset.id
    return Button(action: { appearance.setPreset(preset) }) {
      ZStack {
        Circle()
          .fill(preset.accent)
          .frame(width: 28, height: 28)

        Circle()
          .stroke(PoroTheme.bodyText.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
          .frame(width: 34, height: 34)
      }
      .frame(width: 36, height: 36)
      .accessibilityLabel(preset.displayName)
    }
    .buttonStyle(.plain)
    .help(preset.displayName)
  }
}
