import Foundation

enum PanelRoute: Equatable {
  case chat
  case focusSetup
  case summary
}

enum AssistantPanelContext: Equatable {
  case normal
  case focus
}

enum SessionCommand: Equatable {
  case pause
  case resume
  case end
  case status
}

enum AppIntent: Equatable {
  case chat(String)
  case startFocus(FocusStartDraft)
  case sessionCommand(SessionCommand)
  case spotify(SpotifyCommand)
}

struct ComposerHint: Equatable {
  let title: String
}
