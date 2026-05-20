import Foundation
import Observation

@Observable
@MainActor
final class PoroController {
  let chatController: ChatController
  let focusChatController: ChatController
  let focusSessionController: FocusSessionController

  var panelRoute: PanelRoute = .chat
  var focusPanelRoute: PanelRoute = .chat
  var composerDraft = ""
  var focusComposerDraft = ""
  var composerHint: ComposerHint?
  var focusComposerHint: ComposerHint?
  var focusSetupDraft: FocusStartDraft = .default
  var isFocusPanelTucked: Bool = false

  func chatController(for context: AssistantPanelContext) -> ChatController {
    context == .focus ? focusChatController : chatController
  }

  var onDismissRequested: (() -> Void)?
  var onPresentRequested: (() -> Void)?

  private let intentRouter: AppIntentRouter

  init(
    chatController: ChatController,
    focusChatController: ChatController,
    focusSessionController: FocusSessionController,
    intentRouter: AppIntentRouter
  ) {
    self.chatController = chatController
    self.focusChatController = focusChatController
    self.focusSessionController = focusSessionController
    self.intentRouter = intentRouter

    focusSessionController.onSummaryAvailable = { [weak self] _ in
      self?.focusPanelRoute = .summary
      self?.onPresentRequested?()
    }
  }

  convenience init() {
    let focusSessionController = FocusSessionController()
    let chatController: ChatController
    let focusChatController: ChatController

    do {
      let configuration = try LLMConfiguration.loadFromEnvironment()
      let toolbox = FocusReadToolbox(focusSessionController: focusSessionController)
      chatController = ChatController(
        session: ChatSession(),
        llmClient: CerebrasLLMClient(configuration: configuration, toolbox: toolbox)
      )
      focusChatController = ChatController(
        session: ChatSession(),
        llmClient: CerebrasLLMClient(configuration: configuration)
      )
    } catch {
      chatController = ChatController(
        session: ChatSession(),
        llmClient: UnavailableLLMClient(error: error)
      )
      focusChatController = ChatController(
        session: ChatSession(),
        llmClient: UnavailableLLMClient(error: error)
      )
    }

    self.init(
      chatController: chatController,
      focusChatController: focusChatController,
      focusSessionController: focusSessionController,
      intentRouter: AppIntentRouter()
    )
  }

  func route(for context: AssistantPanelContext) -> PanelRoute {
    context == .focus ? focusPanelRoute : panelRoute
  }

  func composerDraft(for context: AssistantPanelContext) -> String {
    context == .focus ? focusComposerDraft : composerDraft
  }

  func composerHint(for context: AssistantPanelContext) -> ComposerHint? {
    context == .focus ? focusComposerHint : composerHint
  }

  func isChatExpanded(in context: AssistantPanelContext) -> Bool {
    route(for: context) == .chat && chatController(for: context).hasConversation
  }

  var isFocusSessionActive: Bool {
    focusSessionController.hasActiveSession
  }

  var sessionStatusLine: String? {
    focusSessionController.statusLine
  }

  func prepareForPresentation(in context: AssistantPanelContext) {
    switch context {
    case .normal:
      if panelRoute != .summary, panelRoute != .focusSetup {
        panelRoute = .chat
      }
    case .focus:
      if focusPanelRoute != .summary {
        focusPanelRoute = .chat
      }
    }

    refreshComposerHint(in: context)
  }

  func updateComposerDraft(_ text: String, in context: AssistantPanelContext) {
    switch context {
    case .normal:
      if composerDraft != text {
        composerDraft = text
      }
    case .focus:
      if focusComposerDraft != text {
        focusComposerDraft = text
      }
    }

    refreshComposerHint(in: context)
  }

  func submitComposer(in context: AssistantPanelContext) {
    let trimmed = composerDraft(for: context).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    let intent = intentRouter.resolveSubmission(
      for: trimmed,
      hasActiveSession: focusSessionController.hasActiveSession
    )

    switch intent {
    case let .chat(message):
      setRoute(.chat, in: context)
      setComposerDraft("", in: context)
      setComposerHint(nil, in: context)
      chatController(for: context).send(message)
    case let .startFocus(draft):
      setComposerDraft("", in: context)
      setComposerHint(nil, in: context)
      focusSetupDraft = FocusStartDraft(
        goal: draft.goal,
        durationMinutes: draft.durationMinutes
      )
      panelRoute = .focusSetup
    case let .sessionCommand(command):
      setComposerDraft("", in: context)
      setComposerHint(nil, in: context)
      handleSessionCommand(command, originalText: trimmed, in: context)
    }
  }

  func cancelFocusSetup() {
    panelRoute = .chat
    refreshComposerHint(in: .normal)
  }

  func confirmFocusSetup() {
    let goal = focusSetupDraft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let duration = max(1, focusSetupDraft.durationMinutes)

    focusSessionController.startSession(goal: goal, durationMinutes: duration)
    panelRoute = .chat
    focusPanelRoute = .chat
    composerDraft = ""
    focusComposerDraft = ""
    composerHint = nil
    focusComposerHint = nil
    focusChatController.startNewConversation()
    onDismissRequested?()
  }

  func dismissSummary() {
    focusSessionController.dismissSummary()
    focusPanelRoute = .chat
  }

  /// Called when a distraction is detected during a focus session.
  /// Streams a Poro response without adding a synthetic user bubble to history.
  func injectDistractionMessage(activity: ActivityContext) {
    guard let session = focusSessionController.activeSession else { return }
    focusPanelRoute = .chat
    let prompt = "The user is working on '\(session.goal)' and opened \(activity.distractionLabel). A focus guard is asking the user to either close the tab or explain why it needs to stay open. Address the user directly as 'you'. Do not speak as the user or use first-person wording like 'I', 'me', or 'my'. Gently redirect them back without being preachy — one or two sentences max."
    focusChatController.injectAssistantPrompt(prompt)
  }

  private func handleSessionCommand(
    _ command: SessionCommand,
    originalText: String,
    in context: AssistantPanelContext
  ) {
    let response = focusSessionController.handleSessionCommand(command)

    switch command {
    case .end:
      focusPanelRoute = .summary
    case .pause, .resume, .status:
      setRoute(.chat, in: context)
      chatController(for: context).appendLocalExchange(userText: originalText, assistantText: response)
    }
  }

  private func setRoute(_ route: PanelRoute, in context: AssistantPanelContext) {
    switch context {
    case .normal:
      panelRoute = route
    case .focus:
      focusPanelRoute = route
    }
  }

  private func setComposerDraft(_ draft: String, in context: AssistantPanelContext) {
    switch context {
    case .normal:
      composerDraft = draft
    case .focus:
      focusComposerDraft = draft
    }
  }

  private func setComposerHint(_ hint: ComposerHint?, in context: AssistantPanelContext) {
    switch context {
    case .normal:
      composerHint = hint
    case .focus:
      focusComposerHint = hint
    }
  }

  private func refreshComposerHint(in context: AssistantPanelContext) {
    guard route(for: context) == .chat else {
      setComposerHint(nil, in: context)
      return
    }

    let draft = composerDraft(for: context)
    let preview = intentRouter.preview(
      for: draft,
      hasActiveSession: focusSessionController.hasActiveSession
    )
    setComposerHint(preview.hint, in: context)
  }
}
