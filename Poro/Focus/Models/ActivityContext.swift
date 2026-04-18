import Foundation

struct ActivityContext: Equatable, Sendable {
  let applicationName: String
  let bundleIdentifier: String?
  let processIdentifier: Int32
  let pageURL: URL?

  init(
    applicationName: String,
    bundleIdentifier: String?,
    processIdentifier: Int32,
    pageURL: URL? = nil
  ) {
    self.applicationName = applicationName
    self.bundleIdentifier = bundleIdentifier
    self.processIdentifier = processIdentifier
    self.pageURL = pageURL
  }

  var pageHost: String? {
    guard let host = pageURL?.host?.lowercased() else {
      return nil
    }

    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  var distractionLabel: String {
    pageHost ?? applicationName
  }
}
