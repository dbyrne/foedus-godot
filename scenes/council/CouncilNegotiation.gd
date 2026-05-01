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
const OrderControllerScript = preload("res://scripts/council/OrderController.gd")
const OrderArrowScript = preload("res://components/OrderArrow.gd")
const SupportArrowHintScript = preload("res://scripts/council/SupportArrowHint.gd")

var council_game: Node = null  # CouncilGame
var _shell: Node = null
var _hex_board: Node = null
var _court: Node = null
var _tension: Node = null
var _intents_row: HBoxContainer
var _root_layer: Control = null
var _intent_arrow_layer: Node2D = null
var _intent_arrow_nodes: Array = []


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
	_hex_board.drag_proposed.connect(_on_intent_drag_proposed)
	_hex_board.unit_clicked.connect(_on_unit_clicked)
	_intent_arrow_layer = Node2D.new()
	_intent_arrow_layer.position = _hex_board.position
	_intent_arrow_layer.z_index = 1000
	board_wrap.add_child(_intent_arrow_layer)

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
	_refresh_intent_arrows()


func _render_intents(vm) -> void:
	if _intents_row == null:
		return
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
	if council_game != null and council_game.press != null:
		for draft in council_game.press.intents:
			var local_intent: Dictionary = draft.duplicate(true)
			local_intent["player_id"] = vm.my_player_id()
			_add_intent_plate(local_intent, true)


func _add_intent_plate(intent: Dictionary, is_draft: bool) -> void:
	var plate = BrassPlateScript.new()
	var pid := int(intent.get("player_id", -1))
	var unit_id := int(intent.get("unit_id", -1))
	var ord = intent.get("declared_order", {})
	var verb := String(ord.get("type", ord.get("kind", "?")))
	var detail := ""
	if ord.has("dest"):
		detail = "->%s" % str(ord["dest"])
	elif ord.has("target_unit"):
		detail = " u%s" % str(ord["target_unit"])
	elif ord.has("target"):
		detail = " u%s" % str(ord["target"])
	var suffix := " DRAFT" if is_draft else ""
	plate.text = "%s u%d %s%s%s" % [
		Tokens.faction_tag(pid), unit_id, verb.to_upper(), detail, suffix
	]
	plate.font_size_px = 9
	_intents_row.add_child(plate)


func _refresh_intent_arrows() -> void:
	if _intent_arrow_layer == null or council_game == null \
			or council_game.view_model == null or council_game.press == null:
		return
	for arrow in _intent_arrow_nodes:
		arrow.queue_free()
	_intent_arrow_nodes.clear()
	var vm = council_game.view_model
	for intent in council_game.press.intents:
		var unit_id := int(intent.get("unit_id", -1))
		var ord: Dictionary = intent.get("declared_order", {})
		var arrow = _make_arrow_for_order(vm, unit_id, ord, true)
		if arrow != null:
			_intent_arrow_layer.add_child(arrow)
			_intent_arrow_nodes.append(arrow)


func _make_arrow_for_order(vm, unit_id: int, ord: Dictionary,
		ghost: bool) -> Node2D:
	var src: Dictionary = vm.unit_by_id(unit_id)
	if src.is_empty():
		return null
	var src_node_id: int = int(src.get("location", -1))
	var src_tile: Dictionary = vm.tile_for_node(src_node_id)
	var src_pos := Tokens.hex_to_px(int(src_tile["q"]), int(src_tile["r"]))
	var arrow = OrderArrowScript.new()
	arrow.player_id = vm.my_player_id()
	arrow.from_pos = src_pos
	arrow.kind = String(ord.get("type", "Hold"))
	arrow.ghost = ghost
	match arrow.kind:
		"Move":
			var dest: int = int(ord.get("dest", src_node_id))
			var dt: Dictionary = vm.tile_for_node(dest)
			arrow.to_pos = Tokens.hex_to_px(int(dt["q"]), int(dt["r"]))
		"Support":
			# Resolve support arrow destination using the shared helper
			# (require_dest → declared intent → legal fallback → ring).
			var target_unit: Dictionary = vm.unit_by_id(int(ord.get("target", -1)))
			if not target_unit.is_empty():
				var target_loc: int = int(target_unit.get("location", -1))
				var hint: Dictionary = SupportArrowHintScript.resolve(vm, ord)
				if hint["dest"] >= 0:
					var dt: Dictionary = vm.tile_for_node(hint["dest"])
					if not dt.is_empty():
						arrow.to_pos = Tokens.hex_to_px(int(dt["q"]), int(dt["r"]))
						# Dim the arrow when we're guessing from legal moves.
						if hint["dim"]:
							arrow.ghost = true
						return arrow
				# No destination found — collapse to ring rendering.
				var tt: Dictionary = vm.tile_for_node(target_loc)
				if not tt.is_empty():
					arrow.from_pos = Tokens.hex_to_px(int(tt["q"]), int(tt["r"]))
					arrow.to_pos = arrow.from_pos
		"Hold":
			arrow.to_pos = src_pos
	return arrow


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


func _on_intent_drag_proposed(from_unit_id: int, to_node_id: int) -> void:
	if council_game == null or council_game.press == null \
			or council_game.view_model == null:
		return
	var ord: Dictionary = OrderControllerScript.interpret_drag(
		council_game.view_model, from_unit_id, to_node_id,
		council_game.press.intents
	)
	if ord.is_empty():
		return
	council_game.press.add_intent(from_unit_id, ord, null)
	_render_intents(council_game.view_model)
	_refresh_intent_arrows()


func _on_unit_clicked(unit_id: int, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	if council_game == null or council_game.press == null \
			or council_game.view_model == null:
		return
	var u: Dictionary = council_game.view_model.unit_by_id(unit_id)
	if u.is_empty() or int(u.get("owner", -1)) != council_game.view_model.my_player_id():
		return
	council_game.press.remove_intent(unit_id)
	_render_intents(council_game.view_model)
	_refresh_intent_arrows()


func _on_seal_pressed() -> void:
	if council_game:
		council_game.seal_intent()
