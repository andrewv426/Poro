import Foundation
import Observation

@Observable
@MainActor
final class PoroController {
  let chatController: ChatController
  let focusSessionController: FocusSessionController

  var panelRoute: PanelRoute = .chat
  var composerDraft = ""
  var composerHint: ComposerHint?
  var focusSetupDraft: FocusStartDraft = .default

  var onDismissRequested: (() -> Void)?
  var onPresentRequested: (() -> Void)?

  private let intentRouter: AppIntentRouter

  init(
    chatController: ChatController,
    focusSessionController: FocusSessionController,
    intentRouter: AppIntentRouter
  ) {
    self.chatController = chatController
    self.focusSessionController = focusSessionController
    self.intentRouter = intentRouter

    focusSessionController.onSummaryAvailable = { [weak self] _ in
      self?.panelRoute = .summary
      self?.onPresentRequested?()
    }
  }

  convenience init() {
    self.init(
      chatController: ChatController(),
      focusSessionController: FocusSessionController(),
      intentRouter: AppIntentRouter()
    )
  }

  var isChatExpanded: Bool {
    panelRoute == .chat && chatController.hasConversation
  }

  var isFocusSessionActive: Bool {
    focusSessionController.hasActiveSession
  }

  var sessionStatusLine: String? {
    focusSessionController.statusLine
  }

  func prepareForPresentation() {
    if panelRoute != .summary && panelRoute != .focusSetup {
      panelRoute = .chat
    }

    refreshComposerHint()
  }

  func updateComposerDraft(_ text: String) {
    if composerDraft != text {
      composerDraft = text
    }
    refreshComposerHint()
  }

  func submitComposer() {
    let trimmed = composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    let intent = intentRouter.resolveSubmission(
      for: trimmed,
      hasActiveSession: focusSessionController.hasActiveSession
    )

    switch intent {
    case .chat(let message):
      panelRoute = .chat
      composerDraft = ""
      composerHint = nil
      chatController.send(message)
    case .startFocus(let draft):
      composerDraft = ""
      composerHint = nil
      focusSetupDraft = FocusStartDraft(
        goal: draft.goal,
        durationMinutes: draft.durationMinutes
      )
      panelRoute = .focusSetup
    case .sessionCommand(let command):
      composerDraft = ""
      composerHint = nil
      handleSessionCommand(command, originalText: trimmed)
    }
  }

  func cancelFocusSetup() {
    panelRoute = .chat
    refreshComposerHint()
  }

  func confirmFocusSetup() {
    let goal = focusSetupDraft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let duration = max(1, focusSetupDraft.durationMinutes)

    focusSessionController.startSession(goal: goal, durationMinutes: duration)
    panelRoute = .chat
    composerDraft = ""
    composerHint = nil
    chatController.startNewConversation()
    onDismissRequested?()
  }

  func dismissSummary() {
    focusSessionController.dismissSummary()
    panelRoute = .chat
  }

  private func handleSessionCommand(_ command: SessionCommand, originalText: String) {
    let response = focusSessionController.handleSessionCommand(command)

    switch command {
    case .end:
      panelRoute = .summary
    case .pause, .resume, .status:
      panelRoute = .chat
      chatController.appendLocalExchange(userText: originalText, assistantText: response)
    }
  }

  private func refreshComposerHint() {
    guard panelRoute == .chat else {
      composerHint = nil
      return
    }

    composerHint = intentRouter.preview(
      for: composerDraft,
      hasActiveSession: focusSessionController.hasActiveSession
    ).hint
  }
}
