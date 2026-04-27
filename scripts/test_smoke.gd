## Headless smoke-test entry. Run with:
##   godot --headless --script res://scripts/test_smoke.gd
##
## Tries to load Main.tscn; reports whether parsing succeeded and what
## children the scene contains. Exits with code 0 on success, 1 on failure.
extends SceneTree


func _init() -> void:
	print("--- foedus-godot smoke test ---")

	# Load all class_name'd scripts first so their globals register before
	# Main.gd parses (which references both GameClient and HexMap).
	var GameClientScript := load("res://scripts/GameClient.gd")
	if GameClientScript == null:
		print("FAIL: GameClient.gd did not load")
		quit(1)
		return
	print("ok: GameClient.gd loaded")

	var HexMapScript := load("res://scripts/HexMap.gd")
	if HexMapScript == null:
		print("FAIL: HexMap.gd did not load")
		quit(1)
		return
	print("ok: HexMap.gd loaded")

	var MainScript := load("res://scripts/Main.gd")
	if MainScript == null:
		print("FAIL: Main.gd did not load")
		quit(1)
		return
	print("ok: Main.gd loaded")

	var scene: PackedScene = load("res://scenes/Main.tscn")
	if scene == null:
		print("FAIL: Main.tscn did not load")
		quit(1)
		return
	print("ok: Main.tscn loaded")

	var root := scene.instantiate()
	if root == null:
		print("FAIL: Main.tscn did not instantiate")
		quit(1)
		return
	print("ok: Main.tscn instantiated as %s" % root.name)

	# Verify expected child structure: a few key nodes must exist.
	var required_paths := [
		"VBox",
		"VBox/HBox/ConnectBtn",
		"VBox/GameCreate/HSeats/NumPlayersSpin",
		"VBox/GameCreate/HSeats/Seat0Opt",
		"VBox/GameCreate/HSeats/Seat5Opt",
		"VBox/GameCreate/HConfig/MaxTurnsSpin",
		"VBox/GameCreate/HConfig/PeaceSpin",
		"VBox/GameCreate/HConfig/SeedSpin",
		"VBox/GameCreate/HPresets/PresetAllBtn",
		"VBox/GameCreate/HPresets/PresetHumanBtn",
		"VBox/GameCreate/HPresets/CreateBtn",
		"VBox/HBoxButtons/AdvanceBtn",
		"VBox/HBoxButtons/AutoBtn",
		"VBox/HBoxButtons/ViewBtn",
		"VBox/HBoxButtons/SubmitBtn",
		"VBox/HBoxButtons/ResetBtn",
		"VBox/HSplit/LeftPanel/OutputLabel",
		"VBox/HSplit/LeftPanel/OrderScroll/OrderList",
		"VBox/HSplit/HexMap",
	]
	for p in required_paths:
		if root.get_node_or_null(p) == null:
			print("FAIL: missing required node at %s" % p)
			root.free()
			quit(1)
			return
		print("ok: %s present" % p)

	# Confirm HexMap has the expected script attached.
	var hex_map: Control = root.get_node("VBox/HSplit/HexMap")
	if hex_map.get_script() == null:
		print("FAIL: HexMap has no script attached")
		root.free()
		quit(1)
		return
	print("ok: HexMap has script")

	root.free()
	print("--- ALL OK ---")
	quit(0)
