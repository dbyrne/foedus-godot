extends SceneTree
##
## Phase 2c smoke — ResolutionTimeline event diff + CombatBeat /
## CouncilResolution structural load.
##

func _initialize() -> void:
	var failures := 0
	print("--- Phase 2c ---")

	for path in [
		"res://scripts/council/ResolutionTimeline.gd",
		"res://components/CombatBeat.gd",
		"res://scenes/council/CouncilResolution.gd",
	]:
		var s := load(path) as Script
		if s == null:
			push_error("FAIL: load " + path); failures += 1; continue
		# ResolutionTimeline is RefCounted with no _init args; CombatBeat
		# is Node2D; CouncilResolution is Control. Skip instantiation of
		# the latter two here — they need scene context.
		print("ok: ", path)

	# CouncilResolution.tscn instantiates.
	var packed := load("res://scenes/council/CouncilResolution.tscn") as PackedScene
	if packed == null:
		push_error("FAIL: CouncilResolution.tscn"); failures += 1
	else:
		var inst = packed.instantiate()
		inst.queue_free()
		print("ok: CouncilResolution.tscn")

	# Timeline: synthesize prev + curr snapshots and verify event detection.
	var TL = load("res://scripts/council/ResolutionTimeline.gd")
	failures += _test_move_detection(TL)
	failures += _test_dislodge_detection(TL)
	failures += _test_leverage_detection(TL)
	failures += _test_score_detection(TL)
	failures += _test_ownership_detection(TL)
	failures += _test_no_change_no_events(TL)

	if failures == 0:
		print("--- ALL OK ---")
		quit(0)
	else:
		print("--- %d FAILURES ---" % failures)
		quit(1)


func _expect(name: String, cond: bool, detail: String = "") -> int:
	if cond:
		print("ok: ", name)
		return 0
	push_error("FAIL: %s — %s" % [name, detail])
	return 1


func _state(units: Array, ownership: Dictionary = {},
		aid_given: Dictionary = {}, scores: Dictionary = {}) -> Dictionary:
	var u_dict := {}
	for u in units:
		u_dict[str(u.id)] = u
	return {
		"state": {
			"units": u_dict,
			"ownership": ownership,
			"aid_given": aid_given,
			"scores": scores,
		}
	}


func _test_move_detection(TL) -> int:
	# Unit 0 moved from node 1 to node 2.
	var prev := _state([{"id": 0, "owner": 0, "location": 1}])
	var curr := _state([{"id": 0, "owner": 0, "location": 2}])
	var events: Array = TL.from_snapshots(prev, curr)
	var moves := events.filter(func(e): return e.kind == "move")
	var f := _expect("one move event", moves.size() == 1, str(moves))
	if moves.size() == 1:
		f += _expect("move from_node",
			int(moves[0].from_node) == 1, str(moves[0]))
		f += _expect("move to_node",
			int(moves[0].to_node) == 2)
		f += _expect("move player_id",
			int(moves[0].player_id) == 0)
	return f


func _test_dislodge_detection(TL) -> int:
	# Unit 5 vanished between snapshots.
	var prev := _state([
		{"id": 0, "owner": 0, "location": 1},
		{"id": 5, "owner": 1, "location": 7},
	])
	var curr := _state([{"id": 0, "owner": 0, "location": 1}])
	var events: Array = TL.from_snapshots(prev, curr)
	var dislodges := events.filter(func(e): return e.kind == "dislodge")
	var f := _expect("one dislodge event", dislodges.size() == 1)
	if dislodges.size() == 1:
		f += _expect("dislodged unit_id", int(dislodges[0].unit_id) == 5)
		f += _expect("dislodged at_node", int(dislodges[0].at_node) == 7)
	return f


func _test_leverage_detection(TL) -> int:
	# aid_given[(0,1)] grew from 2 to 5 → delta 3 leverage event.
	var prev := _state([], {}, {"0,1": 2})
	var curr := _state([], {}, {"0,1": 5})
	var events: Array = TL.from_snapshots(prev, curr)
	var levs := events.filter(func(e): return e.kind == "leverage")
	var f := _expect("one leverage event", levs.size() == 1, str(levs))
	if levs.size() == 1:
		f += _expect("leverage delta", int(levs[0].delta) == 3)
		f += _expect("leverage from", int(levs[0].from_player) == 0)
		f += _expect("leverage to", int(levs[0].to_player) == 1)
	return f


func _test_score_detection(TL) -> int:
	var prev := _state([], {}, {}, {"0": 10.0, "1": 5.0})
	var curr := _state([], {}, {}, {"0": 14.0, "1": 5.0})
	var events: Array = TL.from_snapshots(prev, curr)
	var scores := events.filter(func(e): return e.kind == "score")
	var f := _expect("one score event", scores.size() == 1, str(scores))
	if scores.size() == 1:
		f += _expect("score player", int(scores[0].player_id) == 0)
		f += _expect("score delta", abs(scores[0].delta - 4.0) < 0.01)
	return f


func _test_ownership_detection(TL) -> int:
	var prev := _state([], {"3": 0})
	var curr := _state([], {"3": 1})
	var events: Array = TL.from_snapshots(prev, curr)
	var owns := events.filter(func(e): return e.kind == "ownership")
	var f := _expect("one ownership event", owns.size() == 1)
	if owns.size() == 1:
		f += _expect("ownership node_id", int(owns[0].node_id) == 3)
	return f


func _test_no_change_no_events(TL) -> int:
	var snap := _state([{"id": 0, "owner": 0, "location": 1}],
		{"1": 0}, {"0,1": 2}, {"0": 5.0})
	return _expect("identical snapshots → 0 events",
		TL.from_snapshots(snap, snap).is_empty())
