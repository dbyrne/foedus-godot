extends SceneTree
const OUT_PATH := "/tmp/phase2a-entry.png"

func _initialize() -> void:
	var Entry = load("res://scenes/council/CouncilEntry.tscn") as PackedScene
	var entry = Entry.instantiate()
	root.add_child(entry)
	await create_timer(0.6).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_PATH)
	print("captured: ", OUT_PATH)
	quit(0)
