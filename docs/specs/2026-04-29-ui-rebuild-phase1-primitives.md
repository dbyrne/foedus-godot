# UI Rebuild — Phase 1: Visual Primitives & Theme

**Status:** Spec, ready for implementation plan.
**Date:** 2026-04-29.
**Direction:** "War Council" (D3) from Claude Design — tabletop diorama
aesthetic with dark felt, brass, bone, candlelight.
**Source design files:** see `docs/specs/foedus-design-bundle/`
(extracted from the Claude Design handoff).

## 1. Motivation

The current Bundle 4 UI is functional but reads as a wall of toggles and
buttons. Per the seat-permutation playtest of 2026-04-29, surfacing
information density and the press/aid/leverage signals legibly is the
top blocker to running human playtests. Rebuilding the visual language
top-to-bottom is the right next move.

This spec covers **Phase 1 only**: the primitive components and theme
tokens that every other screen will compose. Subsequent phases (core
game screens, pre-game flow, mid-flow + meta) sit on top of these
primitives.

## 2. Goals and non-goals

### Goals

- Lock the visual identity: color palette, font stack, ornamentation
  rules.
- Build a kit of reusable Godot Control / Node2D scenes that match the
  design's sculpted appearance.
- Replace the existing `themes/main_theme.tres` with a War Council
  theme.
- Provide a single demo scene that displays every primitive at every
  relevant variant, for visual review and regression testing.

### Non-goals

- No game screens in Phase 1. The current `scenes/Main.tscn` keeps
  working with its existing layout; Phase 2 will replace it.
- No new HTTP endpoints, no engine changes, no wire-protocol changes.
  This is purely client-side.
- No animations beyond what's strictly necessary to render a primitive
  (e.g., the TensionMeter heartbeat). Resolution playback and reveal
  curtain pull are deferred to Phase 4.

## 3. Visual identity (locked)

### Color tokens

| Token | Hex | Use |
|---|---|---|
| `felt` | `#1a2024` | Main table background |
| `feltLight` | `#26303a` | Panel hover, throne highlight |
| `feltDark` | `#0e1418` | Vignette, shadow gradients |
| `brass` | `#c9a064` | Gilded frame, primary chrome |
| `brassDim` | `#8a6f3e` | Borders, disabled brass |
| `bone` | `#e8dcc4` | Parchment, primary text |
| `boneDim` | `#b9a98a` | Secondary text |
| `ink` | `#0a0e12` | Darkest, text on brass |
| `candle` | `#f4d27a` | Highlights, victory glow |
| `blood` | `#a8323a` | Player Aelia, hostile, danger |
| `ember` | `#e07a3c` | Tension, warning |
| `azure` | `#2f5d7c` | Player Borovic |
| `ochre` | `#9c7a1f` | Player Cyrene |
| `sable` | `#3d6b3a` | Player Drevan |

### Typography

| Role | Family | Weights |
|---|---|---|
| `display` | Playfair Display | 700, 900 |
| `serif` | Cormorant Garamond | 400, 500, 700i |
| `sans` | IBM Plex Sans | 700 (small caps with 0.3em tracking) |
| `mono` | JetBrains Mono | 400, 500 |

Sans is small caps, wide tracking — used only for labels and system
chrome. Display and serif do all narrative work. Mono is for data,
hex coordinates, debug.

### Aesthetic rules

- Frames: gilded brass inner border + thin parchment-tone inner rule.
- Corners: small ornamental glyphs, brass dot terminations.
- Surfaces: dark felt with subtle SVG-noise overlay (reproduce as a
  CanvasLayer with a NoiseTexture2D).
- Selection: candle-yellow dashed halo.
- Player accents: heraldic but desaturated; the four player colors
  above are all rendered with a paired darker shade for shading.

## 4. Component inventory

Each component is its own `.tscn` under `res://components/` with a
matching `.gd` script. Public properties listed in design's
`d3-godot-spec.jsx`; props reproduced here for clarity.

| Component | Type | Props | Purpose |
|---|---|---|---|
| `Crest` | Control | `player_id: String`, `size: int`, `broken: bool`, `dim: bool` | Sculpted heraldic shield + sigil per player. |
| `UnitPiece` | Node2D | `player_id: String`, `label: String`, `size: int`, `selected: bool`, `ghost: bool` | Top-down disk with ring + glint, used inside CouncilHex. |
| `CouncilHex` | Node2D | `tile: Tile`, `selected: bool`, `highlight: Color` | Hex tile with terrain decals, supply markers, home banner, optional unit. |
| `BrassPlate` | Control | `text: String` | Engraved label chrome (small caps). |
| `TensionMeter` | Control | `phase: String`, `timer: String`, `value: float` | Heartbeat strip showing phase + remaining time + progress fill. |
| `WaxEnvelope` | Control | `sealed: bool`, `color: Color`, `label: String`, `size: int` | Order/aid icon. |
| `ScalesOfLeverage` | Node2D | `tilt: float`, `left_load: int`, `right_load: int` | Animated balance for pairwise leverage view. |
| `Throne` | Control | `occupied: bool`, `player_id: String` | Matchmaking seat (used in Phase 3 pre-game; building primitive now is cheap). |
| `CouncilShell` | Control (full-screen wrapper) | — | Felt backdrop + gilded frame + corner ornaments. Every screen mounts inside one. |

