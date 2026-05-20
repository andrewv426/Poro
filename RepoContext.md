# Poro Repo Context

This file is for future LLM coding sessions. It should stay concise, current, and focused on facts that help an agent avoid rediscovering the repo.

## What Poro Is

Poro is a macOS floating assistant app written in Swift, SwiftUI, and AppKit. It uses an always-on-top `NSPanel` experience with two separate surfaces:

- Normal chat: a centered 560 px general assistant panel, toggled with `Cmd+Option+T`.
- Focus mode: a 420 px left-edge panel used during focus sessions. It can tuck into a draggable Poro icon tab and expand when distractions are detected.

The LLM backend is Cerebras chat completions. API settings are loaded from environment variables in `LLMConfiguration`:

- `CEREBRAS_API_KEY`
- `CEREBRAS_MODEL`, default `llama3.1-8b`
- `CEREBRAS_BASE_URL`, default `https://api.cerebras.ai/v1`
- `CEREBRAS_VERSION_PATCH`, optional header

## Architecture

Core ownership:

| Type | Responsibility |
| --- | --- |
| `AssistantWindowController` | Owns normal/focus `NSPanel`s, frame math, animation, keyboard movement, focus tab dragging. |
| `PoroController` | App state, routing, normal/focus `ChatController`s, composer drafts, intent routing. |
| `ChatController` | Chat history, streaming state, LLM calls, assistant-only injected prompts. |
| `CerebrasLLMClient` | Streaming chat completion client and base system prompt composition. |
| `FocusSessionController` | Focus session lifecycle, timer, activity logging, distraction detection, pending close/explain flow. |
| `FrontmostActivityMonitor` | Polls/frontmost app monitoring and enriches browsers with active tab metadata. |
| `BrowserTabContextProvider` | AppleScript URL/title lookup and active-tab close-if-URL-matches behavior. |
| `DistractionPolicy` | Static distraction rules and "should ask LLM classifier" gate. |
| `ContentView` | Shared SwiftUI root for normal and focus panel contexts. |

Panel contexts are explicit through `AssistantPanelContext`:

- `.normal` uses `chatController`, `panelRoute`, `composerDraft`, normal panel dimensions.
- `.focus` uses `focusChatController`, `focusPanelRoute`, `focusComposerDraft`, focus panel dimensions.

Do not collapse normal and focus chat histories. Distraction messages belong only in focus chat.

## Current Focus Behavior

Focus session start:

1. User starts focus through normal chat intent.
2. `PoroController.confirmFocusSetup()` starts `FocusSessionController`, resets the focus chat history, and dismisses normal chat.
3. `AssistantWindowController.handleSessionStateChange()` enters tucked focus mode.
4. The focus tab appears on the left edge. It is draggable vertically and stores placement in `UserDefaults` key `poro.focusPanel.tabTopRatio`.

Distraction detection:

1. `FrontmostActivityMonitor` emits `ActivityContext` with app bundle, PID, and browser `pageURL` / `pageTitle` when supported.
2. `FocusSessionController.handleActivityChange()` ignores Poro itself, inactive sessions, overrides, and active nudges.
3. `DistractionPolicy.staticHit(activity:)` catches always-distracting apps and hardcoded hosts.
4. Unknown browser tabs with URL metadata go to `DistractionClassifying`.
5. The LLM classifier only triggers a nudge when verdict is `distract` and score is at least `0.72`.
6. A 2 second `DriftWatchdog` debounce runs before the focus panel expands.

Pending browser distraction flow:

- For supported browser tabs with a URL, `PendingDistraction` is created with a 10 second deadline.
- The focus panel expands and shows two choices:
  - Close tab.
  - Explain why the tab needs to stay open.
- If the user clicks "Explain why", the countdown is cancelled.
- If the user submits an explanation, a 5 minute override is granted and the focus panel tucks back to the Poro icon.
- If the user closes the tab manually, Poro closes only when the active tab URL still exactly matches the flagged URL, then tucks back.
- If the 10 second countdown expires, Poro attempts the same URL-matched close.
- Failed close cases stay expanded so the user can see the failure message.

Important: tab closing is intentionally conservative. It should never close a tab unless the current active tab URL still exactly matches the originally flagged URL.

## Keyboard And Window Behavior

- `Cmd+Option+T` toggles the normal chat panel. During focus sessions this must not open or mutate the focus chat.
- `Cmd+Option+Arrow` nudges only the normal chat panel. It should run only when the normal panel is visible, key, and owns the key event.
- The focus tab is draggable only; it should not open focus chat by click.
- Escape in focus panel tucks to the icon while a session is active.
- Successful distraction resolution tucks the focus panel back to the icon.

Key dimensions in `PoroTheme`:

```swift
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
```

## Callback Ownership

These callbacks are single-owner slots. Avoid assigning another owner unless you first refactor them into multicast callbacks.

