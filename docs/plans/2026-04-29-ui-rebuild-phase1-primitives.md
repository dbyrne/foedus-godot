# UI Rebuild Phase 1 — Implementation Plan

**Goal:** Build the War Council visual primitives + theme on
`foedus-godot`, with no engine, wire-protocol, or game-screen changes.

**Architecture:** New theme file, font files, and nine component
scenes under `res://components/`. New `Phase1Demo.tscn` shows every
primitive. New headless test asserts they all instantiate. Existing
`Main.tscn` and its e2e test untouched.

**Tech Stack:** Godot 4.3, GDScript, GL3 Compatibility renderer.

**Spec:** `docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md`

**Branch:** `ui-rebuild-phase1-primitives` off `main`.

---

## Task ordering

Tasks land bottom-up: tokens & fonts first (every other component
depends on them), then leaf components (Crest, BrassPlate, WaxEnvelope),
then composites (CouncilHex, TensionMeter, ScalesOfLeverage, Throne),
then the wrapper (CouncilShell), then the demo scene + test.

Each task is one commit. TDD where it makes sense; for visual
components, "test" is "demo scene shows the variant correctly + headless
loader passes".

---

## Task 1: Theme tokens autoload

**Files:**
- Create: `scripts/Tokens.gd`
- Modify: `project.godot` (add Tokens to autoload)

A single autoload constant module exposing colors and font paths so
every component reads from one source of truth.

```gdscript
# scripts/Tokens.gd
extends Node

# --- Color palette (War Council direction) ---
const FELT       := Color("#1a2024")
const FELT_LIGHT := Color("#26303a")
const FELT_DARK  := Color("#0e1418")
const BRASS      := Color("#c9a064")
const BRASS_DIM  := Color("#8a6f3e")
const BONE       := Color("#e8dcc4")
const BONE_DIM   := Color("#b9a98a")
const INK        := Color("#0a0e12")
const CANDLE     := Color("#f4d27a")
const BLOOD      := Color("#a8323a")
const EMBER      := Color("#e07a3c")
const AZURE      := Color("#2f5d7c")
const OCHRE      := Color("#9c7a1f")
const SABLE      := Color("#3d6b3a")

# --- Player palette (player_id 0..3 → color pair) ---
const PLAYER_COLORS := {
    0: { "main": BLOOD, "dim": Color("#6e1f25") },  # Aelia
    1: { "main": AZURE, "dim": Color("#1e3e54") },  # Borovic
    2: { "main": OCHRE, "dim": Color("#5e4912") },  # Cyrene
    3: { "main": SABLE, "dim": Color("#234221") },  # Drevan
}

const FACTION_NAMES := {
    0: "Aelia", 1: "Borovic", 2: "Cyrene", 3: "Drevan"
}
const FACTION_TAGS := {
    0: "AEL", 1: "BOR", 2: "CYR", 3: "DRE"
}

# --- Font paths (loaded by theme; components reference by tag) ---
const FONT_DISPLAY_BOLD  := "res://fonts/PlayfairDisplay-Bold.ttf"
const FONT_DISPLAY_BLACK := "res://fonts/PlayfairDisplay-Black.ttf"
const FONT_SERIF         := "res://fonts/CormorantGaramond-Regular.ttf"
const FONT_SERIF_ITALIC  := "res://fonts/CormorantGaramond-Italic.ttf"
const FONT_SERIF_BOLD    := "res://fonts/CormorantGaramond-Bold.ttf"
const FONT_SANS_BOLD     := "res://fonts/IBMPlexSans-Bold.ttf"
const FONT_MONO          := "res://fonts/JetBrainsMono-Regular.ttf"
const FONT_MONO_MEDIUM   := "res://fonts/JetBrainsMono-Medium.ttf"
```

In `project.godot`, append to the `[autoload]` section:

```
Tokens="*res://scripts/Tokens.gd"
```

(`*` prefix = singleton accessible as `Tokens.BRASS` etc. anywhere.)

