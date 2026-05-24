import SwiftUI

enum PoroTheme {
  static let width: CGFloat = 560
  static let focusWidth: CGFloat = 420
  static let focusExpandedSurfaceHeight: CGFloat = 280
  static let focusCollapsedSurfaceHeight: CGFloat = 56
  static let focusCollapsedTotalHeight: CGFloat = 76
  static let tabHeight: CGFloat = 44
  static let tabVisibleWidth: CGFloat = 36
  static let collapsedSurfaceHeight: CGFloat = 56
  static let collapsedTotalHeight: CGFloat = 88
  static let focusSetupHeight: CGFloat = 252
  static let summaryHeight: CGFloat = 330
  static let expandedSurfaceHeight: CGFloat = 480
  static let settingsHeight: CGFloat = 460
  static let topAnchorRatio: CGFloat = 0.30
  static let windowCornerRadius: CGFloat = 14
  static let messageSpacing: CGFloat = 24

  @MainActor static var accent: Color {
    AppearanceController.shared.preset.accent
  }

  @MainActor static var onAccent: Color {
    AppearanceController.shared.preset.onAccent
  }

  static let stopColor = Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255)
  static let bodyText = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
  static let assistantBodyText = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255).opacity(0.85)
  static let mutedText = Color(red: 153 / 255, green: 153 / 255, blue: 153 / 255)
  static let traceText = Color(red: 153 / 255, green: 153 / 255, blue: 153 / 255).opacity(0.5)
  static let divider = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
  static let innerBorder = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
  static let hoverBackground = Color.white.opacity(0.06)
  static let windowTint = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.62)
  static let tabBackground = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.88)

  static let shellAnimation = Animation.interactiveSpring(
    response: 0.28,
    dampingFraction: 0.76,
    blendDuration: 0.12
  )
  static let fadeAnimation = Animation.easeOut(duration: 0.22)

  static func font(size: CGFloat, weight: PoroFontWeight = .regular) -> Font {
    Font.custom(weight.postScriptName, size: size)
  }
}

enum PoroFontWeight {
  case regular
  case medium
  case semibold
  case bold

  var postScriptName: String {
    switch self {
    case .regular: "RadioCanada-Regular"
    case .medium: "RadioCanada-Medium"
    case .semibold: "RadioCanada-SemiBold"
    case .bold: "RadioCanada-Bold"
    }
  }
}

extension Notification.Name {
  static let normalAssistantWindowDidShow = Notification.Name("normalAssistantWindowDidShow")
  static let focusAssistantWindowDidShow = Notification.Name("focusAssistantWindowDidShow")
}
