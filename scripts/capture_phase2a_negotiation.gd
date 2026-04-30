extends SceneTree
##
## Visual capture of the full Negotiation screen against synthetic
## view data — for review during 2a.
##

const OUT_PATH := "/tmp/phase2a-negotiation.png"


func _initialize() -> void:
	var Neg = load("res://scenes/council/CouncilNegotiation.tscn") as PackedScene
	var Game = load("res://scripts/council/CouncilGame.gd")
	var VM = load("res://scripts/council/ViewModel.gd")
	var Press = load("res://scripts/council/PressController.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")

	var neg = Neg.instantiate()
	root.add_child(neg)

	# Wait one frame so the scene's _ready / _build_layout runs.
	await create_timer(0.4).timeout

	# Stub controller — feed a synthetic view.
	var vm = VM.new(Fix.negotiation_view())
	var game = Game.new()
	game.view_model = vm
	game.press = Press.new()
	game.press.seed_from_view(vm)
	neg.add_child(game)
	neg.attach_game(game)
	neg._on_view_changed(vm)

	# Settle frames so all _draw passes complete.
	await create_timer(0.6).timeout

	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("Could not capture viewport"); quit(1); return
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("save_png failed: %d" % err); quit(1); return
	print("captured: ", OUT_PATH, " (", img.get_width(), "x", img.get_height(), ")")
	quit(0)
