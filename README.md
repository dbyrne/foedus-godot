# foedus-godot

Godot 4 frontend for [foedus](https://github.com/dbyrne/foedus) local play —
both human and agent.

The Python `foedus` repo owns the rules. This repo is a thin client that
talks to a running `foedus play-server` over HTTP. Same wire boundary as
the agent protocol, same reasoning: one source of truth for game logic.

## Status

**v0 — text-based bootstrap.** Connects to the play-server, can create a
demo game (1 HeuristicAgent vs 3 RandomAgents), step turns or auto-advance,
and display the per-player view as text. Validates the wire protocol from
Godot end-to-end.

What's not yet built (in roughly this order):
- Hex map renderer (TileMap or custom-drawn)
- Click-based order entry (Move, Support)
- Game-creation UI (pick seats: human / agent / remote)
- Replay / spectator view
- Game-over screen

## Run

You'll need:
- Godot 4.3+ ([download](https://godotengine.org/download))
- A running foedus play-server:
  ```sh
  pip install "foedus[remote] @ git+https://github.com/dbyrne/foedus"
  foedus play-server start --port 8090
  ```

Then open `project.godot` in Godot, hit **Run** (F5). The first scene
asks you to connect to `http://127.0.0.1:8090/healthz`, then exposes
buttons to create + step a demo game.

## Architecture

```
┌──────────────┐  HTTP   ┌────────────────────────┐
│  Godot UI    │ ──────> │ foedus play-server     │
│ (this repo)  │ <────── │   - GameSession owns   │
└──────────────┘         │     state + agents     │
                         │   - human seats accept │
                         │     orders via /orders │
                         │   - agents (in-process │
                         │     or RemoteAgent)    │
                         │     supply orders on   │
                         │     advance            │
                         └────────────────────────┘
```

The Godot client doesn't know game rules. It renders state and posts
orders. Replacing the Godot UI with a web SPA, terminal UI, or anything
else only requires speaking the same HTTP protocol.

## Project layout

```
project.godot                 Godot 4 config + main scene reference
scenes/Main.tscn              v0 root scene (text controls)
scripts/GameClient.gd         HTTPRequest-based client wrapping the
                              play-server REST API
scripts/Main.gd               connect/create/advance/view orchestration
scripts/test_smoke.gd         offline: load scene + scripts, verify nodes
scripts/test_e2e.gd           online:  drives a real play-server through
                              healthz → /games → advance(auto)
```

## Tests

Three headless tests, all runnable via the Godot CLI.

**Smoke (offline, ~1s):** loads scripts and the main scene, verifies the
expected child nodes exist.
```sh
godot --headless --script res://scripts/test_smoke.gd
```

**Phase 1 primitives (offline, ~2s):** loads + instantiates every War
Council component (`components/*.gd`) and verifies the Tokens autoload
constants. Run after touching anything in `components/`.
```sh
godot --headless --script res://scripts/test_phase1_primitives.gd
```

**E2E (online, ~3s):** start a play-server in another terminal, then run
the script; it walks healthz → create demo game → auto-advance.
```sh
# Terminal 1
foedus play-server start --port 8090
# Terminal 2
godot --headless --script res://scripts/test_e2e.gd
```

## UI rebuild — visual primitives (Phase 1)

The current `scenes/Main.tscn` is the v0 game UI. A "War Council"
visual rebuild is in progress; see `docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md`.

Phase 1 ships **only the primitives + theme tokens** (no game-screen
changes). To inspect the components visually, open the demo scene in
the editor and run it (F6 with the scene focused):

```
scenes/Phase1Demo.tscn
```

Phase 1 deliverables on `main`:

- `scripts/Tokens.gd` — autoload with palette, font paths, hex math.
- `fonts/` — bundled Playfair Display, Cormorant Garamond, IBM Plex
  Sans, JetBrains Mono (variable; OFL-1.1).
- `components/` — nine `.gd` primitives (`CouncilShell`, `Crest`,
  `UnitPiece`, `CouncilHex`, `BrassPlate`, `TensionMeter`,
  `WaxEnvelope`, `ScalesOfLeverage`, `Throne`).

## License

MIT — see [LICENSE](LICENSE).
