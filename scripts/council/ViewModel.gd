extends RefCounted
class_name ViewModel
##
## Typed accessors over the play-server's /view/<player> JSON payload.
##
## Wraps a single view dict and exposes named methods so screens don't
## reach into raw dictionary keys. Pure logic — no Godot scene
## dependency, headlessly testable.
##
## Wire shape mirrors `Session._build_view` in foedus's
## game_server/session.py as of 2026-04-29 (see
## tests/fixtures/view_payload_negotiation.gd).
##
## NOTE on phase routing: foedus's engine never actually transitions
## `state.phase` to `Phase.ORDERS` — `finalize_round` always resets to
## `NEGOTIATION` (see foedus's
## docs/superpowers/specs/2026-04-28-press-driver-design.md). The
## driver sequences the two UI phases. We compute the equivalent of
## `is_chat_phase_complete(state)` client-side from
## `state.chat_done` ⊇ alive players. (The /chat endpoint's response
## carries that bool but the /view payload does NOT include it —
## confirmed empirically against a live play-server.)
##   - `chat_phase_complete()` (computed): every alive player signaled
##     chat-done. The press round is locked; clients should be drafting
##     orders.
##   - `submitted` (in view): I've submitted my orders this turn.
## Plus `is_terminal` for the resolved end-state.
##
## Phase 2 spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const PHASE_NEGOTIATION := "negotiation"
const PHASE_ORDERS      := "orders"
const PHASE_RESOLVED    := "resolved"

var _raw: Dictionary
var _state: Dictionary  # raw["state"] cached for hot accessors
var _map: Dictionary    # raw["state"]["map"] cached

func _init(view_payload: Dictionary = {}) -> void:
	_raw = view_payload
	_state = _raw.get("state", {})
	_map = _state.get("map", {})


# --- Top-level identifiers ----------------------------------------------

func game_id() -> String:
	return String(_raw.get("game_id", ""))

func turn() -> int:
	return int(_raw.get("turn", 0))

func max_turns() -> int:
	return int(_raw.get("max_turns", 0))

func my_player_id() -> int:
	return int(_raw.get("you", -1))

func num_players() -> int:
	return int(_state.get("config", {}).get("num_players", 0))


# --- Phase routing ------------------------------------------------------

func phase() -> String:
	## Computes the equivalent of foedus.press.is_chat_phase_complete
	## client-side because the view payload doesn't expose that bool
	## directly (it's only returned from /chat responses).
	if is_terminal():
		return PHASE_RESOLVED
	if bool(_raw.get("submitted", false)):
		return PHASE_ORDERS
	if chat_phase_complete():
		return PHASE_ORDERS
	return PHASE_NEGOTIATION


func chat_phase_complete() -> bool:
	## True iff every alive player has signaled chat-done. Mirrors
	## foedus.press.is_chat_phase_complete(state). Normalizes to int
	## set membership because JSON-parsed integers may arrive as floats.
	var chat_done_raw: Array = _state.get("chat_done", [])
	var eliminated_raw: Array = _state.get("eliminated", [])
	var chat_done: Dictionary = {}
	for x in chat_done_raw:
		chat_done[int(x)] = true
	var eliminated: Dictionary = {}
	for x in eliminated_raw:
		eliminated[int(x)] = true
	var n := num_players()
	if n <= 0:
		return false
	for pid in n:
		if eliminated.has(pid):
			continue
		if not chat_done.has(pid):
			return false
	return true


func awaiting_humans() -> Array:
	return _raw.get("awaiting_humans", [])

func has_submitted() -> bool:
	return bool(_raw.get("submitted", false))


# --- Game end -----------------------------------------------------------

func is_terminal() -> bool:
	return bool(_raw.get("is_terminal", false))

func detente_reached() -> bool:
	return bool(_raw.get("detente_reached", false))

func winners() -> Array:
	return _raw.get("winners", [])

func winner() -> int:
	var w = _raw.get("winner")
	return -1 if w == null else int(w)

func eliminated() -> Array:
	return _raw.get("eliminated", [])


# --- Tiles --------------------------------------------------------------
#
# Tiles are stitched together from several map and state dicts. Each
# tile dict returned has the shape:
#   {
#     "node_id": int,
#     "q": int, "r": int,
#     "node_type": "PLAIN"|"FOREST"|"MOUNTAIN"|"WATER"|"SUPPLY"|"HOME",
#     "supply_value": int,    # 1 by default; 2 for high-value
#     "home_player": int|null,
#     "owner": int|null,
#     "unit": {"id", "owner", "label"} | null,
#   }

func tiles() -> Array:
	var out := []
	for node_id_str in _map.get("coords", {}).keys():
		var node_id := int(node_id_str)
		out.append(tile_for_node(node_id))
	return out


func tile_for_node(node_id: int) -> Dictionary:
	var node_str := str(node_id)
	var coord = _map.get("coords", {}).get(node_str, [0, 0])
	var nt: String = _map.get("node_types", {}).get(node_str, "PLAIN")
	var sv: int = int(_map.get("supply_values", {}).get(node_str, 1))
	var hp = _map.get("home_assignments", {}).get(node_str)
	var ow = _state.get("ownership", {}).get(node_str)
	var unit: Variant = null
	for uid_str in _state.get("units", {}).keys():
		var u: Dictionary = _state["units"][uid_str]
		if int(u.get("location", -1)) == node_id:
			# CouncilHex (Phase 1) consumes {"player", "label"} for the
			# unit dict. Stay consistent with that shape so HexBoard can
			# pass the unit through verbatim.
			unit = {
				"id": int(u["id"]),
				"player": int(u["owner"]),
				"label": _label_for_unit(int(u["id"])),
			}
			break
	return {
		"node_id": node_id,
		"q": int(coord[0]),
		"r": int(coord[1]),
		"node_type": nt,
		"supply_value": sv,
		"home_player": null if hp == null else int(hp),
		"owner": null if ow == null else int(ow),
		"unit": unit,
	}


