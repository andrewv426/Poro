# Figma Revisions — Session Summary + Focus Setup + Components Cleanup

**Figma file:** https://www.figma.com/design/XutQPC4AyxV1sMGjvaKu4v

**Branch:** `figma/session-summary-music-revision`

## Context

After porting Poro's UI into Figma, three issues surfaced from review against the running app:

1. **Components page unreadable.** Variants from `combineAsVariants` were stacked at the same coordinates, producing overlapping previews.
2. **Session Summary doesn't reflect real session state.** The Figma mock hard-coded populated data, but a session with zero distractions renders "None" and conditionally hides the Memorable Arguments section.
3. **Focus Setup needs optional Music field.** Goal stays required; an optional music-preference input lets `/play` be primed at session start.

## Changes

### 1. Components page

- Tiled every component set's variants horizontally (with wrap at ~1100px), with consistent 24px gaps and 24px internal padding. Resized each set to wrap its children.
- Added dark backplate (`#16161C`) behind the component sets so dark-mode components read legibly on Figma's light canvas.
- All affected sets: Message Bubble, Composer, Slash Menu Row, Decision Button, Duration Chip, Focus Icon Tab, Toolbar Icon Button.

### 2. Session Summary — two variants

- Renamed existing summary to **`11a — Session Summary (Populated)`** — Goal, Time on task (mint), Nudges (2), Allowed/Denied overrides, Top distractions, Memorable arguments section.
- Added **`11b — Session Summary (Sparse)`** beside it:
  - Goal + Time on task same as populated
  - Nudges / Allowed / Denied: `0`
  - Top distractions: `None`
  - Memorable Arguments section omitted entirely (matches SwiftUI `if !memorableArguments.isEmpty` gate)
- Sparse height ~230px vs populated ~330px.

### 3. Focus Setup — two variants with Music field

- Removed existing setup; added `9a — Focus Setup (Default)` and `9b — Focus Setup (Music Filled)`.
- New layout: Header → Goal (required, "What are you working on?") → **Music (optional)** → Duration chips → Confirm.
- Music field placeholder: `instrumental, lo-fi, ambient…` (muted) in default; `lo-fi` typed in filled variant with mint-bordered focused field.
- "(optional)" rendered as muted text adjacent to "Music" label.
- Confirm stays full-width mint; assumes Goal is non-empty.

## Files changed in this branch

- `design_handoff_poro/figma_revisions.md` — this file
- *(No Swift code changes — design only. Wiring `musicPreference` into `FocusSetupView` + `FocusSessionController.startSession` is deferred to a follow-up PR.)*

## Follow-up Swift work (out of scope here)

When the design is approved:

1. Add `@State var musicPreference: String = ""` to `FocusSetupView`.
2. Render music input row mirroring the goal field; placeholder `instrumental, lo-fi, ambient…`.
3. Disable Confirm only when goal is empty (music can be empty).
4. Pass `musicPreference` through to `FocusSessionController.startSession(goal:durationMinutes:music:)`.
5. On session start, if music is non-empty, route through `SlashCommandParser.playCommand(query: music)` so the Spotify integration begins playing immediately.

## Verification

- Open the Figma file: https://www.figma.com/design/XutQPC4AyxV1sMGjvaKu4v
- **Components page:** all variants visible side-by-side, no overlap, readable on dark backplate.
- **Screens page → Session Summary group:** both 11a and 11b visible; 11b has zeros + "None" + no memorable arguments section.
- **Screens page → Focus Setup group:** both 9a and 9b visible; 9b shows mint-bordered focused music field with "lo-fi".
