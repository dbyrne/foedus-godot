extends SceneTree
##
## Phase 1 demo screenshot capture.
##
## Loads Phase1Demo.tscn, lets it render two frames, captures the
## viewport as a PNG to /tmp/phase1-demo.png, exits.
##
## Run with a real display (WSLg / X11):
##   DISPLAY=:0 godot --script res://scripts/capture_phase1_demo.gd \
##                    --resolution 1280x800 --quit-after 3
##

const OUT_PATH := "/tmp/phase1-demo.png"


func _initialize() -> void:
	var ps := load("res://scenes/Phase1Demo.tscn") as PackedScene
	if ps == null:
		push_error("Could not load Phase1Demo.tscn")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	# Let _ready (and the await get_tree().process_frame inside it) complete,
	# plus a few render frames so _draw runs and the viewport texture is up to date.
	await create_timer(0.8).timeout
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("get_image() returned null — display likely missing")
		quit(1)
		return
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("save_png failed: %d" % err)
		quit(1)
		return
	print("captured: ", OUT_PATH, " (", img.get_width(), "x", img.get_height(), ")")
	quit(0)
