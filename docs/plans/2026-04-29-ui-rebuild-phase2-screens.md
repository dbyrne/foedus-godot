# UI Rebuild Phase 2 — Implementation Plan

**Goal:** Build six War Council game screens on top of Phase 1
primitives, ship in four sub-phases (2a / 2b / 2c / 2d), keep `Main.tscn`
working until 2d's flag-day swap.

**Architecture:** Phase 1 components stay frozen unless they need
tweaks. New screens compose them programmatically inside their own
`.tscn` roots. A `CouncilGame.gd` controller dispatches phase routing.
The `GameClient.gd` HTTP wrapper from v0 is reused unchanged.

**Spec:** `docs/specs/2026-04-29-ui-rebuild-phase2-screens.md`
**Branch base:** `ui-rebuild-phase1-primitives` (rebases onto Phase 1
if Phase 1 changes during review).

---

## Sub-phase 2a · Foundation + Negotiation

The first PR. Ships when 2a's acceptance criteria pass; subsequent
sub-phases are separate PRs.

### File structure for 2a

| File | Status | Responsibility |
|---|---|---|
| `scripts/council/CouncilGame.gd` | Create | Top-level controller, phase router, view-state dispatcher |
| `scripts/council/PressController.gd` | Create | Holds turn-local intent/stance/aid/chat state, exposes `seal_intent()` |
| `scripts/council/ViewModel.gd` | Create | Pure data: takes a view payload from the server, exposes typed accessors (`my_units()`, `tile(q, r)`, `pairwise(p1, p2)`) |
| `components/HexBoard.gd` | Create | Node2D rendering a full hex grid from ViewModel; click + drag tracking |
| `components/Sociogram.gd` | Create | 4-crest polygon panel with leverage arcs and stance tints |
| `components/CourtPanel.gd` | Create | Right-rail container: Sociogram + per-pair stance dropdowns + aid balance + chat draft |
| `scenes/council/CouncilNegotiation.tscn` + `.gd` | Create | Negotiation screen — composes everything above |
| `scenes/council/CouncilEntry.tscn` + `.gd` | Create | Launcher: connect to server, pick game, choose `v0 mode` (still routes to existing `Main.tscn`) or `Council mode` (routes to CouncilNegotiation) |
| `scripts/test_phase2a_negotiation.gd` | Create | Headless smoke: load each new script, instantiate Negotiation scene, assert all panels present |
| `scripts/capture_phase2a_negotiation.gd` | Create | PNG capture for visual review |

### Task ordering

Bottom-up like Phase 1: ViewModel first, then HexBoard, then Sociogram,
then CourtPanel, then PressController + CouncilGame, then the
Negotiation scene, then the Entry launcher, then tests.

---

### Task 1 — ViewModel

**Files:** `scripts/council/ViewModel.gd`, `tests/test_view_model.gd`
*(unit test, uses synthetic JSON payload — no Godot scene dependency)*

ViewModel wraps a `view` payload from `GameClient.view(game_id, player)`
and exposes typed accessors. Pure logic. Unit-testable headlessly.

```gdscript
class_name ViewModel extends RefCounted

var _raw: Dictionary

func _init(view_payload: Dictionary) -> void:
    _raw = view_payload

func phase() -> String:                # "negotiation" | "orders" | "resolved"
func turn() -> int:
func my_player_id() -> int:
func num_players() -> int:
func tiles() -> Array:                 # list of tile dicts (Phase 1 schema)
func tile_at(q: int, r: int) -> Dictionary:
func my_units() -> Array:              # [{id, label, q, r}]
func unit_by_id(uid: int) -> Dictionary
func legal_orders_for(uid: int) -> Array  # passes through view's legal_orders
func score(pid: int) -> float
func aid_tokens(pid: int) -> int       # only `my_player_id()` returns nonzero
func aid_given(from_pid: int, to_pid: int) -> int
func leverage(from_pid: int, to_pid: int) -> int  # signed
func stance(from_pid: int, to_pid: int) -> String # "ally" | "neutral" | "hostile"
func declared_intents() -> Array       # all players' declared press intents
func betrayals() -> Array              # BetrayalObservation list
func detente_streak() -> int
func is_terminal() -> bool
func winners() -> Array                # list of pid ints
```

**Steps:**
- [ ] Write failing test with synthetic payload from the existing
  `tests/test_e2e.gd` (capture one real view via the play-server and
  pin it as a fixture).
