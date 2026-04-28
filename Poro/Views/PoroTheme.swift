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
  static let topAnchorRatio: CGFloat = 0.30
  static let windowCornerRadius: CGFloat = 14
  static let messageSpacing: CGFloat = 24

  static let accent = Color(red: 232 / 255, green: 212 / 255, blue: 168 / 255)
  static let stopColor = Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255)
  static let bodyText = Color.white.opacity(0.92)
  static let assistantBodyText = Color.white.opacity(0.85)
  static let mutedText = Color.white.opacity(0.40)
  static let traceText = Color.white.opacity(0.08)
  static let divider = Color.white.opacity(0.06)
  static let innerBorder = Color.white.opacity(0.08)
  static let hoverBackground = Color.white.opacity(0.06)
  static let windowTint = Color(red: 22 / 255, green: 22 / 255, blue: 28 / 255).opacity(0.62)

  static let shellAnimation = Animation.interactiveSpring(
    response: 0.28,
    dampingFraction: 0.76,
    blendDuration: 0.12
  )
  static let fadeAnimation = Animation.easeOut(duration: 0.22)
}

extension Notification.Name {
  static let normalAssistantWindowDidShow = Notification.Name("normalAssistantWindowDidShow")
  static let focusAssistantWindowDidShow = Notification.Name("focusAssistantWindowDidShow")
}
