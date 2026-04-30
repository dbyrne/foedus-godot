extends SceneTree
##
## Phase 2a component smoke — HexBoard + Sociogram instantiate
## against a synthetic ViewModel and produce the expected children.
##
## NOTE: scripts that reference the Tokens autoload (HexBoard, Crest,
## CouncilHex, Sociogram, etc.) must be loaded at runtime, not via
## `preload`. preload parses at script-load time, before the autoload
## registers, and produces "Identifier Tokens not found".
##

var HexBoardScript: Script
var SociogramScript: Script
var ViewModelScript: Script
var Fixtures: GDScript


func _initialize() -> void:
	HexBoardScript  = load("res://components/HexBoard.gd")
	SociogramScript = load("res://components/Sociogram.gd")
	ViewModelScript = load("res://scripts/council/ViewModel.gd")
	Fixtures        = load("res://tests/fixtures/view_payload_negotiation.gd")

	var failures := 0
	print("--- Phase 2a components ---")

	failures += _test_hexboard()
	failures += _test_sociogram()

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


func _test_hexboard() -> int:
	var failures := 0
	var board = HexBoardScript.new()
	root.add_child(board)
	var vm = ViewModelScript.new(Fixtures.negotiation_view())
	board.set_view_model(vm)
	# Fixture has 6 tiles.
	# Count CouncilHex children.
	var hex_children := 0
	for c in board.get_children():
		if c.get_class() == "Node2D" or c.get_script() != null:
			hex_children += 1
	failures += _expect(
		"HexBoard mounts one Node2D per tile",
		hex_children == 6,
		str(hex_children)
	)
	# Selecting a unit toggles the selected halo.
	board.set_selected_unit_id(2)
	failures += _expect(
		"HexBoard selected_unit_id stored",
		board.selected_unit_id() == 2
	)
	board.queue_free()
	return failures


func _test_sociogram() -> int:
	var failures := 0
	var soc = SociogramScript.new()
	root.add_child(soc)
	var vm = ViewModelScript.new(Fixtures.negotiation_view())
	soc.set_view_model(vm)
	# Sociogram should have 4 Crest children (one per player).
	var crest_count := 0
	for c in soc.get_children():
		var s = c.get_script()
		if s != null and s.resource_path == "res://components/Crest.gd":
			crest_count += 1
	failures += _expect(
		"Sociogram mounts 4 Crests",
		crest_count == 4,
		str(crest_count)
	)
	soc.queue_free()
	return failures