func tile_at_coord(q: int, r: int) -> Dictionary:
	for node_id_str in _map.get("coords", {}).keys():
		var coord = _map["coords"][node_id_str]
		if int(coord[0]) == q and int(coord[1]) == r:
			return tile_for_node(int(node_id_str))
	return {}


# --- Units --------------------------------------------------------------

func my_units() -> Array:
	return _raw.get("your_units", [])


func units_owned_by(pid: int) -> Array:
	## All units (any player) currently owned by `pid`. Returns dicts
	## with shape {"id", "owner", "location"} — same shape as the wire
	## state.units entries.
	var out: Array = []
	for uid_str in _state.get("units", {}).keys():
		var u: Dictionary = _state["units"][uid_str]
		if int(u.get("owner", -1)) == pid:
			out.append(u)
	return out


func unit_by_id(uid: int) -> Dictionary:
	var u: Variant = _state.get("units", {}).get(str(uid))
	if u == null:
		return {}
	return u


func legal_orders_for(uid: int) -> Array:
	return _raw.get("legal_orders", {}).get(str(uid), [])


# --- Scoring ------------------------------------------------------------

func score(pid: int) -> float:
	var s: Variant = _state.get("scores", {}).get(str(pid))
	return 0.0 if s == null else float(s)


# --- Bundle 4: aid + leverage + stance ---------------------------------

func aid_tokens(pid: int) -> int:
	## Per-player aid balance. State payload exposes all players'
	## tokens; the public ledger means this is non-secret.
	return int(_state.get("aid_tokens", {}).get(str(pid), 0))


func aid_given(from_pid: int, to_pid: int) -> int:
	## Cumulative aid spent by `from_pid` on `to_pid`. Wire encodes
	## tuple keys as flat "A,B" strings.
	var key := "%d,%d" % [from_pid, to_pid]
	return int(_state.get("aid_given", {}).get(key, 0))


func leverage(from_pid: int, to_pid: int) -> int:
	## Signed: aid_given[A→B] - aid_given[B→A]. Positive means A has
	## leverage on B.
	return aid_given(from_pid, to_pid) - aid_given(to_pid, from_pid)


func stance(from_pid: int, to_pid: int) -> String:
	## Stance is from the LAST locked press round (last_press). Self-
	## stance returns "neutral" as a safe default (the press protocol
	## doesn't store it).
	if from_pid == to_pid:
		return "neutral"
	var lp = _raw.get("last_press", {}).get(str(from_pid))
	if lp == null:
		return "neutral"
	var s: Variant = lp.get("stance", {}).get(str(to_pid))
	return "neutral" if s == null else String(s)


func detente_streak() -> int:
	return int(_state.get("mutual_ally_streak", 0))


# --- Press history (committed) -----------------------------------------

func declared_intents() -> Array:
	## All players' declared intents from the LAST locked press round.
	## Returns flattened list with the publishing player_id attached.
	var out := []
	for pid_str in _raw.get("last_press", {}).keys():
		var lp = _raw["last_press"][pid_str]
		for i in lp.get("intents", []):
			var intent = i.duplicate()
			intent["player_id"] = int(pid_str)
			out.append(intent)
	return out


func your_betrayals() -> Array:
	return _raw.get("your_betrayals", [])


# --- Wire v3 event channels -------------------------------------------

func intent_revisions() -> Array:
	## IntentRevised events for the current turn. Each entry: {turn, player,
	## intent: Intent|null, previous: Intent|null, visible_to: list|null}.
	## intent=null means a retraction.
	return _state.get("intent_revisions", [])


func support_lapses() -> Array:
	## SupportLapsed events for the current turn. Each entry: {turn,
	## supporter: unit_id, target: unit_id, reason: String}.
	return _state.get("support_lapses", [])


func done_clears() -> Array:
	## DoneCleared events for the current turn. Each entry: {turn, player,
	## source_player, source_unit}.
	return _state.get("done_clears", [])


# --- Replay metadata ----------------------------------------------------

func is_replay() -> bool:
	return bool(_raw.get("is_replay", false))

func current_turn() -> int:
	return int(_raw.get("current_turn", turn()))

func snapshot_count() -> int:
	return int(_raw.get("snapshot_count", 0))


# --- Internals ----------------------------------------------------------

func _label_for_unit(uid: int) -> String:
	## Stable per-unit label "A"/"B"/... based on creation order
	## within the owning player's units. Server doesn't carry a label
	## field so we synthesize one here.
	var u: Dictionary = unit_by_id(uid)
	if u.is_empty():
		return "?"
	var owner := int(u.get("owner", -1))
	var owner_units := []
	for uid_str in _state.get("units", {}).keys():
		var x: Dictionary = _state["units"][uid_str]
		if int(x.get("owner", -1)) == owner:
			owner_units.append(int(x["id"]))
	owner_units.sort()
	var idx := owner_units.find(uid)
	if idx < 0:
		return "?"
	# A, B, C... up to Z then wrap (unlikely to need >26)
	return char(int("A".unicode_at(0)) + (idx % 26))