**Steps:**
- [ ] Write `scripts/Tokens.gd`.
- [ ] Add Tokens autoload to `project.godot`.
- [ ] Smoke: `godot --headless --quit` — should exit 0 with no parser
  errors.
- [ ] Commit: `theme: Tokens autoload (color palette + font paths)`.

---

## Task 2: Fonts

**Files:**
- Create: `fonts/PlayfairDisplay-Bold.ttf`
- Create: `fonts/PlayfairDisplay-Black.ttf`
- Create: `fonts/CormorantGaramond-Regular.ttf`
- Create: `fonts/CormorantGaramond-Italic.ttf`
- Create: `fonts/CormorantGaramond-Bold.ttf`
- Create: `fonts/IBMPlexSans-Bold.ttf`
- Create: `fonts/JetBrainsMono-Regular.ttf`
- Create: `fonts/JetBrainsMono-Medium.ttf`
- Create: `fonts/LICENSES.md`

All four families are SIL OFL or Apache 2.0 — bundle freely.

**Steps:**
- [ ] Download from upstream:
  - Playfair Display: https://github.com/clauseggers/Playfair-Display
  - Cormorant Garamond: https://github.com/CatharsisFonts/Cormorant
  - IBM Plex Sans: https://github.com/IBM/plex
  - JetBrains Mono: https://github.com/JetBrains/JetBrainsMono
- [ ] Place in `fonts/`.
- [ ] Write `fonts/LICENSES.md` listing source URLs and license name per
  family.
- [ ] Verify each is recognized by Godot: open project in editor, check
  no missing-font warnings.
- [ ] Commit: `fonts: bundle Playfair Display, Cormorant Garamond, IBM
  Plex Sans, JetBrains Mono`.

---

## Task 3: War Council theme

**Files:**
- Create: `themes/war_council_theme.tres`

Define the theme via Godot's `.tres` format (text-based; can be created
by hand). Key bindings:

- `default_font = JetBrainsMono-Regular` (used for fallback; mono is
  always safe for chrome).
- `default_font_size = 14`
- `Label/colors/font_color = BONE`
- `Button/colors/font_color = INK`
- `Button/styles/normal = StyleBoxFlat with BRASS gradient`
- `Button/styles/hover = StyleBoxFlat with CANDLE accent`
- `LineEdit/colors/font_color = BONE`
- `LineEdit/styles/normal = StyleBoxFlat with FELT_LIGHT background +
  BRASS_DIM border`
- `Panel/styles/panel = StyleBoxFlat with FELT background + BRASS_DIM
  inner border`

The theme is referenced by the new `Phase1Demo.tscn` only in this
phase.

**Steps:**
- [ ] Create `themes/war_council_theme.tres` (hand-write the resource
  file; or open Godot editor, build the theme via UI, save).
- [ ] Verify theme loads in editor without warnings.
- [ ] Commit: `theme: war council theme (palette + button/label/panel
  styles)`.

---

## Task 4: BrassPlate component

**Files:**
- Create: `components/BrassPlate.tscn`
- Create: `components/BrassPlate.gd`

Engraved label chrome — a small rounded rectangle with a brass gradient
StyleBox, ink-colored small-caps text inside, drop shadow.

```gdscript
# components/BrassPlate.gd
extends Control
class_name BrassPlate

@export var text: String = "" :
    set(value): text = value; _refresh()

func _ready() -> void: _refresh()

func _refresh() -> void:
    var lbl := $Label as Label
    if lbl:
        lbl.text = text.to_upper()
```

The `.tscn` has a Panel with a StyleBoxFlat (brass→brassDim gradient, 1px
ink border, drop shadow), containing a Label with `IBMPlexSans-Bold`,
size 10, BONE→INK color, letter-spacing 0.3em (Godot uses
`theme_override_constants/spacing` for letter spacing in TextLine).

**Steps:**
- [ ] Build `BrassPlate.tscn` in the editor or hand-author the .tscn.
- [ ] Verify it renders at multiple sizes (12px, 14px) without text
  clipping.
