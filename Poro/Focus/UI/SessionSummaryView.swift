import SwiftUI

struct SessionSummaryView: View {
  let summary: SessionSummary
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Session summary")
          .font(PoroTheme.font(size: 18, weight: .semibold))
          .foregroundStyle(PoroTheme.bodyText)

        Spacer()

        Button("Done", action: onClose)
          .buttonStyle(.plain)
          .font(PoroTheme.font(size: 13, weight: .medium))
          .foregroundStyle(PoroTheme.mutedText)
      }

      rowPair(
        summaryRow("Goal", value: summary.goal),
        summaryRow(
          "Time on task",
          value: "\(summary.completedMinutes)m of \(summary.plannedDurationMinutes)m",
          accent: true
        )
      )

      rowPair(
        summaryRow("Nudges", value: "\(summary.nudgeCount)"),
        summaryRow("Allowed overrides", value: "\(summary.allowedOverrideCount)")
      )

      rowPair(
        summaryRow("Denied overrides", value: "\(summary.deniedOverrideCount)"),
        summaryRow("Top distractions", value: summary.topDistractions.joined(separator: ", ").ifEmpty("None"))
      )

      if !summary.memorableArguments.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Memorable arguments")
            .font(PoroTheme.font(size: 12, weight: .medium))
            .foregroundStyle(PoroTheme.mutedText)

          ForEach(summary.memorableArguments, id: \.self) { argument in
            Text("• \(argument)")
              .font(PoroTheme.font(size: 13, weight: .medium))
              .foregroundStyle(PoroTheme.assistantBodyText)
          }
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func summaryRow(_ label: String, value: String, accent: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(PoroTheme.font(size: 12, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
      Text(value)
        .font(PoroTheme.font(size: 14, weight: .semibold))
        .foregroundStyle(accent ? PoroTheme.accent : PoroTheme.bodyText)
    }
  }

  private func rowPair(_ left: some View, _ right: some View) -> some View {
    HStack(alignment: .top, spacing: 32) {
      left.frame(maxWidth: .infinity, alignment: .leading)
      right.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private extension String {
  func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}
