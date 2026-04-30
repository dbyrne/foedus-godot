# UI Rebuild — Phase 2: Game Screens

**Status:** Spec, ready for implementation plan.
**Date:** 2026-04-29.
**Direction:** "War Council" (D3) — continues Phase 1.
**Phase 1 spec:** `docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md`
**Source design:** Claude Design handoff bundle (see Phase 1 spec for context).

## 1. Motivation

Phase 1 shipped nine reusable visual primitives and a demo scene. They
look right (verified by headless render review) but don't *do* anything —
no game state, no order entry, no resolution playback. Phase 2 turns
the primitives into a playable UI by building the six game screens
described in the design's `B · The Turn`, `C · Relations`, and
`D · Endgame` sections.

The existing v0 UI (`scenes/Main.tscn`) keeps working through 2a–2c so
playtests aren't blocked. The flag-day swap to the new screens lands
in 2d.

## 2. Goals and non-goals

### Goals

- Six functional game screens composed from Phase 1 primitives:
  Negotiation, Orders, Resolution playback, Pairwise dossier,
  Coronation, Replay viewer.
- Drag-from-piece order entry replaces the current
  click-select-then-click-target buttons.
- Resolution moment is animated from the existing `/history` snapshots
  (no new server-side endpoints).
- The cosmetic REVEAL transition between NEGOTIATION and ORDERS
  phases gives the two-phase rhythm visible weight.
- Existing `test_e2e.gd` continues passing throughout (no engine /
  wire changes).

### Non-goals

- **No engine changes.** Foedus's wire protocol is fixed; this is
  client-only.
- **No matchmaking, per-turn timer, or whisper.** Three deferrals
  documented in the audit. Replace matchmaking with a "join by game
  code" flow using the existing `/games` endpoint.
- **REVEAL phase is cosmetic only.** Foedus's engine continues to
  reveal intents continuously as players declare them. The UI's
  REVEAL moment is a 2-second curtain-pull animation that *marks*
  the phase transition; it does not hide information.
- **Per-component `.tscn` files** stay rare. Each screen is a single
  `.tscn` whose root script composes the primitives programmatically.
  Phase 1's experience (`Phase1Demo.gd`) showed this is reliable.
- No theme `.tres` yet — components remain self-styling. Theme
  consolidation lives at the end of Phase 2 once we know which
  control types actually need shared styles.

## 3. Sub-phase breakdown

Phase 2 ships in four sub-phases, each its own PR. Each can be
reviewed and merged independently.

### 2a · Foundation + Negotiation screen

The densest screen — proves the composition pattern. Establishes the
"Council mode" entry point so it can run alongside `Main.tscn`.

**New files:**
- `scenes/council/CouncilNegotiation.tscn` + `.gd`
- `scenes/council/CouncilEntry.tscn` + `.gd` — temporary launcher that
  asks the user "play in v0 mode" or "play in Council mode" (drops
  out at 2d when Council becomes the only path)
- `components/HexBoard.gd` — Node2D that renders a full hex grid from
  view-state Tile data; replaces the v0 `HexMap.gd`'s rendering side
  but reuses its q/r/click logic
- `components/Sociogram.gd` — relations panel (4 crests in a polygon,
  weighted directional arcs showing leverage and stance)
- `scripts/council/PressController.gd` — owns intent / stance /
  aid-spend / chat-draft state for the current turn
- `scripts/council/CouncilGame.gd` — top-level controller: holds the
  GameClient, dispatches between Negotiation/Orders/Resolution scenes
  based on phase, manages `view_player` selection

**Acceptance:**
- Connect to a running `play-server`, create a 4-seat game with one
  human + three heuristic AIs.
- Negotiation screen appears: hex board on the left, sociogram + court
  panel + tension meter on the right, intents listed at the bottom.
- Set stances toward other players (3 dropdowns).
- Declare an intent for one of your units (drag arrow on the map,
  released onto a target hex).
