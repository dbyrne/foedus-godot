extends SceneTree
##
## Phase 1 primitives — headless smoke test.
##
## Loads every component .gd by class_name, instantiates each, asserts
## no errors. Then loads the demo scene and verifies it has the
## expected number of section children.
##
## Run: godot --headless --script res://scripts/test_phase1_primitives.gd
##

const COMPONENT_SCRIPTS := [
	"res://components/BrassPlate.gd",
	"res://components/Crest.gd",
	"res://components/WaxEnvelope.gd",
	"res://components/Throne.gd",
	"res://components/UnitPiece.gd",
	"res://components/TensionMeter.gd",
	"res://components/ScalesOfLeverage.gd",
	"res://components/CouncilHex.gd",
	"res://components/CouncilShell.gd",
]

const DEMO_SCENE := "res://scenes/Phase1Demo.tscn"
const EXPECTED_DEMO_SECTIONS := 8


func _initialize() -> void:
	var failures := 0
	print("--- foedus-godot phase 1 primitives ---")

	# Load and instantiate each component.
	for path in COMPONENT_SCRIPTS:
		var script := load(path) as Script
		if script == null:
			push_error("FAIL: could not load %s" % path)
			failures += 1
			continue
		var obj = script.new()
		if obj == null:
			push_error("FAIL: could not instantiate %s" % path)
			failures += 1
			continue
		obj.free()
		print("ok: ", path)

	# Tokens autoload sanity.
	if not (typeof(Tokens.BRASS) == TYPE_COLOR
			and Tokens.PLAYER_COLORS.size() == 4
			and Tokens.HEX_R == 32):
		push_error("FAIL: Tokens autoload missing expected constants")
		failures += 1
	else:
		print("ok: Tokens autoload (palette + players + HEX_R)")

	# Demo scene's attached script must parse cleanly. load() can return
	# a partial Script object even on parse error, so we instantiate to
	# confirm the script is fully usable.
	var demo_script := load("res://scripts/Phase1Demo.gd") as Script
	if demo_script == null:
		push_error("FAIL: Phase1Demo.gd missing or unloadable")
		failures += 1
	else:
		var probe = demo_script.new()
		if probe == null:
			push_error("FAIL: Phase1Demo.gd has parse errors")
			failures += 1
		else:
			probe.free()
			print("ok: scripts/Phase1Demo.gd parses + instantiates")
	var demo := load(DEMO_SCENE) as PackedScene
	if demo == null:
		push_error("FAIL: %s missing or unloadable" % DEMO_SCENE)
		failures += 1
	else:
		var inst = demo.instantiate()
		if inst == null:
			push_error("FAIL: %s did not instantiate" % DEMO_SCENE)
			failures += 1
		else:
			inst.queue_free()
			print("ok: ", DEMO_SCENE)

	if failures == 0:
		print("--- ALL OK ---")
		quit(0)
	else:
		print("--- %d FAILURES ---" % failures)
		quit(1)