- [ ] Commit: `components: BrassPlate (engraved label chrome)`.

---

## Task 5: Crest component

**Files:**
- Create: `components/Crest.tscn`
- Create: `components/Crest.gd`

Sculpted heraldic shield with player color, drawn via `_draw()` on a
`Control`. Sigil per player (4 distinct shapes from
`d3-council-base.jsx:84-88`). Optional `broken` overlay (dark cross).
Optional `dim` filter (modulate down).

```gdscript
# components/Crest.gd
extends Control
class_name Crest

@export var player_id: int = 0 : set(v): player_id = v; queue_redraw()
@export var crest_size: int = 40 : set(v): crest_size = v; custom_minimum_size = Vector2(v, v * 70.0/60.0); queue_redraw()
@export var broken: bool = false : set(v): broken = v; queue_redraw()
@export var dim: bool = false : set(v): dim = v; queue_redraw()

func _draw() -> void:
    var p = Tokens.PLAYER_COLORS[player_id]
    var main = p.main
    var dim_c = p.dim
    if dim:
        main = main.darkened(0.4); dim_c = dim_c.darkened(0.4)
    # Draw shield path: M 6 6 L 54 6 L 54 38 C 54 56 30 66 30 66 ...
    # Use a PackedVector2Array of bezier-sampled points, scaled to size.
    var pts := _shield_outline(crest_size)
    draw_colored_polygon(pts, main)
    draw_polyline(pts, Tokens.BRASS, 1.5)
    _draw_sigil(player_id, crest_size)
    if broken:
        var s := crest_size
        draw_line(Vector2(s*0.23, s*0.4), Vector2(s*0.77, s*0.8), Tokens.INK, 3.0)
        draw_line(Vector2(s*0.23, s*0.4), Vector2(s*0.77, s*0.8), Tokens.BLOOD, 1.5)

func _shield_outline(s: int) -> PackedVector2Array:
    # Sample the SVG path "M 6 6 L 54 6 L 54 38 C 54 56 30 66 30 66 C 30 66 6 56 6 38 Z"
    # at scale s/60. Bezier with control points (54, 56) (30, 66).
    # Return ~24 points along the curved bottom for smooth render.
    var pts := PackedVector2Array()
    var k := s / 60.0
    pts.append(Vector2(6, 6) * k)
    pts.append(Vector2(54, 6) * k)
    pts.append(Vector2(54, 38) * k)
    # Bezier sample bottom curve
    for i in range(0, 21):
        var t := i / 20.0
        var p := _bezier(Vector2(54, 38), Vector2(54, 56), Vector2(30, 66), Vector2(30, 66), t) * k
        pts.append(p)
    for i in range(0, 21):
        var t := i / 20.0
        var p := _bezier(Vector2(30, 66), Vector2(30, 66), Vector2(6, 56), Vector2(6, 38), t) * k
        pts.append(p)
    return pts

func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
    var u := 1.0 - t
    return u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

func _draw_sigil(pid: int, s: int) -> void:
    var k := s / 60.0
    match pid:
        0:  # Aelia — diamond/spear
            var pts := PackedVector2Array([
                Vector2(30, 18) * k, Vector2(36, 30) * k,
                Vector2(30, 50) * k, Vector2(24, 30) * k,
            ])
            draw_colored_polygon(pts, Tokens.BONE)
        1:  # Borovic — circle + vertical bar
            draw_arc(Vector2(30, 32) * k, 10 * k, 0, TAU, 32, Tokens.BONE, 2.0)
            draw_line(Vector2(30, 20) * k, Vector2(30, 48) * k, Tokens.BONE, 2.0)
        2:  # Cyrene — sun (small disk + radiating)
            draw_circle(Vector2(30, 32) * k, 6 * k, Tokens.BONE)
            for ang_deg in [0, 45, 90, 135, 180, 225, 270, 315]:
                var ang := deg_to_rad(ang_deg)
                draw_line(Vector2(30, 32) * k, Vector2(30 + cos(ang)*12, 32 + sin(ang)*12) * k, Tokens.BONE, 1.2)
        3:  # Drevan — stylized leaf
            var leaf := PackedVector2Array([
                Vector2(30, 16) * k, Vector2(38, 24) * k,
                Vector2(38, 36) * k, Vector2(30, 50) * k,
                Vector2(22, 36) * k, Vector2(22, 24) * k,
            ])
            draw_colored_polygon(leaf, Tokens.BONE)
```

