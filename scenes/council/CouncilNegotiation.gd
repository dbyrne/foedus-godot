extends Control
##
## Negotiation screen — the densest War Council screen.
##
## Layout:
##   ┌─────────────────────────────────────────────────────────┐
##   │ TensionMeter (full-width across top)                    │
##   ├──────────────────────────────────┬──────────────────────┤
##   │                                  │                      │
##   │         HexBoard                 │     CourtPanel       │
##   │       (war table)                │  (sociogram + stance │
##   │                                  │   + aid + chat)      │
##   │                                  │                      │
##   ├──────────────────────────────────┴──────────────────────┤
##   │ Declared intents row (BrassPlates per published intent) │
##   └─────────────────────────────────────────────────────────┘
##
## Driven by a CouncilGame controller; subscribes to its
## `view_changed(view_model)` signal to re-render.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const ShellScript      = preload("res://components/CouncilShell.gd")
const HexBoardScript   = preload("res://components/HexBoard.gd")
const CourtPanelScript = preload("res://components/CourtPanel.gd")
const TensionScript    = preload("res://components/TensionMeter.gd")
const BrassPlateScript = preload("res://components/BrassPlate.gd")
const ViewModelScript  = preload("res://scripts/council/ViewModel.gd")

var council_game: Node = null  # CouncilGame
var _shell: Node = null
var _hex_board: Node = null
var _court: Node = null
var _tension: Node = null
var _intents_row: HBoxContainer
var _root_layer: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game
	if council_game.has_signal("view_changed"):
		council_game.view_changed.connect(_on_view_changed)
	# If a view is already loaded, render it immediately.
	if council_game.view_model != null:
		_on_view_changed(council_game.view_model)


func _build_layout() -> void:
	_shell = ShellScript.new()
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shell)

	# Use a freely-positioned overlay rather than the shell's
	# MarginContainer, so we can pin TensionMeter / panels at fixed
	# offsets instead of having them stretch.
	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root_layer)

	# TensionMeter — top of viewport, inside frame
	_tension = TensionScript.new()
	_tension.position = Vector2(60, 50)
	_tension.custom_minimum_size = Vector2(1160, 36)
	_tension.size = Vector2(1160, 36)
	_root_layer.add_child(_tension)

	# Hex board — left ~620 wide
	var board_label = BrassPlateScript.new()
	board_label.text = "WAR TABLE"
	board_label.font_size_px = 11
	board_label.position = Vector2(60, 100)
	_root_layer.add_child(board_label)

	var board_wrap := Control.new()
	board_wrap.position = Vector2(60, 132)
	board_wrap.size = Vector2(620, 540)
	_root_layer.add_child(board_wrap)
	_hex_board = HexBoardScript.new()
	_hex_board.position = Vector2(310, 270)
	board_wrap.add_child(_hex_board)

	# Court panel — right rail
	_court = CourtPanelScript.new()
	_court.position = Vector2(700, 100)
	_court.size = Vector2(540, 700)
	_root_layer.add_child(_court)

	# Declared intents row at the bottom
	var intents_label = BrassPlateScript.new()
	intents_label.text = "DECLARED INTENTS"
	intents_label.font_size_px = 11
	intents_label.position = Vector2(60, 700)
	_root_layer.add_child(intents_label)
	_intents_row = HBoxContainer.new()
	_intents_row.position = Vector2(60, 732)
	_intents_row.size = Vector2(620, 60)
	_intents_row.add_theme_constant_override("separation", 12)
	_root_layer.add_child(_intents_row)

	# Wire CourtPanel signals to the controller's PressController.
	_court.stance_changed.connect(_on_stance_changed)
	_court.aid_spend_toggled.connect(_on_aid_toggled)
	_court.chat_text_changed.connect(_on_chat_changed)
	_court.seal_pressed.connect(_on_seal_pressed)


func _on_view_changed(vm) -> void:
	if vm == null:
		return
	# Defensive: if attach_game was called before _ready ran, the
	# child nodes don't exist yet. Defer the render until the next
	# idle frame.
	if _hex_board == null or _court == null or _tension == null:
		call_deferred("_on_view_changed", vm)
		return
	_hex_board.set_view_model(vm)
	_court.set_view_model(vm)
	_tension.phase = (
		"orders" if vm.phase() == ViewModelScript.PHASE_ORDERS else "negotiation"
	)
	_tension.timer_text = "T %d / %d" % [vm.turn(), vm.max_turns()]
	# Progress meter: how far through max_turns we are.
	var tt := float(vm.max_turns())
	_tension.value = (float(vm.turn()) / tt) if tt > 0 else 0.0
	_render_intents(vm)


func _render_intents(vm) -> void:
	for c in _intents_row.get_children():
		c.queue_free()
	for intent in vm.declared_intents():
		var plate = BrassPlateScript.new()
		var pid := int(intent.get("player_id", -1))
		var unit_id := int(intent.get("unit_id", -1))
		var ord = intent.get("declared_order", {})
		# Wire uses `type` (not `kind`); also surface destination/target
		# when present so the chip says "BOR u4 MOVE→14" rather than a
		# bare verb.
		var verb := String(ord.get("type", ord.get("kind", "?")))
		var detail := ""
		if ord.has("dest"):
			detail = "→%s" % str(ord["dest"])
		elif ord.has("target_unit"):
			detail = "·u%s" % str(ord["target_unit"])
		plate.text = "%s u%d %s%s" % [
			Tokens.faction_tag(pid), unit_id, verb.to_upper(), detail
		]
		plate.font_size_px = 9
		_intents_row.add_child(plate)


# --- Court panel signal handlers (forward to PressController) ----------

func _on_stance_changed(other_pid: int, value: String) -> void:
	if council_game and council_game.press:
		council_game.press.set_stance(other_pid, value)


func _on_aid_toggled(other_pid: int, on: bool) -> void:
	if council_game and council_game.press:
		council_game.press.toggle_aid(other_pid, on)


func _on_chat_changed(text: String) -> void:
	if council_game and council_game.press:
		council_game.press.set_chat(text)


func _on_seal_pressed() -> void:
	if council_game:
		council_game.seal_intent()