| Callback | Owner |
| --- | --- |
| `focusSessionController.onSessionStateChange` | `AssistantWindowController` |
| `focusSessionController.onStatusItemUpdate` | `StatusItemController` |
| `focusSessionController.onDistractionDetected` | `AssistantWindowController` |
| `focusSessionController.onDistractionResolved` | `AssistantWindowController` |
| `focusSessionController.onSummaryAvailable` | `PoroController` |
| `poroController.onDismissRequested` | `AssistantWindowController` |
| `poroController.onPresentRequested` | `AssistantWindowController` |

## Prompt Inventory

Base chat system prompt, added by `CerebrasLLMClient` for all chat completions:

```text
You are Poro, a macOS assistant that is actively backed by an LLM.
The chat completion provider is Cerebras.
The configured model for this request is <configuration.model>.
If the user asks whether you are running an LLM or what model you use, answer directly using this information.
```

Normal chat focus-read toolbox prompt, appended when the normal chat client has `FocusReadToolbox`:

```text
You are a focus coach and general assistant integrated into a macOS app called Poro.
The user invokes you via a hotkey, and you respond to whatever they ask.

Below is the current [SYSTEM_CONTEXT] from the user's computer. Use this information to answer the user's question accurately.
Never mention the words 'context', 'tool', 'JSON', or 'system' to the user.
Synthesize the information into a natural, warm, and direct response. Speak like a coach.

[SYSTEM_CONTEXT]
{{CONTEXT}}

If the [SYSTEM_CONTEXT] reports that there is no active focus session and the user's question implies one, clarify that there is no session running right now and ask whether they want to start one.
```

Focus distraction assistant-only injection prompt in `PoroController.injectDistractionMessage(activity:)`:

```text
The user is working on '<goal>' and opened <distractionLabel>. A focus guard is asking the user to either close the tab or explain why it needs to stay open. Address the user directly as 'you'. Do not speak as the user or use first-person wording like 'I', 'me', or 'my'. Gently redirect them back without being preachy - one or two sentences max.
```

Focus override decision system prompt in `CerebrasFocusDecisionClient.evaluateDecision(...)`:

```text
You are a strict but fair focus coach.
Decide whether the user should be allowed to keep using the distracting activity they were just caught on.
Only allow if the justification is concrete, relevant to the stated goal, and time-bounded.
Deny vague avoidance, generic breaks, and low-accountability excuses.
Keep the message short, direct, and user-facing.
```

Focus override decision user prompt:

```text
Goal: <goal>
Remaining minutes: <remainingMinutes>
Current activity: <activity.applicationName>
Justification: <justification>
Nudges so far: <nudgesToday>
Allowed overrides so far: <allowedOverrides>

Return JSON only.
```

LLM browser distraction classifier system prompt in `CerebrasFocusDecisionClient.classifyDistraction(...)`:

```text
You classify whether a browser tab is distracting for the user's current focus session.
Use the goal, URL, host, and page title. Mark distract for unrelated entertainment, social media,
shopping, news, idle browsing, or obvious avoidance. Mark allow for docs, research, work tools,
educational material, or anything plausibly necessary for the stated goal.
Score is the probability from 0.0 to 1.0 that this tab is distracting.
Be conservative near ambiguity: allow unless the tab is likely unrelated to the goal.
Return JSON only.
```

LLM browser distraction classifier user prompt:

```text
Goal: <goal>
Remaining minutes: <remainingMinutes>
Application: <activity.applicationName>
URL: <activity.pageURL>
Host: <activity.pageHost>
Title: <activity.pageTitle>

Return JSON only.
```

## Verification

Fast typecheck used in agent sessions:

```sh
swiftc -typecheck $(rg --files Poro -g '*.swift' | rg -v 'Poro/App/AppDelegate.swift|Poro/KeyboardShortcuts.swift|Poro/PoroApp.swift')
```

Known result: this typecheck should pass.

Full CLI build command:

```sh
xcodebuild -project Poro.xcodeproj -target Poro -configuration Debug -destination platform=macOS build
```

Known caveat: CLI `xcodebuild` currently fails on the `KeyboardShortcuts` SPM/module bundle path:

- `Unable to find module dependency: 'KeyboardShortcuts'`
- missing `KeyboardShortcuts_KeyboardShortcuts.bundle`

This is a known local build issue and not necessarily caused by app code changes. Xcode's full build environment may behave differently.

## Working Notes For Future Agents

- Use `rg` first for search.
- Prefer the repo's existing SwiftUI/AppKit patterns over introducing new abstractions.
- Keep normal and focus panel behavior separate.
- Preserve URL-match safety for browser tab closing.
- Do not add synthetic "I drifted..." user bubbles to focus chat history. Distraction nudges should be assistant-only responses.
- If a focus close/explain flow succeeds, tuck the panel back to the icon. If it fails, keep the panel expanded.
- Do not overwrite unrelated dirty changes. This repo often has active in-progress edits.
