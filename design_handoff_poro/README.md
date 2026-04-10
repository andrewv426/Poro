# Handoff: Poro — Floating AI Assistant

## Overview
Poro is a summonable, floating AI-assistant surface for macOS (think command-palette genre). A global hotkey reveals a compact input bar that lives over the user's current app; on first message it springs open into a vertical conversation panel that streams the assistant's reply. Dismiss returns it out of the way until next summon.

The mascot/icon is "Poro" — a white fluffy creature from League of Legends (used with an uploaded reference PNG).

## About the Design Files
The files in this bundle are **design references created in HTML** — a working prototype that demonstrates intended look, motion, and behavior. They are **not production code to copy directly**.

Your task is to **recreate this design in the target codebase's native environment** (SwiftUI for a real macOS menu-bar app would be the most honest choice; a Tauri/Electron + React implementation is also reasonable). Lift the values (colors, sizes, motion curves) exactly — do not port the HTML wholesale.

## Fidelity
**High fidelity.** Final colors, typography, spacing, motion curves, and streaming cadence are all specified and locked. The dev should match these exactly; any deviation should be intentional and justified by platform conventions (e.g., using system Stop-icon SF Symbol instead of the inline SVG).

## Screens / Views

### 1. Summoned (collapsed) — single-row input
- **Purpose:** Instant ask; minimal footprint over whatever app the user is in.
- **Layout:** Single 560 × 56 px rounded rectangle, centered horizontally, vertical anchor at ~30% viewport height.
- **Components (left → right inside input row, 16px horizontal padding, 12px gap):**
  - **Poro icon** — 22×22 px, the uploaded `poro.png`, 95% opacity. Lifts 1px and scales to 1.04 on input focus (200ms spring).
  - **Text field** — flex 1, transparent, no border, SF Pro 15px/1, color `rgba(255,255,255,0.92)`, caret color `var(--accent)`, placeholder `rgba(255,255,255,0.40)` "Ask anything…".
  - **Return indicator** — shows when text is present and not streaming. 14×14 return-arrow glyph in `var(--accent)`.
- **Hint (below window, disappears on expand):** "Press ⌘⌥T to summon, Esc to dismiss" at `rgba(255,255,255,0.32)`, 12px, with kbd chips at `rgba(255,255,255,0.06)` bg.

### 2. Expanded — conversation + streaming
- **Purpose:** Read + continue a conversation with the assistant.
- **Layout:** Same 560 px width, height animates 56 → 480 px with a spring (see Motion).
- **Regions, top → bottom:**
  1. **Top toolbar** (32 px tall, 16 px padding, fades in 120 ms after expand start):
     - Left: 18 px Poro icon at 0.85 opacity.
     - Right icon cluster (4 px gap): *New conversation* (pencil-square), *History* (clock), *Settings* (gear). Each 22×22 px transparent button, icon 14×14 px in `rgba(255,255,255,0.40)`. Hover fills `rgba(255,255,255,0.06)`, icon → `rgba(255,255,255,0.85)`.
  2. **Messages list** — flex, scrollable, padding `8px 20px 16px 20px`. Custom 6 px scrollbar at `rgba(255,255,255,0.08)`. Auto-scrolls to bottom on new tokens.
     - Each message:
       - **Label line** (10 px, 600, letter-spacing 0.08em, uppercase). `YOU` in `rgba(255,255,255,0.40)`; `PORO` in `var(--accent)`. 6 px below → body.
       - **Body** — SF Pro 14.5px/1.55, color `rgba(255,255,255,0.85)` for assistant, `0.92` for user. Inline ``code`` renders as `<code>`: JetBrains Mono 13 px, bg `rgba(255,255,255,0.06)`, 1px×5px padding, 4 px radius.
       - 24 px margin below block.
     - **Streaming cursor** on the last assistant message while streaming: 2 px × 1em rect, `var(--accent)`, blinks `833ms steps(2) infinite`.
  3. **Divider** — 1 px, `rgba(255,255,255,0.06)`, fades in with toolbar.
  4. **Input row** — identical to collapsed state. Changes while streaming:
     - Return indicator hidden.
     - **Stop button** appears (flush right in input row): 24×24 px transparent button containing a 20×20 px SVG — outer circle stroke 1.5 px in `rgba(251,113,133,0.85)`, inner 7×7 px rounded square (rx 1.25) filled same color. Hover: color `rgba(251,113,133,1)`, bg `rgba(251,113,133,0.10)`, `scale(1.05)`. Active: `scale(0.95)`.

### 3. Dismissed
- **Purpose:** Out of the way until summoned.
- **Behavior:** Window opacity → 0, translate Y −8 px, pointer-events none, 160 ms ease-out.

## Interactions & Behavior

### Hotkeys
- **⌘ + ⌥ + T** — Summon. Un-dismisses and focuses the input. Keep this non-conflicting development shortcut for the current implementation; do not switch to `⌘ + Space`.
- **Esc** — If streaming: stop the stream. Otherwise: dismiss the window.
- **Enter** (no Shift) — Submit current query.

