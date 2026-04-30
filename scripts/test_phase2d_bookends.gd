extends SceneTree
##
## Phase 2d smoke — Coronation, Pairwise, Replay scenes load + render.
##

func _initialize() -> void:
	var failures := 0
	print("--- Phase 2d ---")

	for path in [
		"res://scenes/council/CouncilCoronation.gd",
		"res://scenes/council/CouncilPairwise.gd",
		"res://scenes/council/CouncilReplay.gd",
	]:
		var s := load(path) as Script
		if s == null:
			push_error("FAIL: load " + path); failures += 1; continue
		print("ok: ", path)

	for path in [
		"res://scenes/council/CouncilCoronation.tscn",
		"res://scenes/council/CouncilPairwise.tscn",
		"res://scenes/council/CouncilReplay.tscn",
	]:
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("FAIL: " + path); failures += 1; continue
		var inst = packed.instantiate()
		if inst == null:
			push_error("FAIL: instantiate " + path); failures += 1; continue
		inst.queue_free()
		print("ok: ", path)

	# Drive Coronation against the terminal_view fixture.
	var Cor = load("res://scenes/council/CouncilCoronation.tscn") as PackedScene
	var Game = load("res://scripts/council/CouncilGame.gd")
	var VM = load("res://scripts/council/ViewModel.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")
	var cor = Cor.instantiate()
	root.add_child(cor)
	var vm = VM.new(Fix.terminal_view())
	var game = Game.new()
	game.view_model = vm
	cor.add_child(game)
	cor.attach_game(game)
	failures += _expect("Coronation rendered terminal view",
		cor.get_child_count() > 0)

	# Drive Pairwise against the negotiation fixture.
	var Pair = load("res://scenes/council/CouncilPairwise.tscn") as PackedScene
	var pair = Pair.instantiate()
	root.add_child(pair)
	var pair_vm = VM.new(Fix.negotiation_view())
	var pair_game = Game.new()
	pair_game.view_model = pair_vm
	pair.add_child(pair_game)
	pair.attach_game(pair_game)
	failures += _expect("Pairwise rendered with default focus",
		pair.get_child_count() > 0)

	if failures == 0:
		print("--- ALL OK ---")
		quit(0)
	else:
		print("--- %d FAILURES ---" % failures)
		quit(1)


func _expect(name: String, cond: bool) -> int:
	if cond:
		print("ok: ", name)
		return 0
	push_error("FAIL: " + name)
	return 1
