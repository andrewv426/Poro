import Foundation

/// Manages the recording and compaction of user activity during a session.
@MainActor
final class SessionActivityLogger {
  private(set) var activityLog: [ActivityLogEntry] = []

  /// Records a new activity context, automatically compacting contiguous blocks of the same activity.
  /// - Parameter activity: The current activity context.
  func recordActivity(_ activity: ActivityContext) {
    // If the activity hasn't changed from the last recorded one, do nothing.
    if let lastEntry = activityLog.last, lastEntry.isSameActivity(as: activity) {
      return
    }

    let now = Date()
    // Finalize the previous activity's end time.
    if !activityLog.isEmpty {
      activityLog[activityLog.count - 1].endedAt = now
    }

    // Append the new activity.
    let newEntry = ActivityLogEntry(
      applicationName: activity.applicationName,
      pageURL: activity.pageURL,
      pageTitle: activity.pageTitle,
      startedAt: now,
      endedAt: nil
    )
    activityLog.append(newEntry)

    // Maintain a manageable log size.
    if activityLog.count > 100 {
      activityLog.removeFirst()
    }
  }

  /// Clears the activity history.
  func reset() {
    activityLog.removeAll()
  }

  /// Generates a human-readable, chronological summary of the activity log for the LLM.
  /// - Returns: A formatted string listing activities and their durations.
  func snapshot() -> String {
    guard !activityLog.isEmpty else {
      return "No activity recorded yet."
    }

    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated

    return activityLog.map { entry in
      let timeStr = formatter.string(from: entry.duration) ?? "\(Int(entry.duration))s"
      let location = entry.pageTitle ?? entry.pageURL?.host?.lowercased() ?? entry.applicationName
      return "- \(location) (\(timeStr))"
    }.joined(separator: "\n")
  }
}