### Submit flow
1. Trim query; no-op if empty or currently streaming.
2. Append `{role: 'user', content: q}` + placeholder `{role: 'assistant', content: ''}` to messages.
3. Clear input.
4. Begin streaming simulation: per-tick advance by `2 + rand(0..3)` chars; tick interval `16 + rand(0..17) ms`. Real implementation: pipe from actual LLM SSE/stream, keep the same visual cadence feel.
5. On stop (user or natural end): settle final text, remove streaming cursor.

### Motion
- **Expand/collapse height**: `height 280ms cubic-bezier(0.34, 1.56, 0.64, 1)` — gentle overshoot, the macOS-ish spring.
- **Top row + messages fade-in**: `opacity 220ms ease-out` delayed 140 ms after expand start. Divider 200 ms ease-out.
- **Dismiss**: `opacity 160ms ease-out, transform 160ms ease-out` combined with `translate(-50%, calc(-50% - 8px))`.
- **Icon focus lift**: `transform 200ms cubic-bezier(0.34, 1.56, 0.64, 1)` → `translateY(-1px) scale(1.04)`.

### States to build
- `query` (string)
- `messages` (array of `{role: 'user'|'assistant', content: string}`)
- `streamingText` (string | null — null when not streaming)
- `dismissed` (bool)
- `expanded` derived as `messages.length > 0`

## Design Tokens

### Colors
| Token | Value | Use |
|---|---|---|
| `--accent` | `#E8D4A8` | PORO label, caret, return arrow, streaming cursor. Default of 3 beige options. |
| `--accent` alt 1 | `#F2E3C0` | "cream" variant |
| `--accent` alt 2 | `#C9A876` | "caramel" variant |
| Rose (stop) | `rgba(251, 113, 133, 0.85)` base / `1.0` hover | Stop icon |
| `--fg` | `rgba(255,255,255,0.92)` | User body text |
| `--fg-dim` | `rgba(255,255,255,0.85)` | Assistant body text |
| `--fg-muted` | `rgba(255,255,255,0.40)` | Labels, icons, placeholder |
| `--fg-faint` | `rgba(255,255,255,0.22)` | — |
| `--fg-trace` | `rgba(255,255,255,0.08)` | Scrollbar thumb |
| Window tint | `rgba(22, 22, 28, 0.62)` | Behind vibrancy |
| Window inner border | `rgba(255,255,255,0.08)` | Inset 1 px stroke |
| Divider | `rgba(255,255,255,0.06)` | Input separator |
| Hover bg | `rgba(255,255,255,0.06)` | Icon button hover |

### Vibrancy
- `backdrop-filter: blur(40px) saturate(180%)` on the window. Native macOS: use `.ultraThinMaterial` in SwiftUI (`VisualEffectView` with `.hudWindow` material on AppKit).

### Shadow
```
0 10px 30px rgba(0,0,0,0.45),
0 2px 6px  rgba(0,0,0,0.30),
0 0 0 0.5px rgba(0,0,0,0.50)
```

### Radius
- Window: **14 px**
- Stop-icon inner square rx: **1.25 px**
- Input pill variant: 999 px; bordered variant: 9 px. *(Current default is "flat" — no inner wrapper.)*

### Typography
- UI / body: `-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'SF Pro Display', 'Inter', system-ui, sans-serif`
- Mono (labels + inline code): `'JetBrains Mono', 'SF Mono', ui-monospace, monospace`
- Scale:
  - Input field: 15 px / 1
  - Message body: 14.5 px / 1.55
  - Message label: 10 px / 1, weight 600, letter-spacing 0.08em, uppercase
  - Inline code: 13 px
  - Hint text: 12 px / weight 500

### Spacing
- Input row padding: `0 16px`; gap 12 px; height 56 px.
- Top row padding: `0 16px`; height 32 px.
- Messages padding: `8px 20px 16px 20px`.
- Message block margin-bottom: 24 px.

## Assets
- `assets/poro.png` — Poro mascot PNG, provided by the user (League of Legends character). Used at 22×22 in the input bar and 18×18 in the expanded toolbar. Rendered with `object-fit: contain`.
- Icons (pencil-square, clock, gear, return arrow, stop circle+square) — inline SVG in `poro-app.jsx`, Lucide-style 16×16 viewbox with `strokeWidth=1.5`. Replace with SF Symbols on native macOS.

## Files
- `Poro.html` — entry point, all CSS, mounts the React app.
- `poro-app.jsx` — React component tree, streaming simulator, hotkey handling, tweaks panel.
- `assets/poro.png` — mascot.

## Platform recommendations
- **SwiftUI (preferred for real macOS app):** Borderless `NSPanel` with `.nonactivatingPanel` + `.hudWindow` style mask, `canBecomeKey = true`. Register the current `⌘⌥T` hotkey with `KeyboardShortcuts` (or Carbon `RegisterEventHotKey` if you later need lower-level control). Use `NSVisualEffectView` with `.hudWindow` material. Animate height with `.animation(.spring(response: 0.28, dampingFraction: 0.6))`.
- **Electron/Tauri + React:** Frameless always-on-top window, `vibrancy: 'under-window'` (macOS), `transparent: true`. Register accelerator via `globalShortcut`. Framer Motion spring `{ type: 'spring', stiffness: 380, damping: 22 }` approximates the CSS curve.
