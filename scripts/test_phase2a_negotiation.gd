extends SceneTree
##
## Phase 2a integration smoke — loads every new Council script,
## instantiates the Negotiation scene, drives it with a synthetic
## ViewModel (no live server), asserts structural correctness.
##
## Run: godot --headless --script res://scripts/test_phase2a_negotiation.gd
##

const SCRIPTS := [
	"res://scripts/council/ViewModel.gd",
	"res://scripts/council/PressController.gd",
	"res://scripts/council/CouncilGame.gd",
	"res://components/HexBoard.gd",
	"res://components/Sociogram.gd",
	"res://components/CourtPanel.gd",
	"res://scenes/council/CouncilNegotiation.gd",
	"res://scenes/council/CouncilEntry.gd",
]


func _initialize() -> void:
	var failures := 0
	print("--- Phase 2a integration ---")

	# Every script loads + instantiates.
	for path in SCRIPTS:
		var script := load(path) as Script
		if script == null:
			push_error("FAIL: load %s" % path); failures += 1; continue
		var inst = script.new()
		if inst == null:
			push_error("FAIL: instantiate %s" % path); failures += 1; continue
		# Free RefCounted via reference drop; Node via free().
		if inst is Node:
			inst.free()
		print("ok: ", path)

	# Negotiation scene loads.
	var neg_packed := load("res://scenes/council/CouncilNegotiation.tscn") as PackedScene
	if neg_packed == null:
		push_error("FAIL: CouncilNegotiation.tscn"); failures += 1
	else:
		var neg = neg_packed.instantiate()
		root.add_child(neg)
		await create_timer(0.1).timeout
		# Feed a synthetic view via an in-process CouncilGame stand-in.
		var VM = load("res://scripts/council/ViewModel.gd")
		var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")
		var vm = VM.new(Fix.negotiation_view())
		# Stub controller — just enough to feed view_changed.
		var Game = load("res://scripts/council/CouncilGame.gd")
		var game = Game.new()
		game.view_model = vm
		game.press = load("res://scripts/council/PressController.gd").new()
		game.press.seed_from_view(vm)
		neg.add_child(game)
		neg.attach_game(game)
		# Manually fire view_changed since attach_game's path through
		# game_client's response signal isn't wired here.
		neg._on_view_changed(vm)
		neg._on_intent_drag_proposed(2, 4)
		failures += _expect("dragging own unit stages Move intent",
			game.press.intents.size() == 1
			and int(game.press.intents[0].get("unit_id", -1)) == 2
			and String(game.press.intents[0].get("declared_order", {}).get("type", "")) == "Move"
			and int(game.press.intents[0].get("declared_order", {}).get("dest", -1)) == 4)
		failures += _expect("intent payload uses visible_to",
			game.press.to_press_payload()["intents"][0].has("visible_to")
			and not game.press.to_press_payload()["intents"][0].has("recipients"))
		failures += _expect("staged intent keeps arrow visible",
			neg._intent_arrow_nodes.size() == 1)
		neg._on_unit_clicked(2, MOUSE_BUTTON_RIGHT)
		failures += _expect("right-click removes staged intent",
			game.press.intents.is_empty())
		failures += _expect("right-click removes staged arrow",
			neg._intent_arrow_nodes.is_empty())
		print("ok: CouncilNegotiation rendered against synthetic view")

	# Entry scene loads.
	var entry_packed := load("res://scenes/council/CouncilEntry.tscn") as PackedScene
	if entry_packed == null:
		push_error("FAIL: CouncilEntry.tscn"); failures += 1
	else:
		var entry = entry_packed.instantiate()
		entry.queue_free()
		print("ok: CouncilEntry.tscn loads")

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
	push_error("FAIL: %s - %s" % [name, detail])
	return 1