- Spend aid tokens via the aid panel.
- Type a chat draft (broadcast on commit).
- Press "Seal Intent" — intents lock for the turn.
- Heuristic AIs auto-advance; the screen transitions through the
  cosmetic REVEAL animation (Phase 2c builds the real animation; 2a
  uses a placeholder fade) and lands in the Orders screen (Phase 2b
  builds; 2a falls back to v0 `Main.tscn` order entry temporarily —
  this is the only place the new and old UIs touch).

**Cost:** ~1 week single-dev.

### 2b · Orders screen + drag-from-piece

Replaces the v0 OrderList button wall with map-gesture order entry.

**New files:**
- `scenes/council/CouncilOrders.tscn` + `.gd`
- `components/OrderArrow.gd` — Node2D that draws a Move/Support arrow
  on the hex board (tip color from player, tail style from order kind)
- Extensions to `HexBoard.gd` for drag-state tracking (mousedown on
  own unit → drag → mouseup on target tile or adjacent friendly unit)

**Order-entry mapping:**

| Gesture | Order |
|---|---|
| Click own unit then click own hex (or release on it) | `Hold` |
| Drag from own unit to adjacent hex | `Move(dest=target)` |
| Drag from own unit to a friendly unit at hex X (after that friendly's intended Move was published) | `SupportMove(target=u, dest=X)` |
| Drag from own unit to a friendly unit holding | `SupportHold(target=u)` |
| Right-click queued order | Cancel that order |

**Compatibility:** existing legal-order set in the view payload is
still consulted; the UI only enables gestures that the server says
are legal. No new HTTP calls.

**Acceptance:**
- Issue Move, SupportMove, SupportHold, Hold via gestures only — no
  button press needed except `Submit Orders`.
- Cancel a queued order via right-click.
- Submit orders → server resolves → screen transitions to 2c.

**Cost:** ~3–5 days.

### 2c · Resolution playback

Animates the resolution from `/history` snapshots — the "fun moment"
of the game.

**New files:**
- `scenes/council/CouncilResolution.tscn` + `.gd`
- `components/CombatBeat.gd` — flashbulb overlay drawn at a contested
  hex during a clash (small radial burst + dislodgement crater)
- `scripts/council/ResolutionTimeline.gd` — pure logic, takes two
  consecutive snapshots and produces a list of `(timestamp, event)`
  tuples (move-success, dislodgement, alliance-bonus, combat-reward,
  leverage-fire, betrayal). Used to drive the playback `Tween`.

**Animation pattern:**
1. Read previous + current snapshot from `/games/<id>/history`.
2. Build the timeline. Successful Moves animate as unit lerps along
   the hex line. Dislodgements pulse a CombatBeat at the contested
   hex. Alliance / combat / supporter rewards float a small wax-seal
   icon up from the rewarded player's color band. Leverage fires
   show a brief gold thread from leveraged player → defender.
3. Skip / fast-forward / slow-motion buttons (small, top-right).

**Acceptance:**
- Resolve a turn with at least one successful Move and one
  dislodgement.
- Watch the playback animate in 4–8 seconds total.
- Pause / step buttons work; "skip" jumps to end state immediately.

**Cost:** ~5–7 days. Most complex sub-phase due to animation.

### 2d · Bookends + flag-day swap

Three smaller screens plus the swap.

**New files:**
- `scenes/council/CouncilPairwise.tscn` + `.gd` — bilateral dossier:
  open from a click on a sociogram crest; shows leverage scales,
  press history with that player, betrayal log, recent supports
- `scenes/council/CouncilCoronation.tscn` + `.gd` — win screen: large
  crowned crest, score breakdown, détente vs. score-victory flag,
  "view replay" button
- `scenes/council/CouncilReplay.tscn` + `.gd` — replay viewer: scrub
  through `/history`, plays Resolution playback for any turn,
  links back to Pairwise dossier for any pair

**Flag-day swap:**
- `project.godot` `run/main_scene` changes from `scenes/Main.tscn` to
  `scenes/council/CouncilEntry.tscn` (which, by 2d, is the only entry
  point — the entry's "v0 mode" branch is removed).
- `scenes/Main.tscn`, `scripts/Main.gd`, and the press / aid / order
  panels in `scripts/HexMap.gd` are deleted. `GameClient.gd` and
  `SoundManager.gd` survive.
- `scripts/test_smoke.gd` is rewritten to assert the Council entry
  scene's children instead. `test_e2e.gd` stays as-is (still drives
  the play-server, doesn't care about the client UI).

**Cost:** ~3–5 days.

## 4. Architecture invariants (locked)

- **One source of truth for game state:** the play-server. The client
  reshapes view payloads but never invents state. (Inherits from
  `foedus-godot`'s existing `CLAUDE.md` invariant.)
- **Phase routing happens in `CouncilGame.gd`**, not inside individual
  screens. Each screen's `_ready` reads the view payload and renders;
  it does not poll for phase changes itself.
- **Drag-state for order entry lives in `HexBoard.gd`**, not in
  `CouncilOrders.gd`. The Orders screen subscribes to a
  `order_proposed(unit_id, order: Dictionary)` signal.
- **Resolution timeline is pure data.** `ResolutionTimeline.gd` returns
  events; `CouncilResolution.gd` renders them. Timeline is unit-testable
  with two synthetic snapshots.

## 5. Open questions

1. **Hex grid size** — Phase 1's `Tokens.HEX_R = 32` (from the design
   doc) versus the existing `HexMap.gd`'s adaptive sizing. Pick `32`
   and let HexBoard scale to fit; deferred map sizes ≥ ~12 hexes
   wide may need a smaller default. Revisit if 4-player maps look
   crowded.

2. **Sociogram layout** — 4 crests at the corners of a square, or in a
   diamond, or arranged by current scoreboard rank? Phase 2a will ship
   square-corners; revisit if relations are hard to scan.

3. **Aid spend UX** — drag the WaxEnvelope token from your aid
   inventory onto a sociogram arc, or click+select then "spend on X"?
   Drag is more theatrical; click-select is faster. Phase 2a ships
   click-select; promote to drag if playtesters complain.

4. **REVEAL animation duration** — 2 seconds feels right for "ceremony
   without delay"; tweak in 2c when the real animation is built.

5. **Coronation share / replay export** — design implies a "share this
   game" affordance (link out, screenshot). Defer; not on the v0
   playtest critical path.

## 6. Acceptance criteria (whole phase)

- A human can play a full 4-seat game (vs three heuristic AIs)
  end-to-end through the Council UI alone, without touching the v0
  `Main.tscn`.
- All Phase 1 primitives are still in their original `.gd` form
  (Phase 2 doesn't fork them — if a primitive needs a tweak, the
  change lands in `components/` and the demo scene is updated).
- `godot --headless --script res://scripts/test_phase1_primitives.gd`
  still passes.
- `godot --headless --script res://scripts/test_e2e.gd` (with a
  running play-server) still passes.
- Visual review (headless capture of each screen at 1280×800) for
  every new screen, attached to the corresponding sub-phase PR.
- Bundle 4 mechanics (stance, intent, aid, leverage, betrayals,
  combat reward) are all visibly engaged in the UI.

## 7. What's out of scope until Phase 3

- Theme `.tres` — components self-style.
- Audio: sound design / music — single ambient track from
  `SoundManager.gd` survives unchanged.
- Touch / mobile — desktop only.
- Lobby variants beyond "join by code".
- Settings panel polish (current Phase 1 demo has a Settings stub
  via the design's `CouncilSettings` mockup but it's not built yet).
- Pause overlay (no per-turn timer means no real pause primitive).
