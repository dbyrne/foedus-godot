extends Control
##
## Replay viewer — scrub through the game's snapshots.
##
## Loads /games/<id>/history to learn the snapshot list, then fetches
## /games/<id>/history/<turn>/view/<player> on demand. The HexBoard
## renders each snapshot's state. Prev / Next / Play-Resolution
## buttons let the user step through; "Play Resolution N→N+1" mounts a
## CouncilResolution scene above this one for that transition.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md (Phase 2d)
##

const ShellScript           = preload("res://components/CouncilShell.gd")
const HexBoardScript        = preload("res://components/HexBoard.gd")
const BrassPlateScript      = preload("res://components/BrassPlate.gd")
const ResolutionScene       = preload("res://scenes/council/CouncilResolution.tscn")
const ViewModelScript       = preload("res://scripts/council/ViewModel.gd")

signal exit_pressed

var council_game: Node = null
var _root_layer: Control = null
var _hex_board: Node = null
var _turn_label: Label
var _prev_btn: Button
var _next_btn: Button
var _play_btn: Button
var _scrub: HSlider
var _cached_views: Dictionary = {}  # turn → view dict
var _max_snapshot: int = 0
var _current_turn: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game
	if game == null or game.game_client == null:
		return
	# Fetch /history.
	if game.game_client.has_method("history"):
		game.game_client.history(game.game_id)
		# Listen for the response.
		if game.game_client.has_signal("response") \
				and not game.game_client.response.is_connected(_on_history_response):
			game.game_client.response.connect(_on_history_response)


func _build_layout() -> void:
	var shell = ShellScript.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_layer)

	var title_plate = BrassPlateScript.new()
	title_plate.text = "REPLAY"
	title_plate.font_size_px = 12
	title_plate.position = Vector2(60, 60)
	_root_layer.add_child(title_plate)

	# Turn label
	_turn_label = Label.new()
	_turn_label.text = "Turn —"
	_turn_label.add_theme_font_override("font", load(Tokens.FONT_DISPLAY) as Font)
	_turn_label.add_theme_font_size_override("font_size", 24)
	_turn_label.add_theme_color_override("font_color", Tokens.BONE)
	_turn_label.position = Vector2(180, 56)
	_turn_label.size = Vector2(300, 32)
	_root_layer.add_child(_turn_label)

	# HexBoard centered
	var board_wrap := Control.new()
	board_wrap.position = Vector2(60, 110)
	board_wrap.size = Vector2(1160, 620)
	_root_layer.add_child(board_wrap)
	_hex_board = HexBoardScript.new()
	_hex_board.position = Vector2(580, 310)
	board_wrap.add_child(_hex_board)

	# Controls bar
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 16)
	controls.position = Vector2(0, 760)
	controls.size = Vector2(1280, 50)
	_root_layer.add_child(controls)

	_prev_btn = _make_button("◀ Prev")
	_prev_btn.pressed.connect(_on_prev)
	controls.add_child(_prev_btn)

	_scrub = HSlider.new()
	_scrub.min_value = 0
	_scrub.max_value = 0
	_scrub.step = 1
	_scrub.custom_minimum_size = Vector2(400, 30)
	_scrub.value_changed.connect(_on_scrub_changed)
	controls.add_child(_scrub)

	_next_btn = _make_button("Next ▶")
	_next_btn.pressed.connect(_on_next)
	controls.add_child(_next_btn)

	_play_btn = _make_button("Play Resolution N → N+1")
	_play_btn.pressed.connect(_on_play_resolution)
	controls.add_child(_play_btn)

	var exit_btn := _make_button("Exit")
	exit_btn.pressed.connect(func(): exit_pressed.emit())
	controls.add_child(exit_btn)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	b.add_theme_font_size_override("font_size", 12)
	return b


func _on_history_response(endpoint: String, data: Variant) -> void:
	if not endpoint.ends_with("/history"):
		return
	if data is Dictionary:
		var snapshots: Array = data.get("snapshots", [])
		if not snapshots.is_empty():
			_max_snapshot = int(snapshots[snapshots.size() - 1])
			_scrub.max_value = _max_snapshot
			_scrub.value = _max_snapshot
			_load_snapshot(_max_snapshot)


func _load_snapshot(turn: int) -> void:
	if council_game == null or council_game.game_client == null:
		return
	if _cached_views.has(turn):
		_apply_view(turn, _cached_views[turn])
		return
	if council_game.game_client.has_method("history_view"):
		# Listen one-shot for this specific snapshot's response.
		if council_game.game_client.has_signal("response") \
				and not council_game.game_client.response.is_connected(_on_view_response):
			council_game.game_client.response.connect(_on_view_response)
		council_game.game_client.history_view(
			council_game.game_id, turn, council_game.view_player
		)


func _on_view_response(endpoint: String, data: Variant) -> void:
	if not endpoint.contains("/history/"):
		return
	if data is Dictionary:
		var turn := int(data.get("turn", -1))
		if turn >= 0:
			_cached_views[turn] = data
			_apply_view(turn, data)


func _apply_view(turn: int, view_data: Dictionary) -> void:
	_current_turn = turn
	_turn_label.text = "Turn %d / %d" % [turn, _max_snapshot]
	var vm = ViewModelScript.new(view_data)
	_hex_board.set_view_model(vm)


func _on_prev() -> void:
	if _current_turn > 0:
		_scrub.value = _current_turn - 1


func _on_next() -> void:
	if _current_turn < _max_snapshot:
		_scrub.value = _current_turn + 1


func _on_scrub_changed(value: float) -> void:
	_load_snapshot(int(value))


func _on_play_resolution() -> void:
	if _current_turn >= _max_snapshot:
		return
	var prev = _cached_views.get(_current_turn)
	var curr = _cached_views.get(_current_turn + 1)
	if prev == null or curr == null:
		# Fetch them, then retry.
		_load_snapshot(_current_turn + 1)
		return
	var resolution = ResolutionScene.instantiate()
	get_tree().root.add_child(resolution)
	resolution.attach_game(council_game)
	resolution.play_between(prev, curr)
	if resolution.has_signal("playback_finished"):
		resolution.playback_finished.connect(
			func(): resolution.queue_free(), CONNECT_ONE_SHOT
		)
