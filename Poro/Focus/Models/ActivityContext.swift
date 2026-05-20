import Foundation

struct ActivityContext: Equatable {
  let applicationName: String
  let bundleIdentifier: String?
  let processIdentifier: Int32
  let pageURL: URL?
  let pageTitle: String?
  let pageAccessError: String?

  init(
    applicationName: String,
    bundleIdentifier: String?,
    processIdentifier: Int32,
    pageURL: URL? = nil,
    pageTitle: String? = nil,
    pageAccessError: String? = nil
  ) {
    self.applicationName = applicationName
    self.bundleIdentifier = bundleIdentifier
    self.processIdentifier = processIdentifier
    self.pageURL = pageURL
    self.pageTitle = pageTitle
    self.pageAccessError = pageAccessError
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
