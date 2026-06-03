# Poro — Agent Context

Auto-loaded by Claude Code at the start of every session. For deep details (full prompt inventory, focus state machine, dimension constants), see `RepoContext.md` — that file is the long-form appendix.

---

## 1. What Poro is

Poro is a macOS floating assistant app written in Swift, SwiftUI, and AppKit. It runs as an always-on-top `NSPanel` with two distinct surfaces:

- **Normal chat** — 560 px centered panel, general assistant. Toggle with `Cmd+Option+T`.
- **Focus mode** — 420 px left-edge panel used during focus sessions. Tucks into a draggable Poro icon tab on the left screen edge; expands when a distraction is detected.

Slash commands route deterministically (no LLM round-trip). Currently only `/play <song>` — types into the normal-chat composer and swaps the raw text for a styled `[/play]` chip + query field. Submitting plays the top Spotify search result. When `SPOTIFY_CLIENT_ID` is configured, the **Spotify Web API** (Spotify Connect) is used so the desktop client doesn't steal focus; otherwise (or when no active device is available) Poro falls back to AppleScript and snaps focus back via `onReactivateRequested`. Spotify is launched if not running on the AppleScript path. `<song> by <artist>` parses into a track+artist query for tighter relevance. `SlashCommandParser` runs before any natural-language matchers in `AppIntentRouter`, so new slash verbs are easy to add. See `Poro/Spotify/` and `Poro/App/Intent/SlashCommandParser.swift`.

The LLM backend is **OpenRouter streaming chat completions** (OpenAI-compatible). A single multimodal model serves both text and vision — the user can attach images to a message (paperclip button left of the composer, or drag-drop) and ask about them; images ride along in conversation history so follow-ups keep them in context. Configuration is loaded from environment variables at launch — see the env-var list below. Do not put API keys in source.

Distraction detection runs while a focus session is active. It uses static rules first, then an LLM classifier (the same OpenRouter model, via `CerebrasFocusDecisionClient`) for ambiguous browser tabs. When a distraction is confirmed, the user gets a 10-second close-tab-or-explain prompt. Tab closing is conservative: Poro only closes a tab when its current URL still exactly matches the originally flagged URL.

---

## 2. Tech stack & where things live

### Stack

- **Language:** Swift 5+
- **UI:** SwiftUI for views, AppKit (`NSPanel`) for the always-on-top window
- **Hotkeys:** `KeyboardShortcuts` SPM package (sindresorhus, pinned to 2.4.0)
- **LLM:** OpenRouter chat completions (OpenAI-compatible, streaming, custom client); a single multimodal model handles text + vision
- **Browser integration:** AppleScript for tab URL/title lookup and tab close
- **Build:** Xcode 26.1+ (`Poro.xcodeproj`), single target `Poro`

### Environment variables

Two sources, layered (non-empty process env wins on conflict):

1. **`Poro/Poro.env`** — dotenv-style file (`KEY=VALUE` per line, `#` comments) bundled into the app at build time via Xcode's filesystem-synchronized group. Gitignored. Per-worktree (copy or symlink from `~/.config/poro/env`). Required path because the app is sandboxed and cannot read arbitrary home-directory files at runtime.
2. **Xcode scheme env vars** — Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables. Per-user values live in `xcuserdata/` (gitignored). Convenient for one-off overrides.