- [ ] Implement getters one at a time; each gets a test assertion.
- [ ] Run `pytest`-style: `godot --headless --script tests/test_view_model.gd`.
- [ ] Commit: `council: ViewModel (typed accessors over view payload)`.

---

### Task 2 — HexBoard

**Files:** `components/HexBoard.gd`

A Node2D that renders a full hex grid. Reads from a ViewModel; emits
signals on click and drag.

```gdscript
class_name HexBoard extends Node2D

signal tile_clicked(q: int, r: int, button: int)
signal unit_clicked(unit_id: int, button: int)
signal drag_proposed(from_unit_id: int, to_q: int, to_r: int)

@export var view_model: ViewModel
@export var selected_unit_id: int = -1

func set_view_model(vm: ViewModel) -> void
```

Internally instantiates one `CouncilHex` Node2D per tile, positions
them via `Tokens.hex_to_px(q, r)`, mounts a `UnitPiece` inside each
hex that has a unit. Tracks drag state in `_input(event)`:

- `mouse_button=LEFT, pressed` on own unit → start drag.
- `mouse_motion` while dragging → emit ghost-arrow draw call.
- `mouse_button=LEFT, released` on a tile → emit `drag_proposed`.
- `mouse_button=RIGHT, released` on any tile → emit
  `tile_clicked(_, _, RIGHT)` for cancel-order semantics.

**Steps:**
- [ ] Write headless smoke test: load HexBoard, assign a ViewModel
  with 7 tiles, assert 7 CouncilHex children exist.
- [ ] Implement render path.
- [ ] Implement click signal emission.
- [ ] Defer drag-state to 2b (the gesture is irrelevant to the
  Negotiation phase; only Move/Support intents declared via the press
  panel matter in 2a).
- [ ] Commit: `components: HexBoard (renders ViewModel grid, click signals)`.

---

### Task 3 — Sociogram

**Files:** `components/Sociogram.gd`

A Control panel that renders 4 Crests at fixed polygon positions and
draws weighted arcs between them showing the leverage and stance state.

Layout (as per design): 4 corners of a 500×220 box. Top-left = my
player, others positioned clockwise.

