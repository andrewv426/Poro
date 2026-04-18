import SwiftUI

struct FocusSetupView: View {
  @Bindable var poroController: PoroController
  @FocusState private var isGoalFocused: Bool

  private let durationOptions = [25, 50, 90]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Start focus session")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(PoroTheme.bodyText)

        Spacer()

        Button("Cancel") {
          poroController.cancelFocusSetup()
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("What are you working on?")
          .font(.system(size: 12, weight: .medium))
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
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(PoroTheme.mutedText)

        HStack(spacing: 10) {
          ForEach(durationOptions, id: \.self) { minutes in
            Button {
              poroController.focusSetupDraft.durationMinutes = minutes
            } label: {
              Text("\(minutes)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                  poroController.focusSetupDraft.durationMinutes == minutes
                    ? Color.black : PoroTheme.bodyText
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                      poroController.focusSetupDraft.durationMinutes == minutes
                        ? PoroTheme.accent : PoroTheme.hoverBackground
                    )
                )
            }
            .buttonStyle(.plain)
          }
        }
      }

      HStack(spacing: 10) {
        Button {
          poroController.confirmFocusSetup()
        } label: {
          Text("Confirm")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PoroTheme.accent)
            )
        }
        .buttonStyle(.plain)

        Button {
          poroController.cancelFocusSetup()
        } label: {
          Text("Edit later")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PoroTheme.bodyText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PoroTheme.hoverBackground)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      DispatchQueue.main.async {
        isGoalFocused = true
      }
    }
  }
}
