## Headless smoke-test entry. Run with:
##   godot --headless --script res://scripts/test_smoke.gd
##
## Tries to load Main.tscn; reports whether parsing succeeded and what
## children the scene contains. Exits with code 0 on success, 1 on failure.
extends SceneTree


func _init() -> void:
	print("--- foedus-godot smoke test ---")

	var GameClientScript := load("res://scripts/GameClient.gd")
	if GameClientScript == null:
		print("FAIL: GameClient.gd did not load")
		quit(1)
		return
	print("ok: GameClient.gd loaded")

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

	# Verify expected child structure.
	var vbox := root.get_node_or_null("VBox")
	if vbox == null:
		print("FAIL: Main has no VBox")
		root.free()
		quit(1)
		return
	print("ok: VBox present (%d children)" % vbox.get_child_count())
	for c in vbox.get_children():
		print("    - %s [%s]" % [c.name, c.get_class()])

	root.free()
	print("--- ALL OK ---")
	quit(0)
