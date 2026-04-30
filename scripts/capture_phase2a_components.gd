extends SceneTree
##
## Visual review for Phase 2a's HexBoard + Sociogram against the
## synthetic ViewModel fixture.
##
## Run:
##   DISPLAY=:0 godot --script res://scripts/capture_phase2a_components.gd \
##       --resolution 1280x720 --quit-after 200
##

const OUT_PATH := "/tmp/phase2a-components.png"


func _initialize() -> void:
	var Shell  = load("res://components/CouncilShell.gd")
	var Hex    = load("res://components/HexBoard.gd")
	var Soc    = load("res://components/Sociogram.gd")
	var Plate  = load("res://components/BrassPlate.gd")
	var VM     = load("res://scripts/council/ViewModel.gd")
	var Fix    = load("res://tests/fixtures/view_payload_negotiation.gd")

	var vm = VM.new(Fix.negotiation_view())

	# Mount the shell as a backdrop, then add freely-positioned
	# children directly to the root Control (bypassing the shell's
	# MarginContainer, which forces fill-layout on its children).
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_ctrl)

	var shell = Shell.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(shell)

	# Wait one frame so CouncilShell._ready completes.
	await create_timer(0.3).timeout

	# Section labels.
	var war_plate = Plate.new()
	war_plate.text = "WAR TABLE"
	war_plate.font_size_px = 11
	war_plate.position = Vector2(60, 64)
	root_ctrl.add_child(war_plate)

	var court_plate = Plate.new()
	court_plate.text = "THE COURT"
	court_plate.font_size_px = 11
	court_plate.position = Vector2(720, 64)
	root_ctrl.add_child(court_plate)

	# HexBoard wrapper.
	var board_wrap := Control.new()
	board_wrap.position = Vector2(60, 100)
	board_wrap.size = Vector2(620, 580)
	root_ctrl.add_child(board_wrap)

	var board = Hex.new()
	board.position = Vector2(310, 290)
	board_wrap.add_child(board)
	board.set_view_model(vm)

	# Sociogram.
	var soc = Soc.new()
	soc.position = Vector2(720, 100)
	soc.size = Vector2(500, 220)
	root_ctrl.add_child(soc)
	soc.set_view_model(vm)

	# Settle frames so all _draw passes complete.
	await create_timer(0.6).timeout

	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("Could not capture viewport image (display missing?)")
		quit(1)
		return
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("save_png failed: %d" % err)
		quit(1)
		return
	print("captured: ", OUT_PATH, " (", img.get_width(), "x", img.get_height(), ")")
	quit(0)
