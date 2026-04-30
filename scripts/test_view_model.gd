extends SceneTree
##
## Headless test for ViewModel — typed accessors over the play-server's
## /view/<player> payload.
##
## Run: godot --headless --script res://scripts/test_view_model.gd
##

const ViewModel = preload("res://scripts/council/ViewModel.gd")
const Fixtures  = preload("res://tests/fixtures/view_payload_negotiation.gd")


func _initialize() -> void:
	var failures := 0
	print("--- ViewModel ---")

	failures += _test_basic_accessors()
	failures += _test_phase_inference_negotiation()
	failures += _test_phase_inference_orders()
	failures += _test_terminal_state()
	failures += _test_my_units_and_legal_orders()
	failures += _test_aid_and_leverage()
	failures += _test_stance_lookup()
	failures += _test_betrayals_passthrough()
	failures += _test_tile_lookup()

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


func _test_basic_accessors() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var f := 0
	f += _expect("game_id", vm.game_id() == "test-game", str(vm.game_id()))
	f += _expect("turn", vm.turn() == 3, str(vm.turn()))
	f += _expect("max_turns", vm.max_turns() == 15, str(vm.max_turns()))
	f += _expect("my_player_id", vm.my_player_id() == 0, str(vm.my_player_id()))
	f += _expect("num_players", vm.num_players() == 4, str(vm.num_players()))
	return f


func _test_phase_inference_negotiation() -> int:
	# I (p0) am NOT in chat_done and have NOT submitted → NEGOTIATION.
	var vm := ViewModel.new(Fixtures.negotiation_view())
	return _expect(
		"phase=negotiation when I haven't sealed",
		vm.phase() == "negotiation",
		vm.phase()
	)


func _test_phase_inference_orders() -> int:
	# I'm in chat_done → past press → ORDERS.
	var vm := ViewModel.new(Fixtures.orders_view())
	return _expect(
		"phase=orders when chat_done contains me",
		vm.phase() == "orders",
		vm.phase()
	)


func _test_terminal_state() -> int:
	var vm := ViewModel.new(Fixtures.terminal_view())
	var f := 0
	f += _expect("is_terminal", vm.is_terminal())
	f += _expect("winners", vm.winners() == [0], str(vm.winners()))
	return f


func _test_my_units_and_legal_orders() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var f := 0
	var my := vm.my_units()
	f += _expect("my_units count", my.size() == 2, str(my.size()))
	# Legal orders for unit 2 includes 3 entries.
	var legal := vm.legal_orders_for(2)
	f += _expect("legal_orders unit 2 count", legal.size() == 3, str(legal.size()))
	# Unit 1 is opponent's; legal_orders should be empty.
	f += _expect("legal_orders for opponent unit",
		vm.legal_orders_for(1).is_empty())
	return f


func _test_aid_and_leverage() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var f := 0
	f += _expect("my aid_tokens", vm.aid_tokens(0) == 4, str(vm.aid_tokens(0)))
	# Other players' tokens are also exposed via state.aid_tokens.
	f += _expect("p1 aid_tokens", vm.aid_tokens(1) == 2)
	# Leverage(p0 → p2) = aid_given[0,2] - aid_given[2,0] = 3 - 1 = 2.
	f += _expect("leverage 0→2", vm.leverage(0, 2) == 2, str(vm.leverage(0, 2)))
	# Reverse direction is the negative.
	f += _expect("leverage 2→0", vm.leverage(2, 0) == -2)
	# Pair with no entries returns 0.
	f += _expect("leverage 0→3 = 0", vm.leverage(0, 3) == 0)
	return f


func _test_stance_lookup() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var f := 0
	# last_press contains player 0's stance {1:neutral, 2:ally, 3:neutral}.
	f += _expect("stance 0→2 = ally", vm.stance(0, 2) == "ally", vm.stance(0, 2))
	f += _expect("stance 1→0 = hostile", vm.stance(1, 0) == "hostile")
	# Self-stance is not meaningful; expect "neutral" as safe default.
	f += _expect("stance self = neutral", vm.stance(0, 0) == "neutral")
	return f


func _test_betrayals_passthrough() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var b := vm.your_betrayals()
	return _expect("betrayals length", b.size() == 1, str(b.size()))


func _test_tile_lookup() -> int:
	var vm := ViewModel.new(Fixtures.negotiation_view())
	var f := 0
	# Tile at coord (2, 0) is node 2, a high-value supply.
	var t := vm.tile_at_coord(2, 0)
	f += _expect("tile_at_coord", t.get("node_id") == 2, str(t))
	f += _expect("tile node_type", t.get("node_type") == "SUPPLY")
	f += _expect("tile supply_value", t.get("supply_value") == 2)
	# A node owned by p0 — node 1 (PLAIN).
	var t1 := vm.tile_for_node(1)
	f += _expect("tile_for_node owner", t1.get("owner") == 0)
	# Home banner: node 0 has home_assignment = 0.
	var t0 := vm.tile_for_node(0)
	f += _expect("tile home_player", t0.get("home_player") == 0)
	return f
