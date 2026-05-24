import SwiftUI

struct SettingsView: View {
  @Bindable var poroController: PoroController
  @State private var appearance = AppearanceController.shared
  @AppStorage(SettingsKeys.nudgeStep) private var nudgeStep: Double = 24
  @AppStorage(SettingsKeys.mouseDragEnabled) private var mouseDragEnabled: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(spacing: 14) {
          appearanceSection
          windowSection
          shortcutsSection
          generalSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: { poroController.closeSettings() }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(PoroTheme.bodyText)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)

      Spacer()

      Text("Settings")
        .font(PoroTheme.font(size: 13, weight: .semibold))
        .foregroundStyle(PoroTheme.bodyText)

      Spacer()

      Color.clear.frame(width: 24, height: 24)
    }
    .padding(.horizontal, 14)
    .frame(height: 36)
  }

  private var appearanceSection: some View {
    SettingsSection(title: "Appearance") {
      SettingsRow(label: "Accent") {
        SettingsSwatchPicker()
      }
    }
  }

  private var windowSection: some View {
    SettingsSection(title: "Window") {
      SettingsRow(label: "Nudge step") {
        nudgeStepControl
      }
      SettingsRow(label: "Mouse drag") {
        Toggle("", isOn: $mouseDragEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(PoroTheme.accent)
      }
    }
  }

  private var shortcutsSection: some View {
    SettingsSection(title: "Shortcuts") {
      SettingsRow(label: "Toggle Poro") {
        ToggleShortcutRecorder()
      }
    }
  }

  private var nudgeStepControl: some View {
    HStack(spacing: 10) {
      Slider(value: $nudgeStep, in: 4 ... 200, step: 1)
        .frame(width: 160)
        .tint(PoroTheme.accent)

      TextField("", value: $nudgeStep, format: .number)
        .textFieldStyle(.plain)
        .font(PoroTheme.font(size: 12.5, weight: .medium))
        .foregroundStyle(PoroTheme.bodyText)
        .multilineTextAlignment(.trailing)
        .frame(width: 44, height: 26)
        .padding(.horizontal, 8)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(PoroTheme.windowTint)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(PoroTheme.innerBorder, lineWidth: 1)
        )
        .onChange(of: nudgeStep) { _, newValue in
          let clamped = min(max(newValue.rounded(), 4), 200)
          if clamped != nudgeStep {
            nudgeStep = clamped
          }
        }

      Text("px")
        .font(PoroTheme.font(size: 12, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
    }
  }

  private var generalSection: some View {
    SettingsSection(title: "General") {
      Button(action: { NSApp.terminate(nil) }) {
        Text("Quit Poro")
          .font(PoroTheme.font(size: 12.5, weight: .semibold))
          .foregroundStyle(PoroTheme.stopColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(PoroTheme.stopColor.opacity(0.12))
          )
      }
      .buttonStyle(.plain)
    }
  }
}

struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(PoroTheme.font(size: 11, weight: .semibold))
        .foregroundStyle(PoroTheme.mutedText)
        .textCase(.uppercase)

      VStack(spacing: 12) {
        content()
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(PoroTheme.hoverBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(PoroTheme.innerBorder, lineWidth: 1)
      )
    }
  }
}

struct SettingsRow<Trailing: View>: View {
  let label: String
  @ViewBuilder let trailing: () -> Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(label)
        .font(PoroTheme.font(size: 12.5, weight: .medium))
        .foregroundStyle(PoroTheme.bodyText)

      Spacer(minLength: 12)

      trailing()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