**Steps:**
- [ ] Write `Crest.gd`.
- [ ] Build `Crest.tscn` (just a Control with the script attached and a
  custom_minimum_size).
- [ ] Add to demo scene: instance one Crest per player_id 0..3, plus
  one with `broken=true`, one with `dim=true`. Visually verify in
  editor.
- [ ] Commit: `components: Crest (heraldic shield + per-player sigil)`.

---

## Task 6: WaxEnvelope component

**Files:**
- Create: `components/WaxEnvelope.tscn`
- Create: `components/WaxEnvelope.gd`

Smaller drawable. Bone-colored rectangle with diagonal fold lines and
optional wax seal disk (color + label). Used for orders/aid icons.

Approach: identical pattern to Crest — `_draw()` overrides.

**Steps:**
- [ ] Write `WaxEnvelope.gd` translating the SVG in
  `d3-council-base.jsx:230-238`.
- [ ] Build `.tscn`.
- [ ] Add 4 variants to demo: sealed/unsealed × labeled/unlabeled.
- [ ] Commit: `components: WaxEnvelope (sealed letter / aid token icon)`.

---

## Task 7: UnitPiece component

**Files:**
- Create: `components/UnitPiece.tscn`
- Create: `components/UnitPiece.gd`

`Node2D` (drawn at world coordinates inside the hex map). Concentric
disks (ink ring, dim color, main color), white glint ellipse, label
glyph. Optional `selected` halo (candle dashed circle). Optional
`ghost` modulate.

Translated from `d3-council-base.jsx:91-107`.

**Steps:**
- [ ] Write `UnitPiece.gd`.
- [ ] Build `.tscn`.
- [ ] Demo: 4 variants per player, plus selected, plus ghost. 12
  pieces total in a row.
- [ ] Commit: `components: UnitPiece (top-down sculpted disk)`.

---

## Task 8: TensionMeter component

**Files:**
- Create: `components/TensionMeter.tscn`
- Create: `components/TensionMeter.gd`

Phase label (BrassPlate-style small caps), 1px brass divider,
heartbeat fill bar (gradient varies by phase), timer on right (mono).

```gdscript
extends Control
class_name TensionMeter

@export_enum("negotiation", "orders") var phase: String = "negotiation" : set(v): phase = v; queue_redraw()
@export var timer_text: String = "02:14" : set(v): timer_text = v; _refresh_timer()
@export_range(0.0, 1.0, 0.01) var value: float = 0.5 : set(v): value = v; queue_redraw()
```

Children: a Label for phase, a ProgressBar styled with gradient, a
Label for timer.

Heartbeat polyline: `_draw()` overlay drawing a stylized ECG path at
20% opacity over the fill.

**Steps:**
- [ ] Write `TensionMeter.gd`.
- [ ] Build `.tscn` with the three labels + progress bar.
- [ ] Demo: one in NEGOTIATION, one in ORDERS, both at 0%, 50%, 100%
  values.
- [ ] Commit: `components: TensionMeter (phase + timer + heartbeat)`.

---

## Task 9: CouncilHex component

**Files:**
- Create: `components/CouncilHex.tscn`
- Create: `components/CouncilHex.gd`

Largest primitive. Drawn at axial coordinates (q, r); pixel position
computed via `Tokens` constants:

```gdscript
const HEX_R := 32
static func hex_to_px(q: int, r: int) -> Vector2:
    return Vector2(HEX_R * sqrt(3) * (q + r/2.0), HEX_R * 1.5 * r)
```