Arcs:
- **Stance tint**: ally = sable green, neutral = bone-dim, hostile = blood.
- **Stroke width**: scaled by `|leverage|`; clamp to [1.5, 6.0].
- **Direction marker**: arrowhead toward the *creditor* player (the one
  who's owed). When leverage = 0, arc is a thin neutral line.
- **Label**: italic Cormorant text near the midpoint with `leverage +N`
  or `even` and the underlying `aid_given` totals on a second line.

**Steps:**
- [ ] Write smoke test: load Sociogram, assign a 4-player ViewModel,
  assert 4 Crests + 6 arcs (one per pair) drawn.
- [ ] Implement layout + arc drawing.
- [ ] Click on a crest emits `crest_clicked(pid)` signal (the Pairwise
  dossier in 2d will subscribe).
- [ ] Commit: `components: Sociogram (relations panel)`.

---

### Task 4 — CourtPanel

**Files:** `components/CourtPanel.gd`

Right-rail container that wraps Sociogram + per-pair stance dropdowns
+ aid balance + chat draft. Pure layout container; no game logic
beyond emitting signals when the user changes a stance, toggles an
aid spend, or types chat.

Signals:
- `stance_changed(other_pid, new_stance)`
- `aid_spend_toggled(target_unit_id, target_order, on)`
- `chat_text_changed(text)`

**Steps:**
- [ ] Smoke test.
- [ ] Implement layout.
- [ ] Wire signals.
- [ ] Commit: `components: CourtPanel (right-rail container)`.

---

### Task 5 — PressController

**Files:** `scripts/council/PressController.gd`

Owns turn-local press state. Listens to CourtPanel signals + HexBoard
intent gestures (deferred to 2b — for 2a, intents are declared via
the press panel's "declare intent for unit X" sub-control).

```gdscript
class_name PressController extends RefCounted

var stance: Dictionary = {}        # other_pid → "ally"|"neutral"|"hostile"
var intents: Array = []            # [{unit_id, order_dict, recipients}]
var aid_spends: Array = []         # [{target_unit_id, target_order_dict}]
var chat_draft: String = ""

signal updated  # emitted when any field changes

func set_stance(other_pid, value)
func add_intent(unit_id, order, recipients)
func remove_intent(unit_id)
func toggle_aid(target_unit_id, target_order)
func set_chat(text)

func to_press_payload() -> Dictionary  # shape that GameClient submits
func to_aid_payload() -> Array
```

**Steps:**
- [ ] Unit test the payload-shaping methods with synthetic input.
- [ ] Implement signal-emitting setters.
- [ ] Commit: `council: PressController (turn-local state)`.

---

### Task 6 — CouncilGame controller

**Files:** `scripts/council/CouncilGame.gd`

Top-level controller. Owns the GameClient, holds the current
ViewModel, dispatches between Negotiation / Orders / Resolution scenes
based on `view.phase`. Exposes `view_player` property so a single
human can hot-swap perspectives during testing.

Listens to GameClient signals (`response`, `failure`); routes the
view payload into the active screen; handles `seal_intent` and
`submit_orders` flows.

**Steps:**
- [ ] Smoke test: instantiate CouncilGame, mount a CouncilNegotiation
  scene, feed a synthetic view → assert the screen renders.
- [ ] Implement phase-router logic.
- [ ] Wire to GameClient.
- [ ] Commit: `council: CouncilGame controller (phase router)`.

---

### Task 7 — CouncilNegotiation scene

**Files:** `scenes/council/CouncilNegotiation.tscn`,
`scenes/council/CouncilNegotiation.gd`

Composes everything: CouncilShell wraps a 2-column layout. Left
column: TensionMeter at top, HexBoard below. Right column: CourtPanel.
Bottom: declared-intents row (one BrassPlate per published intent
across all players), Chat box, "Seal Intent" button.

**Steps:**
- [ ] Smoke test loads scene, asserts top-level children.
- [ ] Build the .tscn with a Control root + script attachment.
- [ ] Implement the build-layout function in `.gd`.
- [ ] Wire CouncilGame view → screen render + screen signals →
  CouncilGame.
- [ ] Capture: visual review render at 1280×800.
- [ ] Commit: `scenes: CouncilNegotiation (full negotiation screen)`.

---

### Task 8 — CouncilEntry launcher

**Files:** `scenes/council/CouncilEntry.tscn`,
`scenes/council/CouncilEntry.gd`

Temporary launcher (drops out at 2d). Asks: server URL, game
selection, `v0 mode` vs `Council mode`. On Council mode, instantiates
CouncilGame; on v0 mode, opens existing `Main.tscn`.

**Steps:**
- [ ] Build minimal launcher scene.
- [ ] Wire mode selection.
- [ ] `project.godot` `run/main_scene` stays at `Main.tscn` for now —
  CouncilEntry is opened explicitly via F6 during development.
- [ ] Commit: `scenes: CouncilEntry (Council vs v0 launcher)`.

---

### Task 9 — Phase 2a smoke test + integration test

**Files:** `scripts/test_phase2a_negotiation.gd`,
`scripts/capture_phase2a_negotiation.gd`

Headless smoke: load every new script, instantiate the Negotiation
scene with a fixture ViewModel (no live server), assert structural
correctness.

Integration test (manual for 2a, automated in 2d): connect to a real
play-server, run a game in Council mode for 3 turns, observe the
phase router transitions correctly.

**Steps:**
- [ ] Write the headless smoke.
- [ ] Update `README.md` with new test invocation.
- [ ] Run all three tests: smoke, phase-1 primitives, phase-2a
  negotiation. All pass.
- [ ] Commit: `tests: phase 2a headless smoke + capture`.

---

### Task 10 — Plan amendment + PR

**Files:** Update `docs/plans/2026-04-29-ui-rebuild-phase2-screens.md`
with any deviations encountered during 2a implementation. Push branch.
Open PR.

---

### Implementation note (post-execution amendment, 2026-04-29)

Five deviations from the original 2a plan, all minor:

1. **Components use loose-typed cross-references** (`var press = null` not
   `var press: PressController = null`) for the same reason Phase 1 needed
   preload-paths over class_names: headless `--script` invocation parses
   before class_name registration completes.

2. **`is_inside_tree()` early-exits removed** from rebuild functions.
   They caused silent no-ops in headless mode where `root.add_child()`
   doesn't satisfy `is_inside_tree()` until process loops start.

3. **`_on_view_changed` defers via `call_deferred`** when a scene's
   children haven't yet been built (i.e., when `attach_game` is called
   before `_ready` has run). Lets the controller wire up before
   `_build_layout` finishes.

4. **ViewModel `_init` takes a default empty Dict** so generic
   `script.new()` instantiation tests work. Production calls always
   pass a payload.

5. **Sociogram label-text rendering**: still uses raw `draw_string` on
   variable Cormorant Garamond Italic. At negotiation-screen scale the
   labels render legibly; a Label-child rewrite (per Phase 1 lesson)
   may not be needed, but flag for re-examination if labels regress at
   smaller sizes.

---

## Sub-phase 2b · Orders + drag-from-piece

### Implementation note (post-execution amendment, 2026-04-29)

Shipped with these specifics:

1. **OrderArrow** is a Node2D with four kinds (Move solid+filled-head,
   SupportMove dashed+open-head, SupportHold dashed-ring around the
   target unit, Hold solid ring on own unit). Color from
   Tokens.player_main; ghost variant lowers alpha for in-flight drags.

2. **HexBoard drag-state** lives entirely in `_input` on the existing
   Node2D. Mouse-down on an own unit starts a drag; motion updates the
   ghost-arrow draw; mouse-up emits `drag_proposed(from_unit_id,
   to_node_id)`. Right-click is forwarded as a normal click (the
   Orders scene interprets right-click on an own unit as cancel-order).

3. **OrderController** is a separate RefCounted (parallel to
   PressController). Holds `orders[unit_id] = order_dict`. Its
   `interpret_drag` static method does the gesture-to-Order mapping
   using ViewModel.legal_orders_for(uid) — the UI never invents an
   order the server hasn't already greenlit.

4. **Phase router** lives in CouncilEntry. The launcher subscribes to
   CouncilGame.phase_transition and swaps between
   CouncilNegotiation.tscn and CouncilOrders.tscn. The active scene's
   `attach_game(game)` is called on mount so it picks up the existing
   ViewModel without a fresh /view fetch.

5. **Test fixture refresh** — `legal_orders` was using `{"kind":...}`
   keys; the actual wire format from `serialize_order` uses `{"type":
   ...}`. Fixture corrected; `interpret_drag` walks the legal set
   matching by `type` field.

### Original sketch

High-level scope (sketch from initial plan, kept for reference):

- Extend HexBoard with drag-state machine (mousedown on own unit →
  rubber-band arrow → mouseup on target).
- New `OrderArrow.gd` component for queued-order rendering.
- New `CouncilOrders.tscn` — same layout as Negotiation but with an
  "Orders Panel" instead of CourtPanel; lists queued orders + Submit /
  Reset buttons.
- CouncilGame routes phase=orders here.
- Right-click on a queued order cancels it.
- Drag from your unit to a friendly Move target → SupportMove. Drag to
  a friendly Holding unit → SupportHold.

Estimated 5 tasks, ~3–5 days.

---

## Sub-phase 2c · Resolution playback

### Implementation note (post-execution amendment, 2026-04-29)

Shipped with these specifics:

1. **ResolutionTimeline** is pure-data RefCounted — diffs two view
   payloads and yields events {move, dislodge, ownership, leverage,
   score}. Foedus's resolution log isn't transmitted (deliberate wire
   omission), so the diff approach is the only way to reconstruct
   what happened. Six unit-test cases cover each event kind
   independently + an identical-snapshots null case.

2. **CombatBeat** is a Node2D with a `play(duration)` self-tween that
   animates radial expansion + crater + fade, then queue_free()'s.
   Sibling pattern lets CouncilResolution spawn many short-lived
   beats without managing their lifecycle.

3. **CouncilResolution** schedules events sequentially via chained
   Tweens (each event creates a tween that fires the next event on
   completion). Move events render a CombatBeat in the player's
   color at the destination; dislodges render a blood-red beat at
   the source; leverage events render a brief gold thread between
   the two players' homes.

4. **Auto-mount of Resolution between turns** is not yet wired in
   CouncilEntry's phase router — Resolution is invoked
   programmatically via `play_between(prev_view, curr_view)`. The
   auto-flow (detect turn number increase → fetch /history snapshots
   → mount Resolution → on `playback_finished` mount next
   Negotiation) lands in 2d.

5. **Score / ownership events** are surfaced as data but don't yet
   have dedicated visuals — they're implied by the move/dislodge
   beats. Phase 3 polish: floating "+N" wax-seal motes from each
   scoring player's home, brief tile-color fade for ownership flips.

### Original sketch

High-level scope (sketch from initial plan, kept for reference):

- New `ResolutionTimeline.gd` (pure logic, unit-testable) takes two
  consecutive snapshots and produces an event list with timestamps.
- New `CouncilResolution.tscn` runs a Tween over the timeline:
  - Unit lerps for successful Moves
  - CombatBeat flashbulbs at dislodgements
  - WaxEnvelope motes float from rewarded players
  - Brief gold thread for leverage fires
- Skip / pause / step controls.
- Reuses existing `/games/<id>/history` endpoint — no server changes.

Estimated 6–8 tasks, ~5–7 days.

---

## Sub-phase 2d · Bookends + flag-day swap

### Implementation note (post-execution amendment, 2026-04-29)

Shipped:

1. **CouncilCoronation**: large candle-yellow "VICTORY" title, italic
   subtitle ("by treaty — détente prevailed" / "by force of arms"),
   crests for each winner side-by-side, FINAL SCORES grid with
   sovereigns highlighted, View Replay + Exit buttons.

2. **CouncilPairwise**: bilateral dossier — two crests with
   ScalesOfLeverage between them; the scales' tilt and load reflect
   the actual `aid_given[(me, them)]` ledger; leverage delta shown
   prominently with "(you owe me)" / "(I owe you)" / "even" suffix;
   stance labels for both directions; betrayal log filtered to this
   pair. Auto-focuses the player with largest |leverage| if no
   explicit `set_focus_player(pid)` call.

3. **CouncilReplay**: scrub-through-history viewer. Loads
   `/games/<id>/history` to learn the snapshot list, fetches each
   snapshot via `/history/<turn>/view/<player>` on demand (cached).
   Prev / Next / scrub-slider step through; "Play Resolution N→N+1"
   mounts the existing CouncilResolution scene over the current
   snapshot pair.

4. **Auto-resolution router**: CouncilEntry now subscribes to
   CouncilGame.view_changed, caches the previous view's payload, and
   when a new view's `turn` is greater than the cached one, mounts
   CouncilResolution.play_between(prev, curr). On
   `playback_finished`, the resolution scene queue_frees and the
   underlying Negotiation/Orders screen resumes visibility.

5. **Flag-day swap**:
   - `project.godot`: `run/main_scene` flipped from
     `res://scenes/Main.tscn` to `res://scenes/council/CouncilEntry.tscn`.
   - CouncilEntry's "v0 mode" branch removed; the launcher now offers
     a single "Take the throne" button.
   - Legacy `Main.tscn` / `Main.gd` / `HexMap.gd` / `GameClient.gd` /
     `SoundManager.gd` files remain in the repo for archeological
     reference; they're no longer entry points.

### Original sketch

High-level scope (sketch from initial plan, kept for reference):

- CouncilPairwise: bilateral dossier — opens on sociogram crest click.
  Shows ScalesOfLeverage + leverage history graph + recent supports
  + betrayal log.
- CouncilCoronation: win screen — large crowned crest + score
  breakdown.
- CouncilReplay: scrub-through-history viewer.
- Flag-day swap: `project.godot` main_scene → `CouncilEntry.tscn`;
  delete `scenes/Main.tscn`, `scripts/Main.gd`, the Bundle 4 sidebars
  in `scripts/HexMap.gd`. Keep `GameClient.gd` and `SoundManager.gd`.
- `test_smoke.gd` rewritten to assert the new Council entry's
  children.

Estimated 7–10 tasks, ~3–5 days.

---

## Risks and unknowns

1. **Hex grid size at 4-player maps.** `HEX_R = 32` may be too large
   for `continental_sweep r=3` maps (~7 hexes wide). HexBoard ships
   with adaptive scaling that fits within a target rectangle; revisit
   after capture.

2. **ViewModel test fixture rotation.** A pinned synthetic view is
   easy to write but goes stale when the engine adds fields. Pin from
   a real `/view/0` response captured at branch creation; refresh
   when wire format changes.

3. **PressController vs server state.** PressController holds
   turn-local UI state; the server is authoritative on what's been
   committed. If a player half-types an intent and disconnects, the
   intent is lost (server only sees `submit_press_tokens`). Document
   this in the code; no special recovery in 2a.

4. **Sociogram readability with 4 players.** 6 arcs in a small panel
   is dense. May need hover-to-highlight or bilateral-focus mode
   (click a crest to dim the other 3 pairs). Defer to playtest
   feedback.

---

## Done state for Phase 2 (whole phase, after 2d)

- A human plays a full 4-seat game (vs three heuristic AIs)
  end-to-end through the Council UI alone.
- All Phase 1 primitives still pass `test_phase1_primitives.gd`.
- `test_e2e.gd` still passes.
- Bundle 4 mechanics (stance, intent, aid, leverage, betrayals,
  combat reward) are all visibly engaged.
- `scenes/Main.tscn` and its scripts are gone; the Council UI is the
  default.
