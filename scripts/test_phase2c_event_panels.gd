extends SceneTree
##
## Tests for wire v3 event-channel ViewModel accessors:
## intent_revisions(), support_lapses(), done_clears(), and
## wire-version soft validation.
##
## Run: godot --headless --script res://scripts/test_phase2c_event_panels.gd
##

const ViewModel = preload("res://scripts/council/ViewModel.gd")
const Fixtures  = preload("res://tests/fixtures/view_payload_negotiation.gd")


func _initialize() -> void:
	var failures := 0
	print("--- Phase 2c event panels ---")

	failures += _test_empty_channels()
	failures += _test_support_lapses()
	failures += _test_intent_revisions_new_declaration()
	failures += _test_intent_revisions_modification()
	failures += _test_intent_revisions_retraction()
	failures += _test_done_clears()
	failures += _test_wire_version_present()

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


func _base_view() -> Dictionary:
	## Start from the negotiation fixture and inject wire v3 event fields.
	var v := Fixtures.negotiation_view()
	v["state"]["wire_version"] = 3
	v["state"]["intent_revisions"] = []
	v["state"]["support_lapses"] = []
	v["state"]["done_clears"] = []
	return v


func _test_empty_channels() -> int:
	var vm := ViewModel.new(_base_view())
	var f := 0
	f += _expect("intent_revisions empty", vm.intent_revisions().is_empty(),
		str(vm.intent_revisions()))
	f += _expect("support_lapses empty", vm.support_lapses().is_empty(),
		str(vm.support_lapses()))
	f += _expect("done_clears empty", vm.done_clears().is_empty(),
		str(vm.done_clears()))
	return f


func _test_support_lapses() -> int:
	var v := _base_view()
	v["state"]["support_lapses"] = [
		{"turn": 3, "supporter": 0, "target": 2, "reason": "geometry_break"},
		{"turn": 3, "supporter": 1, "target": 0, "reason": "pin_mismatch"},
	]
	var vm := ViewModel.new(v)
	var lapses := vm.support_lapses()
	var f := 0
	f += _expect("support_lapses count", lapses.size() == 2, str(lapses.size()))
	f += _expect("lapse supporter field", int(lapses[0].get("supporter", -1)) == 0,
		str(lapses[0]))
	f += _expect("lapse target field", int(lapses[0].get("target", -1)) == 2,
		str(lapses[0]))
	f += _expect("lapse reason field", lapses[0].get("reason") == "geometry_break",
		str(lapses[0].get("reason")))
	f += _expect("lapse second reason", lapses[1].get("reason") == "pin_mismatch",
		str(lapses[1].get("reason")))
	return f


func _test_intent_revisions_new_declaration() -> int:
	var v := _base_view()
	v["state"]["intent_revisions"] = [
		{
			"turn": 3,
			"player": 1,
			"intent": {
				"unit_id": 1,
				"declared_order": {"type": "Move", "dest": 4},
				"visible_to": null,
			},
			"previous": null,
		},
	]
	var vm := ViewModel.new(v)
	var revisions := vm.intent_revisions()
	var f := 0
	f += _expect("intent_revisions count", revisions.size() == 1, str(revisions.size()))
	var rev := revisions[0]
	f += _expect("revision player", int(rev.get("player", -1)) == 1, str(rev))
	f += _expect("revision intent not null", rev.get("intent") != null, str(rev))
	f += _expect("revision previous is null", rev.get("previous") == null, str(rev))
	var intent = rev["intent"]
	f += _expect("revision unit_id", int(intent.get("unit_id", -1)) == 1)
	f += _expect("revision declared_order type",
		intent.get("declared_order", {}).get("type") == "Move",
		str(intent.get("declared_order")))
	return f


func _test_intent_revisions_modification() -> int:
	var v := _base_view()
	v["state"]["intent_revisions"] = [
		{
			"turn": 3,
			"player": 2,
			"intent": {
				"unit_id": 2,
				"declared_order": {"type": "Hold"},
				"visible_to": null,
			},
			"previous": {
				"unit_id": 2,
				"declared_order": {"type": "Move", "dest": 3},
				"visible_to": null,
			},
		},
	]
	var vm := ViewModel.new(v)
	var revisions := vm.intent_revisions()
	var f := 0
	f += _expect("revision modification count", revisions.size() == 1)
	var rev := revisions[0]
	f += _expect("modification both non-null",
		rev.get("intent") != null and rev.get("previous") != null, str(rev))
	f += _expect("modification player", int(rev.get("player", -1)) == 2)
	f += _expect("modification previous type",
		rev["previous"].get("declared_order", {}).get("type") == "Move",
		str(rev["previous"]))
	f += _expect("modification intent type",
		rev["intent"].get("declared_order", {}).get("type") == "Hold",
		str(rev["intent"]))
	return f


func _test_intent_revisions_retraction() -> int:
	var v := _base_view()
	v["state"]["intent_revisions"] = [
		{
			"turn": 3,
			"player": 3,
			"intent": null,
			"previous": {
				"unit_id": 5,
				"declared_order": {"type": "Support", "target_unit": 1},
				"visible_to": null,
			},
		},
	]
	var vm := ViewModel.new(v)
	var revisions := vm.intent_revisions()
	var f := 0
	f += _expect("retraction count", revisions.size() == 1)
	var rev := revisions[0]
	f += _expect("retraction intent is null", rev.get("intent") == null, str(rev))
	f += _expect("retraction previous not null", rev.get("previous") != null)
	f += _expect("retraction previous unit_id",
		int(rev["previous"].get("unit_id", -1)) == 5)
	return f


func _test_done_clears() -> int:
	var v := _base_view()
	v["state"]["done_clears"] = [
		{"turn": 3, "player": 0, "source_player": 1, "source_unit": 1},
		{"turn": 3, "player": 2, "source_player": 1, "source_unit": 1},
	]
	var vm := ViewModel.new(v)
	var clears := vm.done_clears()
	var f := 0
	f += _expect("done_clears count", clears.size() == 2, str(clears.size()))
	f += _expect("clear player", int(clears[0].get("player", -1)) == 0, str(clears[0]))
	f += _expect("clear source_player", int(clears[0].get("source_player", -1)) == 1)
	f += _expect("clear source_unit", int(clears[0].get("source_unit", -1)) == 1)
	f += _expect("clear second player", int(clears[1].get("player", -1)) == 2)
	return f


func _test_wire_version_present() -> int:
	## Payload with correct wire_version=3 — accessor should return the event arrays.
	var v := _base_view()
	v["state"]["support_lapses"] = [
		{"turn": 3, "supporter": 7, "target": 8, "reason": "target_destroyed"},
	]
	var vm := ViewModel.new(v)
	var f := 0
	f += _expect("wire_version=3 lapses accessible",
		vm.support_lapses().size() == 1, str(vm.support_lapses().size()))
	## Missing wire_version — accessor still returns data (soft warning only).
	var v2 := Fixtures.negotiation_view()
	v2["state"]["support_lapses"] = [
		{"turn": 1, "supporter": 0, "target": 1, "reason": "geometry_break"},
	]
	var vm2 := ViewModel.new(v2)
	f += _expect("missing wire_version still returns data",
		vm2.support_lapses().size() == 1, str(vm2.support_lapses().size()))
	return f