`_draw()` paints:
1. Drop-shadow hexagon, offset (0, +2)
2. Base hexagon, color from `terrain` (plain/forest/mountain/water,
   palette in spec).
3. Optional owner-tint inset hex (1.5px stroke at owner.color, 0.55
   opacity).
4. Terrain decals: mountain peak path, forest tree marks, water wave
   marks (translate from `d3-council-base.jsx:130-156`).
5. Supply marker if `tile.supply > 0` (chest at supply=1, larger crown
   at supply=2).
6. Home banner if `tile.home != null`.
7. Selection halo if `selected`.
8. Highlight overlay if `highlight != null`.
9. UnitPiece child instance positioned at (0, 0) if `tile.unit`.

**Steps:**
- [ ] Translate hex math to GDScript. Add `Tokens.HEX_R = 32`.
- [ ] Write `CouncilHex.gd`.
- [ ] Build `.tscn`.
- [ ] Demo: 8 hexes in a row showing terrain×supply×home variants.
- [ ] Commit: `components: CouncilHex (terrain + supply + home + unit)`.

---

## Task 10: ScalesOfLeverage component

**Files:**
- Create: `components/ScalesOfLeverage.tscn`
- Create: `components/ScalesOfLeverage.gd`

Animated balance — a center post, a beam that tilts based on
`leftLoad - rightLoad`, two pans hanging from beam ends, optional
weight-disk count on each pan.

```gdscript
extends Node2D
class_name ScalesOfLeverage

@export_range(-1.0, 1.0, 0.01) var tilt: float = 0.0
@export var left_load: int = 0
@export var right_load: int = 0
```

`_draw()` rotates beam by `tilt * 0.4` rad (max ~23° tilt). Pans drawn
as small bowls below each beam end. Each load = small bone disk stacked
on the pan.

**Steps:**
- [ ] Write `ScalesOfLeverage.gd`.
- [ ] Build `.tscn`.
- [ ] Demo: 5 instances at tilt = -1, -0.5, 0, +0.5, +1 with matching
  load counts.
- [ ] Commit: `components: ScalesOfLeverage (animated balance for leverage)`.

---

## Task 11: Throne component

**Files:**
- Create: `components/Throne.tscn`
- Create: `components/Throne.gd`

Used in matchmaking screen (Phase 3). Building primitive now per spec
§9. Simple Control: high-back chair silhouette in brass tones, with
optional Crest mounted in the seat or "(empty)" italic if unoccupied.

**Steps:**
- [ ] Write `Throne.gd`.
- [ ] Build `.tscn`.
- [ ] Demo: 4 thrones in a row, alternating occupied/empty.
- [ ] Commit: `components: Throne (matchmaking seat)`.

---

## Task 12: CouncilShell wrapper

**Files:**
- Create: `components/CouncilShell.tscn`
- Create: `components/CouncilShell.gd`

Full-screen wrapper. Layered:
1. Background gradient (felt → feltLight radial highlight at top-left,
   feltDark vignette at bottom-right).
2. Noise overlay (NoiseTexture2D, mix-mode overlay, ~18% alpha).
3. Inner brass frame (ColorRect with border drawn via `_draw`).
4. Corner ornaments (4 small SVG-translated shapes at corners).
5. Children container (anchors fill, padded 24px from frame).

Every game screen will inherit/instance this.

**Steps:**
- [ ] Write `CouncilShell.gd`.
- [ ] Build `.tscn` with the layering.
- [ ] Demo: one CouncilShell with a single BrassPlate inside reading
  "DEMO".
- [ ] Commit: `components: CouncilShell (felt background + gilded frame)`.

---

## Task 13: Phase 1 demo scene

**Files:**
- Create: `scenes/Phase1Demo.tscn`
- Create: `scripts/Phase1Demo.gd`

A scrollable VBoxContainer inside a CouncilShell. Each section is a
`MarginContainer` with a header BrassPlate and a horizontal row of the
component variants. Sections in order:

1. Crests (4 players + broken + dim = 6 instances)
2. UnitPieces (4 players × 3 states = 12 instances)
3. CouncilHex (8 terrain/supply variants)
4. BrassPlate (3 sizes)
5. WaxEnvelope (4 sealed/labeled variants)
6. TensionMeter (negotiation, orders × 3 values = 6)
7. ScalesOfLeverage (5 tilt levels)
8. Throne (4: 2 occupied, 2 empty)

`scripts/Phase1Demo.gd` is just an `extends Control` shell — the scene
is mostly declarative .tscn.

**Steps:**
- [ ] Build `Phase1Demo.tscn`.
- [ ] Run in editor (F6 with the scene focused) — visually verify all
  sections render without overlap or clipping.
- [ ] Commit: `scenes: Phase1Demo (visual review of all primitives)`.

---

## Task 14: Headless test

**Files:**
- Create: `scripts/test_phase1_primitives.gd`

```gdscript
# scripts/test_phase1_primitives.gd
extends SceneTree

const PRIMITIVES := [
    "res://components/CouncilShell.tscn",
    "res://components/Crest.tscn",
    "res://components/UnitPiece.tscn",
    "res://components/CouncilHex.tscn",
    "res://components/BrassPlate.tscn",
    "res://components/TensionMeter.tscn",
    "res://components/WaxEnvelope.tscn",
    "res://components/ScalesOfLeverage.tscn",
    "res://components/Throne.tscn",
]

func _init() -> void:
    var failures := 0
    for p in PRIMITIVES:
        var ps := load(p)
        if ps == null:
            push_error("FAIL: could not load %s" % p)
            failures += 1
            continue
        var inst = ps.instantiate()
        if inst == null:
            push_error("FAIL: could not instantiate %s" % p)
            failures += 1
            continue
        inst.queue_free()
        print("ok: ", p)
    var demo := load("res://scenes/Phase1Demo.tscn")
    if demo == null:
        push_error("FAIL: Phase1Demo.tscn missing")
        failures += 1
    else:
        var dinst = demo.instantiate()
        if dinst == null:
            push_error("FAIL: Phase1Demo did not instantiate")
            failures += 1
        else:
            dinst.queue_free()
            print("ok: Phase1Demo.tscn")
    if failures == 0:
        print("--- ALL OK ---")
        quit(0)
    else:
        print("--- %d FAILURES ---" % failures)
        quit(1)
```

**Steps:**
- [ ] Write the script.
- [ ] Run: `godot --headless --script res://scripts/test_phase1_primitives.gd`.
- [ ] Verify: exit 0, all "ok:" lines printed.
- [ ] Verify the existing tests still pass:
  - `godot --headless --script res://scripts/test_smoke.gd`
  - (e2e requires play-server, defer to user)
- [ ] Commit: `tests: phase 1 primitive smoke (load + instantiate all
  components)`.

---

## Task 15: README update

**Files:**
- Modify: `README.md`

Add a "Visual primitives (Phase 1)" subsection mentioning the demo
scene and how to view it; add the new headless test invocation under
the Tests section.

**Steps:**
- [ ] Update README sections.
- [ ] Commit: `docs: README — Phase 1 demo scene + test`.

---

## Done state

After Task 15, the branch contains:

- 9 component scenes
- 8 font files + LICENSES
- 1 new theme + 1 new autoload
- 1 demo scene + script
- 1 new headless test
- 0 changes to `Main.tscn`, `Main.gd`, `HexMap.gd`, `GameClient.gd`,
  `test_smoke.gd`, or `test_e2e.gd`

The existing app keeps working unchanged. Phase 2 will start replacing
the game screens.

## Open during implementation

- Confirm font licensing while downloading (spec §11.1).
- If any primitive turns out to need significantly more state than
  what's spec'd, stop and ask before scope-creeping the .gd file.
- Hex math (`HEX_R = 32`) lives in `Tokens.gd` — make sure
  `HexMap.gd`'s existing math doesn't collide. May need a one-line
  refactor of `HexMap.gd` to use `Tokens.HEX_R`; if so, keep that
  refactor minimal and additive.
