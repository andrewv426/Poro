import AppKit
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
  var composerMode: ComposerMode = .normal
  var focusSetupDraft: FocusStartDraft = .default
  var isFocusPanelTucked: Bool = false

  func chatController(for context: AssistantPanelContext) -> ChatController {
    context == .focus ? focusChatController : chatController
  }

  var onDismissRequested: (() -> Void)?
  var onPresentRequested: (() -> Void)?
  var onReactivateRequested: (() -> Void)?

  private let intentRouter: AppIntentRouter
  private let spotifyController = SpotifyController()
  private let customDurationKey = "focus.customDurationMinutes"
  static let durationPresets = [25, 45, 60]

  var lastCustomDurationMinutes: Int? {
    let value = UserDefaults.standard.integer(forKey: customDurationKey)
    return value > 0 ? value : nil
  }

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
      // Fast-path the full-verb trigger so power users typing "/play " in one go skip the menu.
      if text == "/play ", isComposerEligibleForChipTrigger {
        composerMode = .spotifyPlay(query: "")
        composerDraft = ""
        setComposerHint(ComposerHint(title: "↵ Resume Spotify"), in: context)
        return
      }

      // Slash-menu mode: text begins with "/" and the user is still typing the verb (no space yet).
      if text.hasPrefix("/") {
        let prefix = String(text.dropFirst())
        if !prefix.contains(" ") {
          let matches = SlashCommandRegistry.matches(prefix: prefix)
          if !matches.isEmpty {
            composerMode = .slashMenu(prefix: prefix, matches: matches)
            composerDraft = text
            setComposerHint(nil, in: context)
            return
          }
          // No matches but still slash-prefix: fall through to plain text editing, drop the menu.
        }
      }

      // User backed out of the slash menu (e.g. deleted the slash, or typed past the verb).
      if case .slashMenu = composerMode {
        composerMode = .normal
      }

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

  /// True when the composer is in a state that can transition straight into chip mode via the
  /// full-verb fast path. Either the user typed "/play " from scratch or they were in the menu.
  private var isComposerEligibleForChipTrigger: Bool {
    switch composerMode {
    case .normal, .slashMenu:
      true
    case .spotifyPlay:
      false
    }
  }

  /// Invoked from the slash-menu UI when the user selects a command (Enter or click).
  func selectSlashCommand(_ descriptor: SlashCommandDescriptor) {
    switch descriptor.id {
    case "play":
      composerMode = .spotifyPlay(query: "")
      composerDraft = ""
      setComposerHint(ComposerHint(title: "↵ Resume Spotify"), in: .normal)
    default:
      composerMode = .normal
      composerDraft = ""
    }
  }

  /// Esc inside the slash menu — close the menu and clear the slash text so the composer is fresh.
  func dismissSlashMenu() {
    guard case .slashMenu = composerMode else { return }
    composerMode = .normal
    composerDraft = ""
    refreshComposerHint(in: .normal)
  }

  /// Updates the query portion of the Spotify chip. Refreshes the composer hint to reflect
  /// resume vs play.
  func setSpotifyQuery(_ query: String) {
    guard case .spotifyPlay = composerMode else { return }
    composerMode = .spotifyPlay(query: query)
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    composerHint = ComposerHint(title: trimmed.isEmpty ? "↵ Resume Spotify" : "↵ Play on Spotify")
  }

  /// Exits Spotify chip mode and clears the composer entirely. Backspacing out of an empty chip
  /// should leave the user with a fresh raw composer, not "/play " residue.
  func exitSpotifyMode() {
    composerMode = .normal
    composerDraft = ""
    refreshComposerHint(in: .normal)
  }

  func submitComposer(in context: AssistantPanelContext) {
    // If the normal-chat composer is in Spotify chip mode, synthesize the canonical "/play [query]"
    // string and reset the mode before falling into the existing router path.
    let submission: String
    if context == .normal, case let .spotifyPlay(query) = composerMode {
      let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
      submission = trimmedQuery.isEmpty ? "/play" : "/play \(trimmedQuery)"
      composerMode = .normal
    } else {
      submission = composerDraft(for: context)
    }

    let trimmed = submission.trimmingCharacters(in: .whitespacesAndNewlines)

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
    case let .spotify(command):
      // Slash commands are normal-chat only. In focus chat we fall through to a regular LLM message
      // so users typing "/play foo" mid-session don't get surprising behavior.
      guard context == .normal else {
        setRoute(.chat, in: context)
        setComposerDraft("", in: context)
        setComposerHint(nil, in: context)
        chatController(for: context).send(trimmed)
        return
      }
      setRoute(.chat, in: context)
      setComposerDraft("", in: context)
      setComposerHint(nil, in: context)
      handleSpotifyCommand(command, originalText: trimmed)
    }
  }

  func cancelFocusSetup() {
    panelRoute = .chat
    refreshComposerHint(in: .normal)
  }

  func confirmFocusSetup() {
    let goal = focusSetupDraft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let duration = max(1, min(240, focusSetupDraft.durationMinutes))

    if !PoroController.durationPresets.contains(duration) {
      UserDefaults.standard.set(duration, forKey: customDurationKey)
    }

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

  private func handleSpotifyCommand(_ command: SpotifyCommand, originalText: String) {
    // Hint to the system that Spotify is about to activate (intentional) so the snap-back behaves
    // cooperatively on macOS 14+. No-op on the Web API path because Spotify never activates there.
    if #available(macOS 14.0, *), case .play(query: .some) = command {
      NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.spotify.client")
    }
    spotifyController.execute(command) { [weak self] outcome in
      self?.appendSpotifyExchange(originalText: originalText, outcome: outcome)
    }
  }

  private func appendSpotifyExchange(originalText: String, outcome: SpotifyOutcome) {
    if outcome.requiresReactivation {
      onReactivateRequested?()
    }

    let assistantText = switch outcome.result {
    case let .played(query):
      "Now playing on Spotify: \(query)"
    case .resumed:
      "Resumed Spotify playback."
    case let .launchFailed(reason):
      "Couldn't open Spotify: \(reason)"
    case .notAuthorized:
      "Spotify automation isn't allowed. Enable Poro under System Settings → Privacy & Security → Automation."
    case let .scriptError(message):
      "Spotify didn't respond: \(message)"
    case .authNeeded:
      "Connect Poro to Spotify to use /play (see ~/.config/poro/env for SPOTIFY_CLIENT_ID)."
    case .premiumRequired:
      "Spotify Web API requires Premium."
    case let .networkError(reason):
      "Couldn't reach Spotify: \(reason)"
    }

    chatController.appendLocalExchange(userText: originalText, assistantText: assistantText)
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