For a new worktree, run: `ln -s ~/.config/poro/env Poro/Poro.env` (or `cp`). `~/.config/poro/env` itself is the source of truth for your keys; `Poro/Poro.env` is the bundled copy. The Stop hook auto-creates this symlink if it's missing (see `hooks/ensure-env-symlink.sh`), so a fresh `git worktree add` followed by your first Claude Code turn is enough — no manual step required. If you build via Xcode without ever running the hook (e.g., immediately after `git worktree add`), create the symlink yourself first or the OpenRouter key won't load.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `OPENROUTER_API_KEY` | yes | — | OpenRouter auth (create a free key at https://openrouter.ai/keys) |
| `OPENROUTER_MODEL` | no | `nvidia/nemotron-nano-12b-v2-vl:free` | Vision-capable model id, used for both text and image chat. The Google `gemma-4-*:free` routes are frequently rate-limited upstream (429); the NVIDIA Nemotron VL free route is more reliably available. Other options: a Qwen3-VL `:free` slug |
| `OPENROUTER_BASE_URL` | no | `https://openrouter.ai/api/v1` | API base URL |
| `SPOTIFY_CLIENT_ID` | no | — | Enables the Spotify Web API path for `/play` (Spotify Connect, no focus flicker). Register an app at https://developer.spotify.com/dashboard with redirect URI `poro://spotify-callback`. Without this, `/play` uses the AppleScript fallback (Spotify briefly steals focus). |

The shared `Poro.xcscheme` ships with **empty values** for `OPENROUTER_API_KEY` and `OPENROUTER_MODEL` as discoverability placeholders — never commit real values to `xcshareddata/`. Fill them in Xcode locally (auto-saved to gitignored `xcuserdata/`) or use the bundled `Poro/Poro.env` path above. Note: empty scheme values won't override the bundled file — `mergedEnvironment()` ignores empty strings.

Loaded by `LLMConfiguration.loadFromEnvironment()` (overlay implemented in `EnvFileLoader`).

### Build note — Xcode 26.1.1 workarounds

Two pbxproj-level changes work around Xcode 26.1.1 IDE-only linker bugs. Neither affects `xcodebuild` from the CLI.

1. **`ENABLE_DEBUG_DYLIB = NO`** in both Debug and Release. Default (`YES`) makes the IDE's `Link __preview.dylib` aux phase fail with `cannot get absolute path for: rpath/Poro.debug.dylib` — the linker is asked to emit a dylib with install_name `@rpath/Poro.debug.dylib` but supplied no `-rpath` entries.

2. **`LD_RUNPATH_SEARCH_PATHS = "$(inherited)"`** — the boilerplate `@executable_path/../Frameworks` entry has been removed. Xcode 26.1.1's IDE-side linker validates that rpath directories exist at link time; since Poro uses only static SPM dependencies (no dynamic frameworks copied to `Poro.app/Contents/Frameworks/`), the directory doesn't exist and the linker aborts with `cannot get absolute path for: executable_path/../Frameworks`. CLI `ld` doesn't run this validation. `$(inherited)` retains the auto-added PackageFrameworks rpath.

When Apple ships fixes for these bugs in a future Xcode release, both changes can be reverted to restore IDE fast-debug-link and the boilerplate Frameworks rpath.

### Build note — sandbox blocks `~` reads at runtime

`com.apple.security.app-sandbox = true` is on. At runtime, `FileManager.homeDirectoryForCurrentUser` resolves to `~/Library/Containers/<bundle-id>/Data/` — not `~`. Any path under the real `~` (including `~/.config/poro/env`) is unreadable and `String(contentsOf:)` silently fails. **The app can only read files it ships in `Bundle.main`.**

That's why `EnvFileLoader` reads `Poro.env` from the bundle first, and why `Poro/Poro.env` is symlinked into the source tree from `~/.config/poro/env`. Xcode's `PBXFileSystemSynchronizedRootGroup` auto-detects the file by extension and copies it to `Poro.app/Contents/Resources/Poro.env` at build time. The same gotcha applies to anything else you might want to read from disk — bundle it, or write to the app's sandboxed container.

### Repo layout

| Path | Contents |
|---|---|
| `Poro/App/` | `PoroApp.swift`, `AppDelegate.swift`, `PoroController.swift`, `AssistantWindowController.swift`, `StatusItemController.swift` |
| `Poro/Chat/LLM/` | `OpenRouterLLMClient.swift`, `OpenAISSEStreamParser.swift`, `LLMConfiguration.swift`, `LLMClient` protocol |
| `Poro/Chat/Models/` | `ChatMessage.swift` (carries optional `images`), `ChatImage.swift`, `ImageAttachment.swift` (NSImage → downscaled JPEG) |
| `Poro/Chat/State/` | `ChatController.swift`, chat session/history types |
| `Poro/Chat/Tools/` | `FocusReadToolbox.swift`, `AssistantToolbox` protocol |
| `Poro/Focus/State/` | `FocusSessionController.swift`, focus session lifecycle |
| `Poro/Focus/` | `FrontmostActivityMonitor.swift`, `BrowserTabContextProvider.swift`, `DistractionPolicy.swift`, `DriftWatchdog.swift`, `CerebrasFocusDecisionClient.swift` |
| `Poro/Views/` | `ContentView.swift` (shared root), `PoroTheme.swift` (dimensions/colors) |
| `Poro/Assets.xcassets/` | App icons, asset catalogs |
| `Poro.xcodeproj/` | Xcode project + SPM resolution |
| `hooks/` | Verification scripts run by the Claude Code `Stop` hook |
| `.claude/` | Project-level Claude Code config (`settings.json` checked in, `settings.local.json` gitignored) |
| `design_handoff_poro/` | Design assets — not built into the app |
| `RepoContext.md` | Long-form reference: full prompt inventory, focus state machine, dimensions |

### Core ownership

| Type | Responsibility |
|---|---|
| `AssistantWindowController` | Owns normal/focus `NSPanel`s, frame math, animation, focus tab dragging |
| `PoroController` | App state, routing, normal/focus `ChatController`s, composer drafts, intent routing |
| `ChatController` | Chat history, streaming state, LLM calls, assistant-only injected prompts |
| `OpenRouterLLMClient` | Streaming (OpenAI-compatible) chat client, multimodal message encoding (`image_url` parts), base system prompt composition |
| `FocusSessionController` | Focus session lifecycle, timer, activity logging, distraction detection |
| `FrontmostActivityMonitor` | Polls frontmost app, enriches browsers with active tab metadata |
| `BrowserTabContextProvider` | AppleScript URL/title lookup, conservative tab close |
| `DistractionPolicy` | Static distraction rules, "should ask LLM classifier" gate |
| `ContentView` | Shared SwiftUI root for both panel contexts |

### Callback ownership (single-owner slots — don't add a second owner without refactoring to multicast)

| Callback | Owner |
|---|---|
| `focusSessionController.onSessionStateChange` | `AssistantWindowController` |
| `focusSessionController.onStatusItemUpdate` | `StatusItemController` |
| `focusSessionController.onDistractionDetected` | `AssistantWindowController` |
| `focusSessionController.onDistractionResolved` | `AssistantWindowController` |
| `focusSessionController.onSummaryAvailable` | `PoroController` |
| `poroController.onDismissRequested` | `AssistantWindowController` |
| `poroController.onPresentRequested` | `AssistantWindowController` |
| `poroController.onReactivateRequested` | `AssistantWindowController` |

---

## 3. Running checks (mandatory at end of every turn)

The Claude Code `Stop` hook is configured to run `./hooks/run-checks.sh` automatically after every assistant response. The orchestrator runs four steps in order:

| Step | Script | Behavior | Hard/soft |
|---|---|---|---|
| 1. Typecheck | `hooks/typecheck.sh` | `swiftc -typecheck` over `Poro/`, excluding `AppDelegate.swift`, `KeyboardShortcuts.swift`, `PoroApp.swift` | **Hard** — fails the turn |
| 2. Lint | `hooks/lint.sh` | `swiftformat --lint Poro/` | **Hard** — auto-fix with `swiftformat Poro/` |
| 3. Build | `hooks/build.sh` | `xcodebuild -scheme Poro -configuration Debug -destination 'platform=macOS' build` | **Soft** — known CLI failure on `KeyboardShortcuts_KeyboardShortcuts.bundle`, warning only |
| 4. Auto-commit | `hooks/auto-commit.sh` | `git add -A && git commit` with auto-generated message. **Never pushes.** | Only runs if steps 1–2 passed |

### Agent rules

- **Read the hook output before declaring the turn complete.** If typecheck or lint fails, fix it in the same turn.
- **Manual invocation:** `./hooks/run-checks.sh` from repo root.
- **Auto-fix lint:** `swiftformat Poro/` (without `--lint`).
- **Push is never automated.** The user runs `git push` manually when ready.
- **Auto-commit only fires on green.** Failed turns leave the working tree dirty.
- **Before pushing, run `/squash`.** It groups the local auto-commits since `origin/main` into a few topic commits so the public history stays readable. Creates a `squash-backup-*` branch so it's reversible. Never pushes.

### Project conventions

- Use `rg` first for search — `find`/`grep` are slower.
- Keep normal and focus chat histories separate. Distraction messages belong only in the focus chat.
- Preserve URL-match safety for browser tab closing — never close a tab unless the current active URL still exactly matches the flagged URL.
- Never add synthetic "I drifted..." user bubbles. Distraction nudges are assistant-only messages.
- If a focus close/explain flow succeeds, tuck the panel back to the icon. If it fails, keep it expanded.
- Don't overwrite unrelated dirty changes — this repo often has active in-progress edits.
- `SourceKit "Cannot find type"` errors in editor diagnostics are usually false positives without a full Xcode build index. Verify against typecheck output.
- **Avoid ternary operators (`?:`) in non-trivial spots.** Prefer Swift 5.9 `if`/`switch` expressions for assignments and `??` for nil-coalescing. Single-token SwiftUI modifiers (`.scaleEffect(isPressed ? 0.96 : 1)`) are fine — the goal is readability, not absolute elimination. Lint already enforces `if`-expression over ternary for assignments via swiftformat's `conditionalAssignment` rule.
- **Never add `Co-Authored-By: Claude` (or any Claude attribution) to commit messages.** Commits in this repo are solo-authored. Applies to both new commits and `git commit --amend` rewrites.

For full focus session lifecycle, prompt inventory, and `PoroTheme` dimension constants → see `RepoContext.md`.
