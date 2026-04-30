extends Control
##
## Orders screen — drag-from-piece order entry.
##
## Layout mirrors Negotiation:
##   - TensionMeter (top, ember/blood color in this phase)
##   - WAR TABLE label + HexBoard (left); rendered with queued
##     OrderArrows over the unit positions
##   - OrdersPanel (right rail) with Submit / Reset
##   - DECLARED INTENTS row at bottom (read-only context from press)
##
## Drag-gesture flow:
##   1. HexBoard emits drag_proposed(from_unit_id, to_node_id) on drop.
##   2. We call OrderController.interpret_drag to map gesture → Order.
##   3. If a legal Order matched, OrderController.propose_order(uid, ord).
##   4. OrdersPanel.updated → repopulates queued list.
##   5. _refresh_arrows redraws OrderArrows for every queued order.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const ShellScript        = preload("res://components/CouncilShell.gd")
const HexBoardScript     = preload("res://components/HexBoard.gd")
const OrdersPanelScript  = preload("res://components/OrdersPanel.gd")
const TensionScript      = preload("res://components/TensionMeter.gd")
const BrassPlateScript   = preload("res://components/BrassPlate.gd")
const OrderArrowScript   = preload("res://components/OrderArrow.gd")
const OrderControllerScript = preload("res://scripts/council/OrderController.gd")
const ViewModelScript    = preload("res://scripts/council/ViewModel.gd")

var council_game: Node = null
var order_controller = null  # OrderController; created on attach_game

var _shell: Node = null
var _hex_board: Node = null
var _panel: Node = null
var _tension: Node = null
var _intents_row: HBoxContainer
var _root_layer: Control = null
var _arrow_layer: Node2D = null
var _arrow_nodes: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game
	if order_controller == null:
		order_controller = OrderControllerScript.new()
	if council_game.has_signal("view_changed"):
		council_game.view_changed.connect(_on_view_changed)
	if council_game.view_model != null:
		_on_view_changed(council_game.view_model)


func _build_layout() -> void:
	_shell = ShellScript.new()
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shell)

	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root_layer)

	_tension = TensionScript.new()
	_tension.position = Vector2(60, 50)
	_tension.custom_minimum_size = Vector2(1160, 36)
	_tension.size = Vector2(1160, 36)
	_tension.phase = "orders"
	_root_layer.add_child(_tension)

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
	_hex_board.drag_proposed.connect(_on_drag_proposed)
	_hex_board.tile_clicked.connect(_on_tile_clicked)
	_hex_board.unit_clicked.connect(_on_unit_clicked)

	# Arrow layer — Node2D sibling of HexBoard, draws OrderArrows in
	# the same coordinate space (same parent + same position).
	_arrow_layer = Node2D.new()
	_arrow_layer.position = _hex_board.position
	board_wrap.add_child(_arrow_layer)

	_panel = OrdersPanelScript.new()
	_panel.position = Vector2(700, 100)
	_panel.size = Vector2(540, 700)
	_root_layer.add_child(_panel)
	_panel.submit_pressed.connect(_on_submit)
	_panel.reset_pressed.connect(_on_reset)
	_panel.remove_order_pressed.connect(_on_remove_order)

	# Declared intents row — context only, not interactive in 2b.
	var intents_label = BrassPlateScript.new()
	intents_label.text = "DECLARED INTENTS (locked)"
	intents_label.font_size_px = 11
	intents_label.position = Vector2(60, 700)
	_root_layer.add_child(intents_label)
	_intents_row = HBoxContainer.new()
	_intents_row.position = Vector2(60, 732)
	_intents_row.size = Vector2(620, 60)
	_intents_row.add_theme_constant_override("separation", 12)
	_root_layer.add_child(_intents_row)


func _on_view_changed(vm) -> void:
	if vm == null:
		return
	if _hex_board == null or _panel == null or _tension == null:
		call_deferred("_on_view_changed", vm)
		return
	_hex_board.set_view_model(vm)
	_panel.set_view_model(vm)
	_panel.set_order_controller(order_controller)
	_tension.phase = "orders"
	_tension.timer_text = "T %d / %d" % [vm.turn(), vm.max_turns()]
	var tt := float(vm.max_turns())
	_tension.value = (float(vm.turn()) / tt) if tt > 0 else 0.0
	_render_intents(vm)
	_refresh_arrows()


