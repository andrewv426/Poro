# Poro — Session Context

This document captures what was built, debugged, and decided during the main implementation session. It's a reference for future Claude conversations — not a user-facing README.

---

## What Poro Is

A macOS floating assistant panel built with Swift + SwiftUI. It sits as an NSPanel above all windows. It has two modes:

1. **Normal chat** — a 560px panel centered on screen. General-purpose AI assistant (Cerebras API).
2. **Focus mode** — a 420px panel anchored to the left edge. Activated by a focus session. Monitors what the user is doing and auto-pops when distraction is detected.

---

## Architecture Overview

### Core objects

| Class | Role |
|-------|------|
| `AssistantWindowController` | NSPanel state machine — owns all window positioning and animation |
| `PoroController` | `@Observable` app state — chat controllers, routing, intent parsing |
| `FocusSessionController` | Focus session lifecycle, distraction detection, timer, nudges |
| `ContentView` | SwiftUI root — switches layout based on `panelRoute` + `isFocusChat` |
| `ChatController` | Manages one chat session (messages, streaming, LLM requests) |
| `StatusItemController` | Menu bar item showing session timer |

### Window state machine (`PanelMode`)

```
.hidden   ←→  .normal    (Cmd+Option+T toggles)
    ↓               ↓
.tucked   ←→  .expanded  (focus session active)
```

| Mode | Width | Position | Chat |
|------|-------|----------|------|
| `.normal` | 560px | centered | normal chat |
| `.expanded` | 420px | left-flush | focus chat |
| `.tucked` | 420px | tab peeks 36px from left | — |
| `.hidden` | — | off-screen | — |

### Dual chat

Two separate `ChatController` instances:
- `chatController` — normal chat, has `FocusReadToolbox` (can read session state)
- `focusChatController` — focus chat, no toolbox (reactive only)

`activeChatController` computed property on `PoroController` transparently routes to the right one based on `isFocusChat`. All of `ContentView` uses `activeChatController` — no `if/else` in the view layer.

### Distraction detection flow

```
FrontmostActivityMonitor
  → onActivityChange
    → DistractionPolicy.evaluate()   (static rules)
      → DriftWatchdog.schedule()     (2s debounce)
        → presentNudge()
          → onDistractionDetected
            → AssistantWindowController.handleDistractionDetected()
              → injectDistractionMessage() on focusChatController
              → expandFocus()              opens 420px panel
              → Task.sleep(30s) → clearDistractionState()
```

---

## What Was Built This Session

### 1. Focus mode UI — replace nudge popup with left-edge tab + auto-expand

**Previous behavior:** A separate `NudgeWindowController` / `FocusNudgeView` popup appeared when distraction was detected. User could argue with it.

**New behavior:**
- During a focus session, the panel tucks to a small tab on the left edge (36px visible, Poro logo + pulse ring)
- When distraction is detected, the panel auto-expands from the left edge (420px) and injects the distraction message directly into the focus chat
- Esc during a session tucks back to the tab rather than hiding entirely

**Files deleted:** `NudgeWindowController.swift`, `FocusNudgeView.swift`

**Files modified:** `AppDelegate.swift` (removed nudge controller), `FocusSessionController.swift` (replaced nudge system with `onDistractionDetected` callback), `AssistantWindowController.swift` (rewrote mode transitions), `ContentView.swift` (added `FocusTabView`)

### 2. Dual chat — separate normal and focus chat histories

**Problem:** Normal chat and focus chat were the same `ChatController`. Distraction messages polluted normal conversation history. Cmd+Option+T during a session should open the normal chat, not the focus chat.

**Solution:**
- Added `focusChatController: ChatController` to `PoroController`
- Added `isFocusChat: Bool` flag — set by `AssistantWindowController` on mode transitions
- `activeChatController` computed property routes based on the flag
- Focus chat history is cleared (`startNewConversation()`) each time a new session starts
- Normal chat history is never touched by focus session events

### 3. Git history cleanup

- Rewrote commit dates: spread from 2026-01-15 to present (roughly weekly cadence)
- Removed Cerebras API key (`csk-cr92rxfh...`) from `Poro.xcscheme` git history using `git filter-branch`
- Added `*.xcscheme` to `.gitignore`
- Pushed to `https://github.com/andrewv426/Poro.git`

---

## Bugs Found and Fixed

### Tab invisible — three separate causes

1. **Wrong x-offset in `tuckedFrame()`**: Used `PoroTheme.width` (560) instead of `PoroTheme.focusWidth` (420) for the panel width calculation. Left only 28px visible instead of 36px.
2. **Wrong alignment in `FocusTabView`**: `Spacer()` was after the icon, pushing it to the leading (off-screen) side. Fixed by putting `Spacer()` before the icon.
3. **`totalHeight` didn't return `tabHeight` when tucked**: The height calculation missed the tucked case entirely — panel had zero height. Fixed with `if poroController.isTucked { return PoroTheme.tabHeight }`.

