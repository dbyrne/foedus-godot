# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`README.md` covers the v0 setup and headless test invocations; this file covers the architecture invariants and the layout conventions.

## Commands

```sh
# Smoke (offline, ~1s) — loads scripts + main scene, asserts node tree
godot --headless --script res://scripts/test_smoke.gd

# E2E (online, ~3s) — needs a play-server in another terminal
foedus play-server start --port 8090
godot --headless --script res://scripts/test_e2e.gd
```

To run the GUI, open `project.godot` in Godot 4.3+ and press **F5**. The play-server is a separate Python process — start it before connecting.

## Architecture invariants

**The Godot client knows zero game rules.** It renders state and posts orders to `foedus play-server` over HTTP. Replacing this client with a web SPA, terminal UI, or anything else only requires speaking the same JSON wire protocol. **Don't reimplement order legality, fog filtering, or resolution here** — call the server. If something seems missing from the server response, fix the server, not the client.

**One HTTPRequest per call, freed on completion.** `scripts/GameClient.gd` builds a fresh `HTTPRequest` node for each request and `queue_free()`s it in the completion callback. This sidesteps Godot's "one request per HTTPRequest at a time" constraint and avoids manual state machines for in-flight requests. Keep the pattern when adding new endpoints.

**Endpoints mirror `foedus.game_server` exactly.** The convenience methods on `GameClient` (`healthz`, `list_games`, `create_game`, `view`, `submit_orders`, `advance`, `delete_game`, `history`, `history_view`) are named after the REST endpoints they hit. When the server adds an endpoint, add a same-named wrapper here.

**Signals over callbacks.** `GameClient` emits `response(endpoint, data)` and `failure(endpoint, message)` rather than per-call callbacks. Subscribers dispatch on `endpoint`. This keeps the client class small and lets `Main.gd` route everything through one signal pair.

## Layout

- `project.godot` — Godot 4 config, points to `scenes/Main.tscn` as the run scene
- `scenes/Main.tscn` — root scene with status, controls, hex map, scoreboard, order list, game-over banner
- `scripts/GameClient.gd` — HTTP wrapper around the play-server REST API (signal-based)
- `scripts/Main.gd` — UI controller: connect / create-game / advance / view / order entry
- `scripts/HexMap.gd` — hex map rendering and click → unit-selection / order-shortcut handling
- `scripts/SoundManager.gd` — audio bus (lazy-init)
- `scripts/test_smoke.gd` — offline smoke test (scene + node-tree)
- `scripts/test_e2e.gd` — online integration test (drives a real play-server)
- `themes/main_theme.tres` — single global theme

## Order-entry UX (in `Main.gd`)

Two paths to issue an order, both writing into the same `pending_orders` dict:

1. **Click shortcuts on the hex map**:
   - Click your own unit → selects it (refreshes the OrderList panel with every legal order).
   - Click own hex (selected unit's hex) → queues `Hold`.
   - Click adjacent hex → queues `Move`.
2. **OrderList panel**: every legal order (including all `SupportHold` / `SupportMove` permutations) appears as a button. Use this for anything beyond Hold/Move.

Unspecified units default to `Hold` on submit. Don't add server round-trips for legality checks — the play-server returns legal orders in the `view` payload.

## When `README.md` and the code disagree

`README.md` is written from a status perspective and lags actual progress. If the code has functionality the README says is "not yet built" (e.g., the hex map renderer, click-based order entry), the code is the source of truth — update the README rather than the other way around.

## Renderer

`gl_compatibility` everywhere (config + mobile fallback). Don't switch to Forward+/Mobile renderers without checking against the lowest-end target machine — this client is meant to run on hardware where Godot's GL3 path is the safe choice.
