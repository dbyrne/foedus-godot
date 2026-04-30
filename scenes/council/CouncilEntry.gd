extends Control
##
## Title screen + game-create launcher.
##
## Connects to a play-server, creates a 4-seat game, mounts the
## CouncilGame controller and the appropriate phase scene. Subscribes
## to view_changed to detect turn-number increases (auto-mounts
## Resolution playback between turns) and to phase_transition to
## swap between Negotiation, Orders, and Coronation.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const ShellScript      = preload("res://components/CouncilShell.gd")
const BrassPlateScript = preload("res://components/BrassPlate.gd")
const NegotiationScene = preload("res://scenes/council/CouncilNegotiation.tscn")
const OrdersScene      = preload("res://scenes/council/CouncilOrders.tscn")
const ResolutionScene  = preload("res://scenes/council/CouncilResolution.tscn")
const CoronationScene  = preload("res://scenes/council/CouncilCoronation.tscn")
const PairwiseScene    = preload("res://scenes/council/CouncilPairwise.tscn")
const ReplayScene      = preload("res://scenes/council/CouncilReplay.tscn")
const CouncilGameScript = preload("res://scripts/council/CouncilGame.gd")
const ViewModelScript  = preload("res://scripts/council/ViewModel.gd")
const GameClientScript = preload("res://scripts/GameClient.gd")

var _game_client: Node = null
var _status_label: Label
var _server_input: LineEdit
var _connect_btn: Button
var _create_btn: Button
var _council_btn: Button
var _game_id: String = ""

# Phase-driven scene mounting for Council mode.
var _council_game: Node = null
var _active_scene: Node = null
var _active_phase: String = ""
# For auto-resolution playback between turns:
var _last_view_payload: Dictionary = {}
var _resolution_scene: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_game_client = GameClientScript.new()
	add_child(_game_client)
	if _game_client.has_signal("response"):
		_game_client.response.connect(_on_response)
	if _game_client.has_signal("failure"):
		_game_client.failure.connect(_on_failure)


func _build_layout() -> void:
	var shell = ShellScript.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	var v := VBoxContainer.new()
	v.position = Vector2(120, 120)
	v.size = Vector2(700, 500)
	v.add_theme_constant_override("separation", 18)
	add_child(v)

	var title := Label.new()
	title.text = "FOEDUS"
	title.add_theme_font_override("font", load(Tokens.FONT_DISPLAY) as Font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Tokens.BONE)
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "the war council"
	subtitle.add_theme_font_override(
		"font", load(Tokens.FONT_SERIF_ITALIC) as Font
	)
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Tokens.BONE_DIM)
	v.add_child(subtitle)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 20)
	v.add_child(sep)

	# Server URL row
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	v.add_child(server_row)
	var server_lbl := _label("Server:")
	server_lbl.custom_minimum_size = Vector2(120, 0)
	server_row.add_child(server_lbl)
	_server_input = LineEdit.new()
	_server_input.text = "http://127.0.0.1:8090"
	_server_input.custom_minimum_size = Vector2(380, 0)
	_server_input.add_theme_font_override("font", load(Tokens.FONT_MONO) as Font)
	_server_input.add_theme_font_size_override("font_size", 14)
	server_row.add_child(_server_input)
	_connect_btn = _button("Connect")
	_connect_btn.pressed.connect(_on_connect_pressed)
	server_row.add_child(_connect_btn)

	# Status
	_status_label = _label("(not connected)")
	v.add_child(_status_label)

	# Game creation row
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	v.add_child(create_row)
	_create_btn = _button("Create demo game (1 human + 3 AI)")
	_create_btn.disabled = true
	_create_btn.pressed.connect(_on_create_pressed)
	create_row.add_child(_create_btn)

	# Begin button (no longer dual-mode after the 2d flag-day swap).
	_council_btn = _button("Take the throne")
	_council_btn.disabled = true
	_council_btn.pressed.connect(_on_council_pressed)
	v.add_child(_council_btn)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Tokens.BONE)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	b.add_theme_font_size_override("font_size", 12)
	return b


# --- Handlers -----------------------------------------------------------

func _on_connect_pressed() -> void:
	_game_client.base_url = _server_input.text
	_status_label.text = "connecting…"
	if _game_client.has_method("healthz"):
		_game_client.healthz()


func _on_create_pressed() -> void:
	_status_label.text = "creating game…"
	if _game_client.has_method("create_game"):
		var config := {
			"num_players": 4,
			"seed": 42,
			"max_turns": 20,
			"peace_threshold": 99,
		}
		_game_client.create_game(config, [
			{"type": "human", "name": "You"},
			{
				"type": "agent",
				"name": "Cooperator",
				"kind": "foedus.agents.heuristics.Cooperator",
			},
			{
				"type": "agent",
				"name": "DishonestCooperator",
				"kind": "foedus.agents.heuristics.DishonestCooperator",
			},
			{
				"type": "agent",
				"name": "GreedyHold",
				"kind": "foedus.agents.heuristics.GreedyHold",
			},
		])