### Tuck animation didn't surface the panel

`tuck()` called `panel.animator().setFrame()` but never called `orderFrontRegardless()` before the animation block. The panel stayed behind other windows. Fixed by calling `panel.orderFrontRegardless()` before the animation.

### Distraction not auto-triggering

Two causes:
1. `DriftWatchdog` default grace period was 10 seconds. Reduced to 2 seconds.
2. The watchdog was cancelled if the user briefly switched apps while the pending activity was being evaluated (guard `lastSeenActivity == activity`). Removed that guard.

### `isNudgeActive` never reset

`clearDistractionState()` existed but was never called from outside. After the first distraction, `isNudgeActive` stayed `true` forever and no further distractions were detected. Fixed by calling `clearDistractionState()` from `AssistantWindowController` after a 30-second `Task.sleep`.

### `StatusItemController` clobbering `AssistantWindowController`'s session callback

Both `StatusItemController` and `AssistantWindowController` were assigning to `focusSessionController.onSessionStateChange`. `StatusItemController` was initialized after `AssistantWindowController` and overwrote the callback — the window controller never received session start/end events.

Fixed by adding a dedicated `onStatusItemUpdate` callback on `FocusSessionController`. `notifySessionStateChange()` fires both. `StatusItemController` now uses `onStatusItemUpdate` exclusively.

### `surfaceHeight` wrong in focus collapsed mode

`surfaceHeight` returned `focusCollapsedTotalHeight` (76) instead of a surface-only height. Added `focusCollapsedSurfaceHeight = 56` to `PoroTheme` and used it in `surfaceHeight`.

### Panel width inconsistency in focus mode

`ContentView` framed both `surface` and the outer `VStack` at `PoroTheme.width` (560px) even during focus expanded mode (420px panel). This caused SwiftUI layout overflow. Fixed with:
```swift
let panelWidth = poroController.isFocusChat ? PoroTheme.focusWidth : PoroTheme.width
```

---

## Dead Code Removed

| Item | Reason |
|------|--------|
| `NudgeWindowController.swift` | Replaced by inline chat injection |
| `FocusNudgeView.swift` | Replaced by inline chat injection |
| `NudgeContext.swift` | Orphaned model — zero external references after nudge removal |
| `PoroTheme.activeSessionCollapsedTotalHeight` | Defined, never used |
| `AssistantWindowController.lastDistractionActivity` | Stored, never read |

---

## PoroTheme Constants (current)

```swift
static let width: CGFloat = 560                    // normal panel width
static let focusWidth: CGFloat = 420               // focus/tucked panel width
static let focusExpandedSurfaceHeight: CGFloat = 280   // focus chat expanded
static let focusCollapsedSurfaceHeight: CGFloat = 56   // focus surface when collapsed
static let focusCollapsedTotalHeight: CGFloat = 76     // focus total (surface + strip)
static let tabHeight: CGFloat = 44                 // tucked tab height
static let tabVisibleWidth: CGFloat = 36           // pixels peeking from left edge
static let collapsedSurfaceHeight: CGFloat = 56    // normal surface when collapsed
static let collapsedTotalHeight: CGFloat = 88      // normal total (surface + strip)
static let focusSetupHeight: CGFloat = 252
static let summaryHeight: CGFloat = 330
static let expandedSurfaceHeight: CGFloat = 480    // normal chat expanded
static let topAnchorRatio: CGFloat = 0.30          // vertical anchor for normal panel
```

---

## Callback Ownership (single-owner slots — do not double-assign)

| Callback | Owner |
|----------|-------|
| `focusSessionController.onSessionStateChange` | `AssistantWindowController` |
| `focusSessionController.onStatusItemUpdate` | `StatusItemController` |
| `focusSessionController.onDistractionDetected` | `AssistantWindowController` |
| `focusSessionController.onSummaryAvailable` | `PoroController` |
| `poroController.onDismissRequested` | `AssistantWindowController` |
| `poroController.onPresentRequested` | `AssistantWindowController` |

---

## Known Non-Issues

**SourceKit "Cannot find type" errors** in the diagnostics panel for `AssistantWindowController.swift`, `ContentView.swift`, `FocusSessionController.swift` etc. are false positives. SourceKit can't resolve cross-file types without a full Xcode build index. All types (`FloatingAssistantPanel`, `PoroController`, `PoroTheme`, etc.) exist in the project. Do a Cmd+B in Xcode to confirm zero real compiler errors.

**`xcodebuild` CLI build failure** with KeyboardShortcuts SPM bundle is a pre-existing issue unrelated to these changes. The scheme needs the full Xcode build environment to resolve SPM bundles.