func _render_intents(vm) -> void:
	for c in _intents_row.get_children():
		c.queue_free()
	for intent in vm.declared_intents():
		var plate = BrassPlateScript.new()
		var pid := int(intent.get("player_id", -1))
		var unit_id := int(intent.get("unit_id", -1))
		var ord = intent.get("declared_order", {})
		var kind := String(ord.get("type", "?"))
		plate.text = "%s u%d %s" % [Tokens.faction_tag(pid), unit_id, kind.to_upper()]
		plate.font_size_px = 9
		_intents_row.add_child(plate)


func _refresh_arrows() -> void:
	if _arrow_layer == null or order_controller == null or council_game == null \
			or council_game.view_model == null:
		return
	for a in _arrow_nodes:
		a.queue_free()
	_arrow_nodes.clear()
	var vm = council_game.view_model
	for uid in order_controller.orders.keys():
		var unit_id: int = int(uid)
		var src: Dictionary = vm.unit_by_id(unit_id)
		if src.is_empty():
			continue
		var src_node_id: int = int(src.get("location", -1))
		var src_tile: Dictionary = vm.tile_for_node(src_node_id)
		var src_pos: Vector2 = Tokens.hex_to_px(int(src_tile["q"]), int(src_tile["r"]))
		var ord: Dictionary = order_controller.orders[unit_id]
		var arrow = OrderArrowScript.new()
		arrow.player_id = vm.my_player_id()
		arrow.from_pos = src_pos
		arrow.kind = String(ord.get("type", "Hold"))
		match arrow.kind:
			"Move":
				var dest: int = int(ord.get("dest", src_node_id))
				var dt: Dictionary = vm.tile_for_node(dest)
				arrow.to_pos = Tokens.hex_to_px(int(dt["q"]), int(dt["r"]))
			"SupportHold":
				var t: Dictionary = vm.unit_by_id(int(ord.get("target", -1)))
				if not t.is_empty():
					var tt2: Dictionary = vm.tile_for_node(int(t["location"]))
					arrow.to_pos = Tokens.hex_to_px(int(tt2["q"]), int(tt2["r"]))
			"SupportMove":
				var dest2: int = int(ord.get("target_dest", -1))
				var dt2: Dictionary = vm.tile_for_node(dest2)
				arrow.from_pos = src_pos
				arrow.to_pos = Tokens.hex_to_px(int(dt2["q"]), int(dt2["r"]))
			"Hold":
				arrow.to_pos = src_pos
		_arrow_layer.add_child(arrow)
		_arrow_nodes.append(arrow)


# --- Signal handlers ----------------------------------------------------

func _on_drag_proposed(from_unit_id: int, to_node_id: int) -> void:
	if order_controller == null or council_game == null:
		return
	var ord: Dictionary = OrderControllerScript.interpret_drag(
		council_game.view_model, from_unit_id, to_node_id
	)
	if ord.is_empty():
		# No legal order matched — silently drop the gesture.
		return
	order_controller.propose_order(from_unit_id, ord)
	_refresh_arrows()


func _on_unit_clicked(unit_id: int, button: int) -> void:
	# Right-click on an own unit cancels its queued order.
	if button == MOUSE_BUTTON_RIGHT and council_game and council_game.view_model:
		var u: Dictionary = council_game.view_model.unit_by_id(unit_id)
		if not u.is_empty() and int(u.get("owner", -1)) == council_game.view_model.my_player_id():
			order_controller.remove_order(unit_id)
			_refresh_arrows()


func _on_tile_clicked(node_id: int, button: int) -> void:
	# Currently no special handling beyond unit_clicked above.
	pass


func _on_submit() -> void:
	if council_game == null or order_controller == null:
		return
	council_game.submit_orders(order_controller.to_orders_payload())


func _on_reset() -> void:
	if order_controller != null:
		order_controller.clear()
		_refresh_arrows()


func _on_remove_order(unit_id: int) -> void:
	if order_controller != null:
		order_controller.remove_order(unit_id)
		_refresh_arrows()
