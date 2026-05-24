import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class PoroController {
  let chatController: ChatController
  let focusChatController: ChatController
  let focusSessionController: FocusSessionController
  let spotifyPlaybackPoller: SpotifyPlaybackPoller

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

  var spotifyIsPlaying: Bool {
    spotifyPlaybackPoller.isPlayingMusic
  }

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
    spotifyPlaybackPoller = SpotifyPlaybackPoller()

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
      if panelRoute != .summary, panelRoute != .focusSetup, panelRoute != .settings {
        panelRoute = .chat
      }
      // Only the normal-chat panel needs playback polling — focus chat never shows Spotify controls.
      spotifyPlaybackPoller.startObserving()
    case .focus:
      if focusPanelRoute != .summary {
        focusPanelRoute = .chat
      }
    }

    refreshComposerHint(in: context)
  }

  func panelWasHidden(_ context: AssistantPanelContext) {
    if context == .normal {
      spotifyPlaybackPoller.stopObserving()
    }
  }

  func openSettings() {
    withoutAnimation {
      panelRoute = .settings
      composerHint = nil
    }
  }

  func closeSettings() {
    withoutAnimation {
      panelRoute = .chat
      refreshComposerHint(in: .normal)
    }
  }

  func updateComposerDraft(_ text: String, in context: AssistantPanelContext) {
    switch context {
    case .normal:
      // Mode transitions cascade multiple state mutations (composerMode + composerHint, plus
      // showsFooterStrip flipping false→true when the hint appears). Wrap each cluster in an
      // animation-suppressing transaction so ContentView's ambient `.animation(value:)` modifiers
      // don't pick up the cascade and produce a flicker.

      // Fast-path the full-verb trigger so power users typing "/play " in one go skip the menu.
      if text == "/play ", isComposerEligibleForChipTrigger {
        withoutAnimation {
          composerMode = .spotifyPlay(query: "")
          composerDraft = ""
          setComposerHint(ComposerHint(title: "↵ Resume Spotify"), in: context)
        }
        return
      }

      if text == "/focus ", isComposerEligibleForChipTrigger {
        withoutAnimation {
          composerMode = .focusStart(args: "")
          composerDraft = ""
          setComposerHint(ComposerHint(title: "↵ Set up focus session"), in: context)
        }
        return
      }

      // Slash-menu mode: text begins with "/" and the user is still typing the verb (no space yet).
      if text.hasPrefix("/") {
        let prefix = String(text.dropFirst())
        if !prefix.contains(" ") {
          let matches = SlashCommandRegistry.matches(prefix: prefix, spotifyPlaying: spotifyIsPlaying)
          if !matches.isEmpty {
            withoutAnimation {
              composerMode = .slashMenu(prefix: prefix, matches: matches)
              composerDraft = text
              setComposerHint(nil, in: context)
            }
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

  /// Pre-keystroke handler for the space character. When the current draft is exactly `/play`
  /// or `/focus`, transition into chip mode synchronously and tell the caller to consume the
  /// keystroke (`return true`). This avoids the one-frame "/play " ghost in the NSTextField
  /// field editor before SwiftUI's deferred render pass updates the binding to empty.
  ///
  /// Returns false to let AppKit insert the space normally.
  func handleChipTriggerSpace(currentDraft: String) -> Bool {
    guard isComposerEligibleForChipTrigger else { return false }
    if currentDraft == "/play" {
      withoutAnimation {
        composerMode = .spotifyPlay(query: "")
        composerDraft = ""
        setComposerHint(ComposerHint(title: "↵ Resume Spotify"), in: .normal)
      }
      return true
    }
    if currentDraft == "/focus" {
      withoutAnimation {
        composerMode = .focusStart(args: "")
        composerDraft = ""
        setComposerHint(ComposerHint(title: "↵ Set up focus session"), in: .normal)
      }
      return true
    }
    return false
  }

  /// True when the composer is in a state that can transition straight into chip mode via the
  /// full-verb fast path. Either the user typed "/play " from scratch or they were in the menu.
  private var isComposerEligibleForChipTrigger: Bool {
    switch composerMode {
    case .normal, .slashMenu:
      true
    case .spotifyPlay, .spotifyPlaylistChip, .spotifyOptionPicker, .focusStart:
      false
    }
  }

  /// Invoked from the slash-menu UI when the user selects a command (Enter or click).
  func selectSlashCommand(_ descriptor: SlashCommandDescriptor) {
    // Wrap the cascade in a no-animation transaction so SwiftUI doesn't pick up the ambient
    // shellAnimation/fadeAnimation modifiers that observe composerMode / composerHint /
    // showsFooterStrip. Without this, picking `/play` from the menu fires three concurrent
    // animations (mode → chip, hint → "Resume Spotify", footer strip appears) and the
    // overlapping fades read as a flicker.
    withoutAnimation {
      switch descriptor.id {
      case "play":
        composerMode = .spotifyPlay(query: "")
        composerDraft = ""
        setComposerHint(ComposerHint(title: "↵ Resume Spotify"), in: .normal)
      case "focus":
        composerMode = .focusStart(args: "")
        composerDraft = ""
        setComposerHint(ComposerHint(title: "↵ Set up focus session"), in: .normal)
      case "stop":
        composerMode = .normal
        composerDraft = ""
        setComposerHint(nil, in: .normal)
        handleSpotifyCommand(.pause, originalText: "/stop")
      case "skip":
        composerMode = .normal
        composerDraft = ""
        setComposerHint(nil, in: .normal)
        handleSpotifyCommand(.skip, originalText: "/skip")
      case "shuffle":
        // Default to enabling shuffle from the menu; explicit `/shuffle off` requires typing.
        composerMode = .normal
        composerDraft = ""
        setComposerHint(nil, in: .normal)
        handleSpotifyCommand(.shuffle(enabled: true), originalText: "/shuffle")
      default:
        composerMode = .normal
        composerDraft = ""
      }
    }
  }

  /// Esc inside the slash menu — close the menu and clear the slash text so the composer is fresh.
  func dismissSlashMenu() {
    guard case .slashMenu = composerMode else { return }
    withoutAnimation {
      composerMode = .normal
      composerDraft = ""
      refreshComposerHint(in: .normal)
    }
  }

  /// Updates the query portion of the Spotify chip. Refreshes the composer hint to reflect
  /// resume vs play. Called on every keystroke in chip mode — the no-animation transaction is
  /// critical here: without it, every keystroke that crosses the empty↔non-empty boundary
  /// flips composerHint and fires a 0.22s fadeAnimation, which is the typing flicker the user
  /// reported.
  func setSpotifyQuery(_ query: String) {
    guard case .spotifyPlay = composerMode else { return }
    withoutAnimation {
      composerMode = .spotifyPlay(query: query)
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
      composerHint = ComposerHint(title: trimmed.isEmpty ? "↵ Resume Spotify" : "↵ Play on Spotify")
    }
  }

  /// Exits Spotify chip mode and clears the composer entirely. Backspacing out of an empty chip
  /// should leave the user with a fresh raw composer, not "/play " residue.
  func exitSpotifyMode() {
    withoutAnimation {
      composerMode = .normal
      composerDraft = ""
      refreshComposerHint(in: .normal)
    }
  }

  /// Picker arrow-key navigation.
  func setPickerSelectedIndex(_ index: Int) {
    guard case let .spotifyOptionPicker(state) = composerMode else { return }
    let clamped = max(0, min(state.options.count - 1, index))
    composerMode = .spotifyOptionPicker(state: SpotifyPickerState(
      kind: state.kind,
      query: state.query,
      options: state.options,
      selectedIndex: clamped
    ))
  }

  /// Picker selection — Enter / click. Routes the chosen option through the Spotify command path.
  func confirmPickerSelection() {
    guard case let .spotifyOptionPicker(state) = composerMode else { return }
    guard !state.options.isEmpty else { return }
    let option = state.options[max(0, min(state.options.count - 1, state.selectedIndex))]
    withoutAnimation {
      composerMode = .normal
      composerDraft = ""
      refreshComposerHint(in: .normal)
    }

    let displayName = option.title
    let originalText: String
    let command: SpotifyCommand
    switch state.kind {
    case .track:
      command = .pickTrack(uri: option.uri, displayName: displayName)
      originalText = "/play \(displayName)"
    case .playlist:
      command = .pickPlaylist(uri: option.uri, displayName: displayName)
      originalText = "/play playlist \(displayName)"
    }
    handleSpotifyCommand(command, originalText: originalText)
  }

  /// Picker Escape — back out to the originating chip mode with the user's typed query restored.
  func cancelPicker() {
    guard case let .spotifyOptionPicker(state) = composerMode else { return }
    withoutAnimation {
      switch state.kind {
      case .track:
        composerMode = .spotifyPlay(query: state.query)
        composerHint = ComposerHint(title: state.query.isEmpty ? "↵ Resume Spotify" : "↵ Play on Spotify")
      case .playlist:
        composerMode = .spotifyPlaylistChip(query: state.query)
        composerHint = ComposerHint(title: "↵ Pick a playlist")
      }
    }
  }

  func setFocusArgs(_ args: String) {
    guard case .focusStart = composerMode else { return }
    withoutAnimation {
      composerMode = .focusStart(args: args)
      composerHint = ComposerHint(title: "↵ Set up focus session")
    }
  }

  func exitFocusMode() {
    withoutAnimation {
      composerMode = .normal
      composerDraft = ""
      refreshComposerHint(in: .normal)
    }
  }

  func submitComposer(in context: AssistantPanelContext) {
    // If the normal-chat composer is in Spotify chip mode, synthesize the canonical "/play [query]"
    // string and reset the mode before falling into the existing router path.
    let submission: String
    if context == .normal, case let .spotifyPlay(query) = composerMode {
      let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
      submission = trimmedQuery.isEmpty ? "/play" : "/play \(trimmedQuery)"
    } else if context == .normal, case let .focusStart(args) = composerMode {
      let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
      submission = trimmedArgs.isEmpty ? "/focus" : "/focus \(trimmedArgs)"
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

    // Every intent below mutates composerMode + composerHint + composerDraft in the same
    // render cycle; wrap each cluster in an animation-suppressing transaction so the ambient
    // .animation(value:) modifiers in ContentView don't drive a flicker.
    switch intent {
    case let .chat(message):
      withoutAnimation {
        composerMode = .normal
        setRoute(.chat, in: context)
        setComposerDraft("", in: context)
        setComposerHint(nil, in: context)
      }
      chatController(for: context).send(message)
    case let .startFocus(draft):
      withoutAnimation {
        composerMode = .normal
        setComposerDraft("", in: context)
        setComposerHint(nil, in: context)
        focusSetupDraft = FocusStartDraft(
          goal: draft.goal,
          durationMinutes: draft.durationMinutes
        )
        panelRoute = .focusSetup
      }
    case let .sessionCommand(command):
      withoutAnimation {
        composerMode = .normal
        setComposerDraft("", in: context)
        setComposerHint(nil, in: context)
      }
      handleSessionCommand(command, originalText: trimmed, in: context)
    case let .spotify(command):
      // Slash commands are normal-chat only. In focus chat we fall through to a regular LLM message
      // so users typing "/play foo" mid-session don't get surprising behavior.
      guard context == .normal else {
        withoutAnimation {
          composerMode = .normal
          setRoute(.chat, in: context)
          setComposerDraft("", in: context)
          setComposerHint(nil, in: context)
        }
        chatController(for: context).send(trimmed)
        return
      }

      // For `.play` and `.playPlaylist` submitted from the chip with a non-empty query, fetch
      // options and show the picker rather than playing immediately. Other commands (pause, skip,
      // shuffle, resume `/play` with no query, picker selections) execute directly.
      if case let .play(query) = command, let query, SpotifyAuth.shared.isConfigured {
        withoutAnimation {
          setRoute(.chat, in: context)
          setComposerDraft("", in: context)
          setComposerHint(ComposerHint(title: "Searching Spotify…"), in: context)
        }
        fetchTrackPicker(query: query)
        return
      }
      if case let .playPlaylist(query) = command, SpotifyAuth.shared.isConfigured {
        withoutAnimation {
          setRoute(.chat, in: context)
          setComposerDraft("", in: context)
          setComposerHint(ComposerHint(title: "Loading playlists…"), in: context)
        }
        fetchPlaylistPicker(query: query)
        return
      }

      withoutAnimation {
        composerMode = .normal
        setRoute(.chat, in: context)
        setComposerDraft("", in: context)
        setComposerHint(nil, in: context)
      }
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
    withoutAnimation {
      panelRoute = .chat
      focusPanelRoute = .chat
      composerDraft = ""
      focusComposerDraft = ""
      composerHint = nil
      focusComposerHint = nil
    }
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

  // MARK: - Spotify picker fetch

  private func fetchTrackPicker(query: SpotifyPlayQuery) {
    let originalQuery = composerDraftLabel(for: query)
    Task { @MainActor in
      let api = SpotifyWebAPI(auth: SpotifyAuth.shared)
      do {
        let hits = try await api.searchTracks(query, limit: 5)
        guard !hits.isEmpty else {
          withoutAnimation {
            self.composerMode = .normal
            self.composerHint = nil
          }
          self.chatController.appendLocalExchange(
            userText: "/play \(originalQuery)",
            assistantText: "No matches on Spotify for \(originalQuery)."
          )
          return
        }
        let options = hits.map {
          SpotifyPickerOption(id: $0.uri, uri: $0.uri, title: $0.displayName, subtitle: nil)
        }
        // Suppress ambient animations on the chip→picker transition: composerMode swap and
        // composerHint update fire in the same render cycle, and ContentView's
        // .animation(fadeAnimation, value: composerHint) would otherwise cross-fade the hint
        // over the picker insertion.
        withoutAnimation {
          self.composerMode = .spotifyOptionPicker(state: SpotifyPickerState(
            kind: .track,
            query: originalQuery,
            options: options,
            selectedIndex: 0
          ))
          self.composerHint = ComposerHint(title: "↑↓ to choose · ↵ to play")
        }
      } catch {
        withoutAnimation {
          self.composerMode = .normal
          self.composerHint = nil
        }
        self.chatController.appendLocalExchange(
          userText: "/play \(originalQuery)",
          assistantText: "Couldn't reach Spotify: \(error.localizedDescription)"
        )
      }
    }
  }

  private func fetchPlaylistPicker(query: String?) {
    Task { @MainActor in
      let api = SpotifyWebAPI(auth: SpotifyAuth.shared)
      do {
        let userHits = try await api.userPlaylists()
        let filtered: [SpotifyPlaylistHit] = if let query, !query.isEmpty {
          userHits.filter { $0.name.lowercased().contains(query.lowercased()) }
        } else {
          userHits
        }
        guard !filtered.isEmpty else {
          withoutAnimation {
            self.composerMode = .normal
            self.composerHint = nil
          }
          let displayQuery = query?.isEmpty == false ? " for \(query!)" : ""
          self.chatController.appendLocalExchange(
            userText: query.map { "/play playlist \($0)" } ?? "/play playlist",
            assistantText: "No playlists found\(displayQuery)."
          )
          return
        }
        let options = filtered.prefix(8).map {
          SpotifyPickerOption(
            id: $0.id,
            uri: $0.uri,
            title: $0.name,
            subtitle: $0.ownerName.map { "by \($0)" }
          )
        }
        withoutAnimation {
          self.composerMode = .spotifyOptionPicker(state: SpotifyPickerState(
            kind: .playlist,
            query: query ?? "",
            options: Array(options),
            selectedIndex: 0
          ))
          self.composerHint = ComposerHint(title: "↑↓ to choose · ↵ to play")
        }
      } catch {
        withoutAnimation {
          self.composerMode = .normal
          self.composerHint = nil
        }
        self.chatController.appendLocalExchange(
          userText: query.map { "/play playlist \($0)" } ?? "/play playlist",
          assistantText: "Couldn't reach Spotify: \(error.localizedDescription)"
        )
      }
    }
  }

  private func composerDraftLabel(for query: SpotifyPlayQuery) -> String {
    switch query {
    case let .freeform(text): text
    case let .trackByArtist(track, artist): "\(track) by \(artist)"
    }
  }

  private func handleSpotifyCommand(_ command: SpotifyCommand, originalText: String) {
    // Hint to the system that Spotify is about to activate (intentional) so the snap-back behaves
    // cooperatively on macOS 14+. No-op on the Web API path because Spotify never activates there.
    if #available(macOS 14.0, *), shouldHintActivation(for: command) {
      NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.spotify.client")
    }
    spotifyController.execute(command) { [weak self] outcome in
      self?.appendSpotifyExchange(originalText: originalText, outcome: outcome)
      // Nudge the playback state so the menu reacts faster than the 10-second poll tick.
      self?.spotifyPlaybackPoller.refreshNow()
    }
  }

  private func shouldHintActivation(for command: SpotifyCommand) -> Bool {
    switch command {
    case .play(query: .some), .playPlaylist, .pickTrack, .pickPlaylist:
      true
    case .play(query: .none), .pause, .skip, .shuffle:
      false
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
    case .paused:
      "Paused Spotify."
    case .skipped:
      "Skipped to the next track."
    case let .shuffleSet(enabled):
      enabled ? "Shuffle on." : "Shuffle off."
    case let .playlistStarted(name):
      "Now playing playlist: \(name)"
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
    case .nothingPlaying:
      "Nothing is playing on Spotify right now."
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

  /// Run a body inside a transaction that fully suppresses SwiftUI's implicit animations,
  /// even in subtrees that have an explicit `.animation(value:)` modifier in scope.
  ///
  /// `Transaction(animation: nil)` alone is NOT enough: an explicit `.animation(animation,
  /// value:)` modifier *rewrites* `transaction.animation` for its subtree, overriding the nil
  /// we set at the source. Setting `disablesAnimations = true` flags the transaction as
  /// "really don't animate" — the explicit modifiers honor it and skip the animation.
  ///
  /// Use this anywhere we mutate composer state that ContentView animates implicitly
  /// (e.g. `composerHint` via `.animation(PoroTheme.fadeAnimation, value: composerHint)`).
  private func withoutAnimation(_ body: () -> Void) {
    var txn = Transaction(animation: nil)
    txn.disablesAnimations = true
    withTransaction(txn, body)
  }
}
