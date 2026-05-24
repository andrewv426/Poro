import Foundation
import Observation

@Observable
@MainActor
final class AppearanceController {
  static let shared = AppearanceController()

  private(set) var preset: AccentPreset

  @ObservationIgnored
  var onPresetChange: (() -> Void)?

  private init() {
    let stored = UserDefaults.standard.string(forKey: SettingsKeys.accentPresetID)
    preset = AccentPalette.preset(for: stored)
  }

  func setPreset(_ preset: AccentPreset) {
    guard preset.id != self.preset.id else { return }
    self.preset = preset
    UserDefaults.standard.set(preset.id, forKey: SettingsKeys.accentPresetID)
    onPresetChange?()
  }
}
