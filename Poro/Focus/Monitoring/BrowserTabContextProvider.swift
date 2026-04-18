import Foundation

struct BrowserTabContextProvider {
  enum BrowserApp: Equatable {
    case chrome
    case safari
    case arc
    case brave

    init?(bundleIdentifier: String?) {
      switch bundleIdentifier {
      case "com.google.Chrome":
        self = .chrome
      case "com.apple.Safari":
        self = .safari
      case "company.thebrowser.Browser":
        self = .arc
      case "com.brave.Browser":
        self = .brave
      default:
        return nil
      }
    }

    var applescriptApplicationName: String {
      switch self {
      case .chrome:
        return "Google Chrome"
      case .safari:
        return "Safari"
      case .arc:
        return "Arc"
      case .brave:
        return "Brave Browser"
      }
    }

    var urlScript: String {
      switch self {
      case .safari:
        return "tell application \"Safari\" to get URL of current tab of front window"
      case .chrome, .arc, .brave:
        return
          "tell application \"\(applescriptApplicationName)\" to get URL of active tab of front window"
      }
    }
  }

  func browser(for bundleIdentifier: String?) -> BrowserApp? {
    BrowserApp(bundleIdentifier: bundleIdentifier)
  }

  func activeTabURL(for browser: BrowserApp) -> URL? {
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: browser.urlScript)
    let result = script?.executeAndReturnError(&errorInfo)

    if errorInfo != nil {
      return nil
    }

    guard let stringValue = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !stringValue.isEmpty
    else {
      return nil
    }

    return URL(string: stringValue)
  }
}
