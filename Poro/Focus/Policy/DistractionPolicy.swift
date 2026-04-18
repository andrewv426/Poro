import Foundation

struct DistractionHit: Equatable, Sendable {
  let applicationName: String
  let reason: String
}

struct DistractionPolicy {
  private let alwaysDistractingBundleIdentifiers: Set<String> = [
    "com.hnc.Discord",
    "com.tinyspeck.slackmacgap",
    "com.spotify.client",
    "com.apple.Music",
    "com.apple.TV",
    "com.apple.MobileSMS",
  ]

  private let browserBundleIdentifiers: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "org.mozilla.firefox",
    "com.brave.Browser",
    "com.microsoft.edgemac",
    "company.thebrowser.Browser",
  ]

  private let distractingHosts: Set<String> = [
    "youtube.com",
    "m.youtube.com",
    "x.com",
    "twitter.com",
    "reddit.com",
    "discord.com",
    "instagram.com",
    "facebook.com",
    "tiktok.com",
  ]

  func evaluate(activity: ActivityContext, goal: String) -> DistractionHit? {
    if let bundleIdentifier = activity.bundleIdentifier,
      alwaysDistractingBundleIdentifiers.contains(bundleIdentifier)
    {
      return DistractionHit(
        applicationName: activity.applicationName,
        reason: "\(activity.applicationName) is usually a distraction during focused work."
      )
    }

    if let bundleIdentifier = activity.bundleIdentifier,
      browserBundleIdentifiers.contains(bundleIdentifier)
    {
      if let host = activity.pageHost,
        distractingHosts.contains(host) || distractingHosts.contains(host.replacingOccurrences(of: "www.", with: ""))
      {
        return DistractionHit(
          applicationName: host,
          reason: "\(host) is a distraction for this session."
        )
      }

      guard !goalSuggestsBrowserWork(goal) else {
        return nil
      }

      return DistractionHit(
        applicationName: activity.applicationName,
        reason: "\(activity.applicationName) is outside the current focus goal."
      )
    }

    return nil
  }

  private func goalSuggestsBrowserWork(_ goal: String) -> Bool {
    let lowercased = goal.lowercased()
    let browserFriendlyKeywords = [
      "research",
      "reference",
      "web",
      "browser",
      "read",
      "docs",
      "documentation",
      "source",
      "look up",
    ]

    return browserFriendlyKeywords.contains(where: { lowercased.contains($0) })
  }
}
