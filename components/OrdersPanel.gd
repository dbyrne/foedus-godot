extends Control
class_name OrdersPanel
##
## Right-rail panel for the Orders screen — replaces CourtPanel.
##
## Stacks:
##   1. BrassPlate "ORDERS" header
##   2. List of queued orders (one row per unit), each with order text +
##      a small remove (×) button
##   3. Hint label about drag-from-piece
##   4. Submit + Reset buttons
##
## Subscribes to the OrderController's `updated` signal to refresh
## the queued-orders list.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const BrassPlateScript = preload("res://components/BrassPlate.gd")

signal submit_pressed()
signal reset_pressed()
signal remove_order_pressed(unit_id: int)

var _view_model = null
var _order_controller = null
var _orders_box: VBoxContainer
var _hint_label: Label
var _submit_btn: Button
var _reset_btn: Button


func set_view_model(vm) -> void:
	_view_model = vm
	_refresh()


func set_order_controller(ctrl) -> void:
	if _order_controller != null and _order_controller.updated.is_connected(_refresh):
		_order_controller.updated.disconnect(_refresh)
	_order_controller = ctrl
	if _order_controller != null:
		_order_controller.updated.connect(_refresh)
	_refresh()


func _ready() -> void:
	custom_minimum_size = Vector2(540, 700)
	_build_structure()
	_refresh()


func _build_structure() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	var plate = BrassPlateScript.new()
	plate.text = "ORDERS"
	plate.font_size_px = 12
	v.add_child(plate)

	_hint_label = Label.new()
	_hint_label.text = "Drag from your unit:\n  • own hex → Hold\n  • adjacent hex → Move\n  • friendly unit → Support"
	_hint_label.add_theme_font_override("font", load(Tokens.FONT_SERIF_ITALIC) as Font)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Tokens.BONE_DIM)
	v.add_child(_hint_label)

	var queued_header = BrassPlateScript.new()
	queued_header.text = "QUEUED"
	queued_header.font_size_px = 10
	v.add_child(queued_header)

	_orders_box = VBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 4)
	v.add_child(_orders_box)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	# Action buttons
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	_submit_btn = _make_button("Submit Orders")
	_submit_btn.pressed.connect(func(): submit_pressed.emit())
	actions.add_child(_submit_btn)
	_reset_btn = _make_button("Reset")
	_reset_btn.pressed.connect(func(): reset_pressed.emit())
	actions.add_child(_reset_btn)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	b.add_theme_font_size_override("font_size", 12)
	return b


func _refresh() -> void:
	if not is_inside_tree() or _orders_box == null:
		return
	for c in _orders_box.get_children():
		c.queue_free()
	if _order_controller == null or _view_model == null:
		_orders_box.add_child(_orphan_label("(no orders queued)"))
		return
	if _order_controller.count() == 0:
		_orders_box.add_child(_orphan_label("(no orders queued — every unholding unit will Hold)"))
		return
	for uid in _order_controller.orders.keys():
		var ord: Dictionary = _order_controller.orders[uid]
		_orders_box.add_child(_build_order_row(int(uid), ord))


func _orphan_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(Tokens.FONT_SERIF_ITALIC) as Font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Tokens.BONE_DIM)
	return l


func _build_order_row(unit_id: int, order: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var unit: Dictionary = _view_model.unit_by_id(unit_id)
	var label := Label.new()
	var owner: int = int(unit.get("owner", _view_model.my_player_id()))
	label.text = "  %s u%d %s" % [Tokens.faction_tag(owner), unit_id,
		_describe_order(order)]
	label.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Tokens.BONE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var rm := Button.new()
	rm.text = "  ×  "
	rm.add_theme_font_override("font", load(Tokens.FONT_MONO) as Font)
	rm.add_theme_font_size_override("font_size", 14)
	rm.tooltip_text = "Cancel order (right-click on the unit also works)"
	rm.pressed.connect(func(): remove_order_pressed.emit(unit_id))
	row.add_child(rm)
	return row


func _describe_order(order: Dictionary) -> String:
	var t := String(order.get("type", "?"))
	match t:
		"Hold":
			return "Hold"
		"Move":
			return "Move → n%d" % int(order.get("dest", -1))
		"SupportHold":
			return "Support u%d Hold" % int(order.get("target", -1))
		"SupportMove":
			return "Support u%d → n%d" % [
				int(order.get("target", -1)),
				int(order.get("target_dest", -1)),
			]
		_:
			return t
