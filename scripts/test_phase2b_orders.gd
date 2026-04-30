extends SceneTree
##
## Phase 2b smoke — loads OrderArrow / OrderController / OrdersPanel /
## CouncilOrders, instantiates them, drives OrderController through
## the propose / interpret / serialize loop with a synthetic ViewModel.
##

func _initialize() -> void:
	var failures := 0
	print("--- Phase 2b ---")

	# Component scripts load + instantiate.
	for path in [
		"res://components/OrderArrow.gd",
		"res://components/OrdersPanel.gd",
		"res://scripts/council/OrderController.gd",
		"res://scenes/council/CouncilOrders.gd",
	]:
		var s := load(path) as Script
		if s == null:
			push_error("FAIL: load " + path); failures += 1; continue
		var inst = s.new()
		if inst == null:
			push_error("FAIL: instantiate " + path); failures += 1; continue
		if inst is Node:
			inst.free()
		print("ok: ", path)

	# CouncilOrders.tscn instantiates.
	var packed := load("res://scenes/council/CouncilOrders.tscn") as PackedScene
	if packed == null:
		push_error("FAIL: CouncilOrders.tscn"); failures += 1
	else:
		var inst = packed.instantiate()
		inst.queue_free()
		print("ok: CouncilOrders.tscn")

	# Drive an OrderController through propose/serialize.
	var Ctrl = load("res://scripts/council/OrderController.gd")
	var ctrl = Ctrl.new()
	failures += _expect("ctrl starts empty", ctrl.count() == 0)
	ctrl.propose_order(7, {"type": "Move", "dest": 12})
	failures += _expect("count after propose", ctrl.count() == 1)
	failures += _expect("has_order_for(7)", ctrl.has_order_for(7))
	failures += _expect("order_for(7).type",
		String(ctrl.order_for(7).get("type", "")) == "Move")
	ctrl.remove_order(7)
	failures += _expect("count after remove", ctrl.count() == 0)
	# Serialize.
	ctrl.propose_order(2, {"type": "Hold"})
	ctrl.propose_order(5, {"type": "Move", "dest": 9})
	var payload: Dictionary = ctrl.to_orders_payload()
	failures += _expect("payload has 2 keys", payload.size() == 2)
	failures += _expect("payload key is str(uid)", payload.has("2") and payload.has("5"))

	# interpret_drag with the synthetic fixture.
	var VM = load("res://scripts/council/ViewModel.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")
	var vm = VM.new(Fix.negotiation_view())
	# Fixture: my unit 0 is at node 0 (home). legal_orders for unit 0
	# is just Hold per the fixture.
	# Drag unit 0 to node 0 (its own location) → Hold.
	var ord_hold: Dictionary = Ctrl.interpret_drag(vm, 0, 0)
	failures += _expect("interpret_drag self → Hold",
		String(ord_hold.get("type", "")) == "Hold", str(ord_hold))
	# Drag unit 2 to node 4 → Move{dest=4} (in fixture's legal set).
	var ord_move: Dictionary = Ctrl.interpret_drag(vm, 2, 4)
	failures += _expect("interpret_drag adjacent → Move",
		String(ord_move.get("type", "")) == "Move"
		and int(ord_move.get("dest", -1)) == 4, str(ord_move))
	# Drag to non-legal target (unit 0 to non-adjacent node 5) → empty.
	var ord_none: Dictionary = Ctrl.interpret_drag(vm, 0, 5)
	failures += _expect("interpret_drag illegal → empty",
		ord_none.is_empty(), str(ord_none))

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
