# Poro

A floating, always-on-top AI assistant for macOS, with a built-in focus coach. It's written in Swift, SwiftUI, and AppKit, and streams responses from a multimodal model through OpenRouter.

Overview deck: https://docs.google.com/presentation/d/1Am5adKxpMCp9yE9u1n5Sr_6yfHISk_401i9V8wRkV94/edit?usp=sharing

---

## Features

### Normal chat
- **`Cmd+Option+T`** toggles a 560 px floating chat bar over whatever app you're in. You can rebind it in Settings.
- The first message opens the bar into a conversation panel that streams replies from OpenRouter (`nvidia/nemotron-nano-12b-v2-vl:free` by default).
- **Image attachments:** attach images with the paperclip button or drag and drop them, then ask about them. Images stay in the conversation history, so follow-up questions still have them in context.
- **`Cmd+Option+Arrow`** moves the panel. The step size (4–200 px) is set in Settings. Mouse dragging can also be turned on there.
- The assistant can see the state of your current focus session, so you can ask things like "how much time is left?" and get a real answer.

### Slash commands
Type `/` in the composer to open an autocomplete menu. Slash commands are handled directly, with no LLM round-trip.

| Command | What it does |
|---|---|
| `/play <song>` | Plays the top Spotify result. `<song> by <artist>` gives a tighter match. |
| `/play playlist <name>` | Plays one of your own Spotify playlists. |
| `/focus [duration] [on <goal>]` | Opens focus-session setup, e.g. `/focus 30 min on thesis draft` |
| `/stop` · `/skip` · `/shuffle [off]` | Spotify playback controls. These only appear while something is playing. |

Natural language works for focus too: "start a focus session for 45 min on the essay", "lock in", "keep me focused". During a session you can also type `pause`, `resume`, `end`, or `status`.

### Focus mode
- Starting a session collapses Poro into a small tab on the **left screen edge**. You can drag the tab up or down, and Poro remembers where you left it.
- A menu-bar item shows the time remaining.
- Poro watches the frontmost app, and in supported browsers it also reads the active tab's URL and title:
  1. **Static rules** flag apps that are always distracting (Discord, Slack, Spotify, Music, TV, Messages) and known distracting sites (YouTube, X/Twitter, Reddit, Instagram, Facebook, TikTok, Discord).
  2. **Other browser tabs** go to an LLM classifier that uses the same OpenRouter model. A tab counts as a distraction only if the verdict is `distract` with a score of at least **0.72**.
  3. A **2-second debounce** filters out quick accidental tab switches.
- When a distraction is confirmed, the focus panel expands and gives you **10 seconds** to choose:
  - **Close tab.** Poro closes the tab only if its URL still *exactly* matches the flagged URL.
  - **Explain why.** This stops the countdown. If the reason holds up, you get a **5-minute override**.
  - If you don't respond, Poro tries the same URL-matched close when the timer runs out.
- If the close or explanation succeeds, the panel tucks back to the edge tab. If it fails, the panel stays open so you can see what went wrong.
- When the session ends, Poro shows a summary.

Tab lookup and closing work in **Chrome, Safari, Arc, and Brave** through AppleScript. Each browser needs a one-time Automation permission prompt.

### Settings
Settings covers the accent color, nudge step, mouse drag, the toggle shortcut, and Quit.

---

## Getting started

### Requirements
- macOS with **Xcode 26.1+**
- An [OpenRouter](https://openrouter.ai/keys) API key (free keys are available)
- *(Optional)* A Spotify developer app for the Web API playback path

### Configure environment
Poro is sandboxed, so it can't read `~` at runtime. Keys are bundled from `Poro/Poro.env` (gitignored) at build time:

```bash
mkdir -p ~/.config/poro && touch ~/.config/poro/env
```

```bash
ln -s ~/.config/poro/env Poro/Poro.env
```

Example `~/.config/poro/env`:

```
OPENROUTER_API_KEY=sk-or-...
# OPENROUTER_MODEL=nvidia/nemotron-nano-12b-v2-vl:free
# OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
# SPOTIFY_CLIENT_ID=...
```

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `OPENROUTER_API_KEY` | yes | — | OpenRouter auth |
| `OPENROUTER_MODEL` | no | `nvidia/nemotron-nano-12b-v2-vl:free` | Vision-capable model id, used for both text and images |
| `OPENROUTER_BASE_URL` | no | `https://openrouter.ai/api/v1` | API base URL |
| `SPOTIFY_CLIENT_ID` | no | — | Turns on Spotify Web API (Connect) playback |

You can also set these as Xcode scheme environment variables. Non-empty scheme values take precedence over the bundled file.

### Spotify (optional)
Register an app at the [Spotify developer dashboard](https://developer.spotify.com/dashboard) with the redirect URI `poro://spotify-callback`, then set `SPOTIFY_CLIENT_ID`. Poro then controls playback through Spotify Connect without bringing the Spotify app to the front.

Without a client ID, or when no active Spotify device is found, Poro falls back to AppleScript. It launches Spotify if needed, and Spotify briefly takes focus before Poro takes it back.

### Build & run
Open `Poro.xcodeproj`, pick the `Poro` scheme, and run.

---

## Project layout

| Path | Contents |
|---|---|
| `Poro/App/` | App entry, `PoroController` (state and routing), `AssistantWindowController` (panels), status item |
| `Poro/App/Intent/` | Slash-command parser and registry, natural-language intent parser and router |
| `Poro/Chat/` | OpenRouter streaming client, env loading, chat and image models, chat state, and the assistant toolbox |
| `Poro/Focus/` | Session controller, activity monitor, browser tab provider, distraction policy, LLM classifier, focus UI |
| `Poro/Spotify/` | Web API, OAuth (PKCE), AppleScript fallback, playback poller |
| `Poro/Settings/` | Settings view, accent palette, shortcut recorder |
| `Poro/Views/` | Shared SwiftUI root, composer, slash menu, Spotify picker, `PoroTheme` |
| `hooks/` | Typecheck, lint, build, and auto-commit scripts |
| `design_handoff_poro/` | HTML design prototype and specs (not built into the app) |

`CLAUDE.md` and `RepoContext.md` have deeper architecture notes: the focus state machine, the prompt inventory, callback ownership, and dimension constants.

---

## Development

```bash
./hooks/run-checks.sh
```

This runs `swiftc -typecheck`, then `swiftformat --lint` (fix issues with `swiftformat Poro/`), then an `xcodebuild` Debug build. The CLI build has a known, non-blocking failure on the `KeyboardShortcuts` resource bundle. For Claude Code sessions, the same script runs as a `Stop` hook and auto-commits locally when the checks pass. It never pushes.

**Dependencies:** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 2.4.0 (SPM).
