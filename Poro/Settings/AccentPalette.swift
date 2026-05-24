import AppKit
import SwiftUI

struct AccentPreset: Identifiable, Equatable {
  let id: String
  let displayName: String
  let accent: Color
  let onAccent: Color
  let nsAccent: NSColor
  let nsOnAccent: NSColor

  static func == (lhs: AccentPreset, rhs: AccentPreset) -> Bool {
    lhs.id == rhs.id
  }
}

enum AccentPalette {
  static let mint = preset(
    id: "mint",
    displayName: "Mint",
    accent: (168, 230, 201),
    onAccent: (17, 17, 17)
  )

  static let peach = preset(
    id: "peach",
    displayName: "Peach",
    accent: (255, 196, 168),
    onAccent: (51, 27, 17)
  )

  static let lilac = preset(
    id: "lilac",
    displayName: "Lilac",
    accent: (208, 189, 244),
    onAccent: (33, 23, 51)
  )

  static let sky = preset(
    id: "sky",
    displayName: "Sky",
    accent: (170, 215, 247),
    onAccent: (15, 30, 51)
  )

  static let butter = preset(
    id: "butter",
    displayName: "Butter",
    accent: (247, 224, 142),
    onAccent: (51, 41, 12)
  )

  static let rose = preset(
    id: "rose",
    displayName: "Rose",
    accent: (247, 168, 184),
    onAccent: (51, 17, 27)
  )

  static let sage = preset(
    id: "sage",
    displayName: "Sage",
    accent: (188, 209, 168),
    onAccent: (26, 36, 17)
  )

  static let slate = preset(
    id: "slate",
    displayName: "Slate",
    accent: (180, 196, 210),
    onAccent: (17, 26, 36)
  )

  static let all: [AccentPreset] = [mint, peach, lilac, sky, butter, rose, sage, slate]
  static let `default` = mint

  static func preset(for id: String?) -> AccentPreset {
    all.first { $0.id == id } ?? `default`
  }

  private static func preset(
    id: String,
    displayName: String,
    accent: (Int, Int, Int),
    onAccent: (Int, Int, Int)
  ) -> AccentPreset {
    AccentPreset(
      id: id,
      displayName: displayName,
      accent: Color(red: Double(accent.0) / 255, green: Double(accent.1) / 255, blue: Double(accent.2) / 255),
      onAccent: Color(red: Double(onAccent.0) / 255, green: Double(onAccent.1) / 255, blue: Double(onAccent.2) / 255),
      nsAccent: NSColor(
        srgbRed: CGFloat(accent.0) / 255,
        green: CGFloat(accent.1) / 255,
        blue: CGFloat(accent.2) / 255,
        alpha: 1
      ),
      nsOnAccent: NSColor(
        srgbRed: CGFloat(onAccent.0) / 255,
        green: CGFloat(onAccent.1) / 255,
        blue: CGFloat(onAccent.2) / 255,
        alpha: 1
      )
    )
  }
}