## v0 mode handler removed in 2d flag-day swap; CouncilEntry no longer
## offers the legacy UI. Main.tscn still exists in the repo for
## archeological reference but is no longer the project's main scene.


func _on_council_pressed() -> void:
	if _game_id == "":
		return
	_council_game = CouncilGameScript.new()
	add_child(_council_game)
	_council_game.attach(_game_client, _game_id, 0)
	if _council_game.has_signal("phase_transition"):
		_council_game.phase_transition.connect(_on_phase_transition)
	if _council_game.has_signal("view_changed"):
		_council_game.view_changed.connect(_on_view_for_resolution)
	# Mount Negotiation by default; the first /view response will fire
	# phase_transition and swap if needed.
	_mount_scene_for_phase(ViewModelScript.PHASE_NEGOTIATION)
	_council_game.refresh_view()
	visible = false


func _on_view_for_resolution(vm) -> void:
	## Detect the moment a turn finalized: the /view payload's turn
	## just incremented. When that happens, mount Resolution between
	## the previously-cached snapshot and the fresh one before the
	## new turn's Negotiation/Orders screen takes over.
	if vm == null:
		return
	var new_view: Dictionary = vm._raw if vm.has_method("get") else {}
	# Cache and bail on first view (no prior to compare).
	if _last_view_payload.is_empty():
		_last_view_payload = new_view
		return
	var prev_turn: int = int(_last_view_payload.get("turn", -1))
	var curr_turn: int = int(new_view.get("turn", -1))
	if curr_turn > prev_turn and curr_turn > 0:
		_play_resolution(_last_view_payload, new_view)
	_last_view_payload = new_view


func _play_resolution(prev: Dictionary, curr: Dictionary) -> void:
	## Mount the Resolution scene over the current screen, play the
	## animation, then queue_free it on completion. The underlying
	## Negotiation/Orders scene stays in the tree and resumes
	## visibility once Resolution finishes.
	if _resolution_scene != null:
		_resolution_scene.queue_free()
	_resolution_scene = ResolutionScene.instantiate()
	get_tree().root.add_child(_resolution_scene)
	if _resolution_scene.has_method("attach_game"):
		_resolution_scene.attach_game(_council_game)
	if _resolution_scene.has_method("play_between"):
		_resolution_scene.play_between(prev, curr)
	if _resolution_scene.has_signal("playback_finished"):
		_resolution_scene.playback_finished.connect(
			_on_resolution_finished, CONNECT_ONE_SHOT
		)


func _on_resolution_finished() -> void:
	if _resolution_scene != null:
		_resolution_scene.queue_free()
		_resolution_scene = null


func _on_phase_transition(from_phase: String, to_phase: String) -> void:
	if to_phase == _active_phase:
		return
	_mount_scene_for_phase(to_phase)


func _mount_scene_for_phase(phase: String) -> void:
	if _active_scene != null:
		_active_scene.queue_free()
		_active_scene = null
	var packed: PackedScene = null
	match phase:
		ViewModelScript.PHASE_NEGOTIATION:
			packed = NegotiationScene
		ViewModelScript.PHASE_ORDERS:
			packed = OrdersScene
		ViewModelScript.PHASE_RESOLVED:
			packed = CoronationScene
		_:
			packed = NegotiationScene
	if packed == null:
		return
	_active_scene = packed.instantiate()
	get_tree().root.add_child(_active_scene)
	_active_phase = phase
	if _active_scene.has_method("attach_game") and _council_game != null:
		_active_scene.attach_game(_council_game)
	# Coronation can fire view_replay_pressed → swap to Replay scene.
	if _active_scene.has_signal("view_replay_pressed"):
		_active_scene.view_replay_pressed.connect(_on_view_replay)


func _on_view_replay() -> void:
	if _active_scene != null:
		_active_scene.queue_free()
	_active_scene = ReplayScene.instantiate()
	get_tree().root.add_child(_active_scene)
	if _active_scene.has_method("attach_game"):
		_active_scene.attach_game(_council_game)
	if _active_scene.has_signal("exit_pressed"):
		_active_scene.exit_pressed.connect(
			func(): _mount_scene_for_phase(ViewModelScript.PHASE_RESOLVED)
		)


# --- Game client signals -----------------------------------------------

func _on_response(endpoint: String, data: Variant) -> void:
	if endpoint.ends_with("/healthz"):
		_status_label.text = "connected to " + _server_input.text
		_create_btn.disabled = false
	elif endpoint.ends_with("/games") or "/games" in endpoint and data is Dictionary and data.has("game_id"):
		_game_id = String(data.get("game_id", ""))
		if _game_id != "":
			_status_label.text = "game ready: " + _game_id
			_council_btn.disabled = false


func _on_failure(endpoint: String, message: String) -> void:
	_status_label.text = "failed: %s — %s" % [endpoint, message]
