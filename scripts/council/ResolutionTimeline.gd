extends RefCounted
class_name ResolutionTimeline
##
## Pure-data event timeline derived from two consecutive snapshots.
##
## Foedus's resolution log isn't transmitted (the wire format omits it
## by design — see foedus/foedus/remote/wire.py serialize_state). So we
## reconstruct the turn's events by diffing snapshot N against N+1.
##
## Events surfaced (in deterministic order suitable for animation):
##   {"kind": "move",        "unit_id", "from_node", "to_node", "player_id"}
##   {"kind": "dislodge",    "unit_id", "at_node", "player_id"}
##   {"kind": "ownership",   "node_id", "from_player", "to_player"}
##   {"kind": "leverage",    "from_player", "to_player", "delta"}
##   {"kind": "score",       "player_id", "delta"}
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md (Phase 2c)
##


static func from_snapshots(prev_view: Dictionary,
		curr_view: Dictionary) -> Array:
	## Build the event list.
	var events: Array = []
	var prev_state: Dictionary = prev_view.get("state", {})
	var curr_state: Dictionary = curr_view.get("state", {})

	events += _move_and_dislodge_events(prev_state, curr_state)
	events += _ownership_events(prev_state, curr_state)
	events += _leverage_events(prev_state, curr_state)
	events += _score_events(prev_state, curr_state)
	return events


static func _units_by_id(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for uid_str in state.get("units", {}).keys():
		var u: Dictionary = state["units"][uid_str]
		out[int(u["id"])] = u
	return out


static func _move_and_dislodge_events(prev: Dictionary,
		curr: Dictionary) -> Array:
	var events: Array = []
	var prev_units := _units_by_id(prev)
	var curr_units := _units_by_id(curr)
	for uid in prev_units.keys():
		var pu: Dictionary = prev_units[uid]
		var prev_loc := int(pu.get("location", -1))
		var owner := int(pu.get("owner", -1))
		if curr_units.has(uid):
			var cu: Dictionary = curr_units[uid]
			var curr_loc := int(cu.get("location", -1))
			if curr_loc != prev_loc:
				events.append({
					"kind": "move",
					"unit_id": int(uid),
					"from_node": prev_loc,
					"to_node": curr_loc,
					"player_id": owner,
				})
		else:
			# Unit gone in curr → dislodged (or eliminated). The
			# location it died at is its prev_loc.
			events.append({
				"kind": "dislodge",
				"unit_id": int(uid),
				"at_node": prev_loc,
				"player_id": owner,
			})
	return events


static func _ownership_events(prev: Dictionary,
		curr: Dictionary) -> Array:
	var events: Array = []
	var prev_own: Dictionary = prev.get("ownership", {})
	var curr_own: Dictionary = curr.get("ownership", {})
	# Iterate over the union of keys.
	var all_keys := {}
	for k in prev_own.keys(): all_keys[k] = true
	for k in curr_own.keys(): all_keys[k] = true
	for k in all_keys.keys():
		var pv = prev_own.get(k)
		var cv = curr_own.get(k)
		if pv != cv:
			events.append({
				"kind": "ownership",
				"node_id": int(k),
				"from_player": pv if pv != null else -1,
				"to_player": cv if cv != null else -1,
			})
	return events


static func _leverage_events(prev: Dictionary,
		curr: Dictionary) -> Array:
	## A leverage event surfaces whenever an aid_given[(A,B)] entry
	## increased — meaning A spent aid on B this turn.
	var events: Array = []
	var prev_ag: Dictionary = prev.get("aid_given", {})
	var curr_ag: Dictionary = curr.get("aid_given", {})
	for k in curr_ag.keys():
		var prev_v: int = int(prev_ag.get(k, 0))
		var curr_v: int = int(curr_ag[k])
		if curr_v > prev_v:
			var parts: PackedStringArray = String(k).split(",")
			if parts.size() == 2:
				events.append({
					"kind": "leverage",
					"from_player": int(parts[0]),
					"to_player": int(parts[1]),
					"delta": curr_v - prev_v,
				})
	return events


static func _score_events(prev: Dictionary, curr: Dictionary) -> Array:
	## A score event for each player whose total moved this turn.
	var events: Array = []
	var prev_scores: Dictionary = prev.get("scores", {})
	var curr_scores: Dictionary = curr.get("scores", {})
	for k in curr_scores.keys():
		var prev_v: float = float(prev_scores.get(k, 0.0))
		var curr_v: float = float(curr_scores[k])
		if abs(curr_v - prev_v) > 0.001:
			events.append({
				"kind": "score",
				"player_id": int(k),
				"delta": curr_v - prev_v,
			})
	return events