## 5. Theme

Replace `themes/main_theme.tres` with a War Council theme that exposes
the color tokens as Theme constants and the four font stacks as Theme
default fonts. Existing controls (`Button`, `Label`, `TextEdit`, etc.)
get sensible defaults so any screen built on this theme renders with
the right typography and palette without per-control overrides.

## 6. Demo scene

`scenes/Phase1Demo.tscn` (and `scripts/Phase1Demo.gd`):

A single scene mounting every component at every relevant variant.
Layout is a simple grid of labeled cells. Acts as:

- Visual review surface for design feedback.
- Manual regression test (open the scene, scan for breakage).
- Reference scene that future screens can look at to remember how to
  use a primitive.

The demo scene is **not** a runtime game scene — it's not connected to
the play-server. `scenes/Main.tscn` stays untouched in Phase 1.

## 7. Headless tests

Add `scripts/test_phase1_primitives.gd`:

- Loads every primitive `.tscn` and asserts each instantiates without
  errors.
- Asserts the demo scene loads and contains the expected primitive
  count.
- Runs in CI via `godot --headless --script res://scripts/test_phase1_primitives.gd`,
  same pattern as the existing `test_smoke.gd` and `test_e2e.gd`.

## 8. File layout

```
themes/
  war_council_theme.tres        ← new (replaces main_theme.tres in
                                    project.godot's UI/theme setting)
components/
  CouncilShell.tscn / .gd
  Crest.tscn / .gd
  UnitPiece.tscn / .gd
  CouncilHex.tscn / .gd
  BrassPlate.tscn / .gd
  TensionMeter.tscn / .gd
  WaxEnvelope.tscn / .gd
  ScalesOfLeverage.tscn / .gd
  Throne.tscn / .gd
fonts/
  PlayfairDisplay-Regular.ttf
  PlayfairDisplay-Bold.ttf
  PlayfairDisplay-Black.ttf
  CormorantGaramond-Regular.ttf
  CormorantGaramond-Italic.ttf
  CormorantGaramond-SemiBold.ttf
  CormorantGaramond-Bold.ttf
  IBMPlexSans-Bold.ttf
  JetBrainsMono-Regular.ttf
  JetBrainsMono-Medium.ttf
scenes/
  Phase1Demo.tscn               ← new
scripts/
  Phase1Demo.gd                 ← new
  test_phase1_primitives.gd     ← new
```

`scenes/Main.tscn` and `scripts/Main.gd` are untouched in Phase 1.

## 9. Compatibility / deferrals

- Existing `Main.tscn` and its order entry remain functional. The new
  theme is loaded as a separate resource and only applied to
  `Phase1Demo.tscn`. Phase 2 will swap `Main.tscn` to use the new
  theme.
- Fonts are checked into the repo (font files ~1–2 MB total). Acceptable
  cost given the offline/single-binary distribution intent.
- The design's `Throne` component is used in Phase 3's matchmaking
  screen, but matchmaking is a deferred backend feature. Building the
  primitive now is cheap and avoids returning to fonts/theme later.
- The Sociogram (used in Pairwise dossier and the Court panel in
  Negotiation) is **not** a primitive — it composes Crests, lines, and
  arcs. Deferred to Phase 2.

## 10. Acceptance criteria

- All nine component scenes load without warnings.
- `scenes/Phase1Demo.tscn` renders all components at all documented
  variants without overlap or clipping at 1280×800 and 1920×1080.
- `godot --headless --script res://scripts/test_phase1_primitives.gd`
  exits 0 with all assertions passing.
- The existing `scripts/test_smoke.gd` and `scripts/test_e2e.gd` still
  pass.
- The four player crests are visually distinct and recognizable at
  size=26 (the size used in the negotiation top bar).
- `TensionMeter` renders correctly in both `phase=negotiation` (candle
  fill) and `phase=orders` (ember/blood fill).

## 11. Open questions

1. **Font licensing.** Playfair Display, Cormorant Garamond, IBM Plex
   Sans, and JetBrains Mono are all SIL OFL or Apache 2.0 — fine to
   bundle. Confirm during implementation.
2. **Faction names.** Design uses "Aelia / Borovic / Cyrene / Drevan"
   (AEL/BOR/CYR/DRE). The engine uses int player_ids 0–3. Phase 1
   ships these as a hard-coded client-only `PLAYERS` resource; Phase 2
   may add a "faction draft" mechanic, at which point these become
   configurable.
3. **Sociogram primitive vs composition.** Currently spec'd as Phase 2
   composition. If Phase 2 prototyping reveals it has enough internal
   complexity to warrant its own component, promote it back to a
   primitive in a follow-up.
