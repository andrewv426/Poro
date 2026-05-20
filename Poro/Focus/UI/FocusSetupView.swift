import SwiftUI

struct FocusSetupView: View {
  @Bindable var poroController: PoroController
  @FocusState private var isGoalFocused: Bool
  @FocusState private var isCustomFocused: Bool
  @State private var isCustomActive: Bool = false
  @State private var customDraft: String = ""

  private let durationOptions = PoroController.durationPresets
  private let minCustomMinutes = 1
  private let maxCustomMinutes = 240

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Start focus session")
          .font(PoroTheme.font(size: 18, weight: .semibold))
          .foregroundStyle(PoroTheme.bodyText)

        Spacer()

        Button("Cancel") {
          poroController.cancelFocusSetup()
        }
        .buttonStyle(.plain)
        .font(PoroTheme.font(size: 13, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("What are you working on?")
          .font(PoroTheme.font(size: 12, weight: .medium))
          .foregroundStyle(PoroTheme.mutedText)

        TextField(
          "Finish the essay",
          text: $poroController.focusSetupDraft.goal
        )
        .textFieldStyle(.roundedBorder)
        .focused($isGoalFocused)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Duration")
          .font(PoroTheme.font(size: 12, weight: .medium))
          .foregroundStyle(PoroTheme.mutedText)

        if isCustomActive {
          HStack(spacing: 10) {
            TextField("Minutes", text: $customDraft)
              .textFieldStyle(.roundedBorder)
              .focused($isCustomFocused)
              .onChange(of: customDraft) { _, newValue in
                applyCustomDraft(newValue)
              }

            Button {
              isCustomActive = false
              let fallback = durationOptions.contains(poroController.focusSetupDraft.durationMinutes)
                ? poroController.focusSetupDraft.durationMinutes
                : (durationOptions.first ?? 45)
              poroController.focusSetupDraft.durationMinutes = fallback
            } label: {
              Text("Presets")
                .font(PoroTheme.font(size: 13, weight: .semibold))
                .foregroundStyle(PoroTheme.bodyText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PoroTheme.hoverBackground)
                )
            }
            .buttonStyle(.plain)
          }
        } else {
          HStack(spacing: 10) {
            ForEach(durationOptions, id: \.self) { minutes in
              presetChip(minutes: minutes)
            }
            customChip
          }
        }
      }

      Button {
        poroController.confirmFocusSetup()
      } label: {
        Text("Confirm")
          .font(PoroTheme.font(size: 13, weight: .semibold))
          .foregroundStyle(PoroTheme.onAccent)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(PoroTheme.accent)
          )
      }
      .buttonStyle(.plain)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      let current = poroController.focusSetupDraft.durationMinutes
      if !durationOptions.contains(current) {
        isCustomActive = true
        customDraft = String(current)
      } else if let remembered = poroController.lastCustomDurationMinutes {
        customDraft = String(remembered)
      }
      DispatchQueue.main.async {
        isGoalFocused = true
      }
    }
  }

  private func presetChip(minutes: Int) -> some View {
    let isSelected = !isCustomActive
      && poroController.focusSetupDraft.durationMinutes == minutes

    return Button {
      isCustomActive = false
      poroController.focusSetupDraft.durationMinutes = minutes
    } label: {
      Text("\(minutes)")
        .font(PoroTheme.font(size: 13, weight: .semibold))
        .foregroundStyle(isSelected ? PoroTheme.onAccent : PoroTheme.bodyText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? PoroTheme.accent : PoroTheme.hoverBackground)
        )
    }
    .buttonStyle(.plain)
  }

  private var customChip: some View {
    let label: String = {
      if isCustomActive, let value = Int(customDraft), value > 0 {
        return "\(value)"
      }
      if let remembered = poroController.lastCustomDurationMinutes {
        return "\(remembered)"
      }
      return "Custom"
    }()

    return Button {
      isCustomActive = true
      if customDraft.isEmpty, let remembered = poroController.lastCustomDurationMinutes {
        customDraft = String(remembered)
      }
      applyCustomDraft(customDraft)
      DispatchQueue.main.async {
        isCustomFocused = true
      }
    } label: {
      Text(label)
        .font(PoroTheme.font(size: 13, weight: .semibold))
        .foregroundStyle(isCustomActive ? PoroTheme.onAccent : PoroTheme.bodyText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isCustomActive ? PoroTheme.accent : PoroTheme.hoverBackground)
        )
    }
    .buttonStyle(.plain)
  }

  private func applyCustomDraft(_ raw: String) {
    let digits = raw.filter(\.isNumber)
    if digits != raw {
      customDraft = digits
      return
    }
    guard let value = Int(digits) else { return }
    let clamped = max(minCustomMinutes, min(maxCustomMinutes, value))
    poroController.focusSetupDraft.durationMinutes = clamped
  }
}
