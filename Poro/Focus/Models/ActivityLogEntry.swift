import Foundation

struct ActivityLogEntry: Codable, Sendable {
  let applicationName: String
  let pageURL: URL?
  let pageTitle: String?
  let startedAt: Date
  var endedAt: Date?

  var duration: TimeInterval {
    (endedAt ?? Date()).timeIntervalSince(startedAt)
  }

  func isSameActivity(as other: ActivityContext) -> Bool {
    applicationName == other.applicationName &&
    pageURL == other.pageURL &&
    pageTitle == other.pageTitle
  }
}
