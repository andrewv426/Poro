import SwiftUI

struct FocusNudgeView: View {
  @Bindable var focusSessionController: FocusSessionController
  @FocusState private var isInputFocused: Bool

  private var nudge: NudgeContext? {
    focusSessionController.currentNudge
  }

  var body: some View {
    Group {
      if let nudge {
        VStack(alignment: .leading, spacing: 14) {
          Text("Lock-In Mode")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(PoroTheme.accent)

          Text(nudge.prompt)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(PoroTheme.bodyText)

          switch nudge.stage {
          case .prompted:
            HStack(spacing: 10) {
              actionButton("Back to work", fill: PoroTheme.accent, foreground: .black) {
                focusSessionController.backToWork()
              }

              actionButton("Argue", fill: PoroTheme.hoverBackground, foreground: PoroTheme.bodyText) {
                focusSessionController.beginArguing()
                isInputFocused = true
              }
            }

          case .arguing:
            VStack(alignment: .leading, spacing: 10) {
              TextField(
                "Why is this necessary right now?",
                text: Binding(
                  get: { focusSessionController.currentNudge?.justificationDraft ?? "" },
                  set: { focusSessionController.updateJustificationDraft($0) }
                ),
                axis: .vertical
              )
              .textFieldStyle(.roundedBorder)
              .focused($isInputFocused)

              HStack(spacing: 10) {
                actionButton("Submit", fill: PoroTheme.accent, foreground: .black) {
                  focusSessionController.submitArgument()
                }

                actionButton("Cancel", fill: PoroTheme.hoverBackground, foreground: PoroTheme.bodyText) {
                  focusSessionController.backToWork()
                }
              }
            }
            .onAppear {
              DispatchQueue.main.async {
                isInputFocused = true
              }
            }

          case .evaluating:
            HStack(spacing: 10) {
              ProgressView()
                .controlSize(.small)
              Text("Evaluating your argument…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PoroTheme.assistantBodyText)
            }

          case .resolved(let decision):
            Text(decision.message)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(
                decision.verdict == .allow ? PoroTheme.accent : PoroTheme.stopColor
              )
          }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.84))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(PoroTheme.innerBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 20, y: 10)
      }
    }
  }

  private func actionButton(
    _ title: String,
    fill: Color,
    foreground: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
        )
    }
    .buttonStyle(.plain)
  }
}
