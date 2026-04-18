import SwiftUI

struct SessionSummaryView: View {
  let summary: SessionSummary
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Session summary")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(PoroTheme.bodyText)

        Spacer()

        Button("Done", action: onClose)
          .buttonStyle(.plain)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(PoroTheme.mutedText)
      }

      summaryRow("Goal", value: summary.goal)
      summaryRow("Time on task", value: "\(summary.completedMinutes)m")
      summaryRow("Nudges", value: "\(summary.nudgeCount)")
      summaryRow("Allowed overrides", value: "\(summary.allowedOverrideCount)")
      summaryRow("Denied overrides", value: "\(summary.deniedOverrideCount)")
      summaryRow("Top distractions", value: summary.topDistractions.joined(separator: ", ").ifEmpty("None"))

      if !summary.memorableArguments.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Memorable arguments")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PoroTheme.mutedText)

          ForEach(summary.memorableArguments, id: \.self) { argument in
            Text("• \(argument)")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(PoroTheme.assistantBodyText)
          }
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func summaryRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(PoroTheme.mutedText)
      Text(value)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(PoroTheme.bodyText)
    }
  }
}

private extension String {
  func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}
