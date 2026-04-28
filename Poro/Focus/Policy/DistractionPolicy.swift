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

  func staticHit(activity: ActivityContext) -> DistractionHit? {
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
        isDistractingHost(host)
      {
        return DistractionHit(
          applicationName: host,
          reason: "\(host) is a distraction for this session."
        )
      }
    }

    return nil
  }

  func needsLLMClassification(activity: ActivityContext) -> Bool {
    guard
      let bundleIdentifier = activity.bundleIdentifier,
      browserBundleIdentifiers.contains(bundleIdentifier),
      activity.pageURL != nil
    else {
      return false
    }

    if let host = activity.pageHost, isDistractingHost(host) {
      return false
    }

    return true
  }

  private func isDistractingHost(_ host: String) -> Bool {
    let normalizedHost = host.replacingOccurrences(of: "www.", with: "")
    return distractingHosts.contains(normalizedHost)
      || distractingHosts.contains(where: { normalizedHost.hasSuffix(".\($0)") })
  }
}
