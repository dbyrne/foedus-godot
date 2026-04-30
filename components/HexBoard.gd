extends Node2D
class_name HexBoard
##
## Full hex-grid renderer driven by a ViewModel. Instantiates one
## CouncilHex per tile, positions them via Tokens.hex_to_px(q, r),
## tracks click + drag-state for order entry.
##
## Signals:
##   tile_clicked(node_id, button)             — left/right click
##   unit_clicked(unit_id, button)             — left/right click on a unit
##   drag_proposed(from_unit_id, to_node_id)   — drag from own unit released
##                                                on a tile
##
## Drag rules:
## - Mouse-down LEFT on an own unit  → start drag, remember source unit.
## - Mouse-motion while dragging     → ghost arrow drawn from source to
##                                     current pointer position.
## - Mouse-up LEFT on a tile         → emit drag_proposed; consumer
##                                     decides legality + the resulting
##                                     order kind (Move / SupportMove /
##                                     SupportHold / Hold).
## - Right-click anywhere            → tile_clicked with button=RIGHT
##                                     (used to cancel a queued order).
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const CouncilHexScript = preload("res://components/CouncilHex.gd")

signal tile_clicked(node_id: int, button: int)
signal unit_clicked(unit_id: int, button: int)
signal drag_proposed(from_unit_id: int, to_node_id: int)

var _view_model = null  # ViewModel; loose typing avoids class_name ordering
var _hex_nodes: Dictionary = {}   # node_id → CouncilHex Node2D
var _selected_unit_id: int = -1

# Drag state
var _drag_from_unit_id: int = -1
var _drag_from_pos: Vector2 = Vector2.ZERO
var _drag_current_pos: Vector2 = Vector2.ZERO
var _is_dragging: bool = false


func set_view_model(vm) -> void:
	_view_model = vm
	_rebuild()


func selected_unit_id() -> int:
	return _selected_unit_id


func set_selected_unit_id(uid: int) -> void:
	_selected_unit_id = uid
	_refresh_selection_overlay()


func _ready() -> void:
	if _view_model != null:
		_rebuild()


func _rebuild() -> void:
	# Tear down existing hexes.
	for node_id in _hex_nodes.keys():
		_hex_nodes[node_id].queue_free()
	_hex_nodes.clear()
	if _view_model == null:
		return
	# Instantiate one CouncilHex per tile.
	for tile in _view_model.tiles():
		var hex = CouncilHexScript.new()
		var hex_tile := {
			"q": tile["q"],
			"r": tile["r"],
			"terrain": _terrain_for_node_type(tile["node_type"]),
			"supply": _supply_for_tile(tile),
			"owner": tile["owner"],
			"home": tile["home_player"],
			"unit": tile["unit"],
		}
		hex.tile = hex_tile
		hex.position = Tokens.hex_to_px(tile["q"], tile["r"])
		add_child(hex)
		_hex_nodes[tile["node_id"]] = hex
	_refresh_selection_overlay()


func get_hex_node(node_id: int) -> Node2D:
	## Public accessor for the CouncilHex Node2D at a given node_id.
	## Used by Resolution playback to hide a moving unit on its source
	## hex while a ghost lerps to the destination.
	return _hex_nodes.get(node_id)


func set_unit_visible_at(node_id: int, visible: bool) -> void:
	var hex = _hex_nodes.get(node_id)
	if hex == null:
		return
	for c in hex.get_children():
		if c is Node2D:
			c.visible = visible


func _refresh_selection_overlay() -> void:
	if _view_model == null:
		return
	for node_id in _hex_nodes.keys():
		var hex = _hex_nodes[node_id]
		var t = _view_model.tile_for_node(node_id)
		var selected := false
		if _selected_unit_id >= 0 and t.get("unit") != null:
			selected = int(t["unit"]["id"]) == _selected_unit_id
		hex.selected = selected


func _terrain_for_node_type(node_type: String) -> String:
	## CouncilHex's `terrain` field uses lowercase names. The wire ships
	## node_type lowercase too (verified live), but accept either case
	## so we don't regress if the engine ever switches.
	match node_type.to_lower():
		"forest":   return "forest"
		"mountain": return "mountain"
		"water":    return "water"
		# home, supply, plain all render as the "plain" base; their
		# distinguishing markers (banner / chest) are drawn from
		# tile.home / tile.supply, not from the terrain face.
		_: return "plain"


func _supply_for_tile(tile: Dictionary) -> int:
	## CouncilHex.supply is 0 (none), 1 (regular chest), 2 (high-value crown).
	## Only supply-type nodes show a marker; homes always render their banner
	## but no supply chest even though they yield score.
	if String(tile.get("node_type", "")).to_lower() != "supply":
		return 0
	return int(tile.get("supply_value", 1))


# --- Input handling -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or _view_model == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _is_dragging:
		_drag_current_pos = to_local(event.position)
		queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var local: Vector2 = to_local(event.position)
	var hit_node_id := _node_id_at(local)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start a drag if pressing on one of our own units.
			if hit_node_id >= 0:
				var t = _view_model.tile_for_node(hit_node_id)
				var unit = t.get("unit")
				if unit != null and int(unit.get("player", -1)) == _view_model.my_player_id():
					_drag_from_unit_id = int(unit["id"])
					_drag_from_pos = _hex_nodes[hit_node_id].position
					_drag_current_pos = local
					_is_dragging = true
					queue_redraw()
					return
			# Not a drag start — just a click.
			if hit_node_id >= 0:
				_emit_click(hit_node_id, MOUSE_BUTTON_LEFT)
		else:
			# Mouse released. If we were dragging, propose an order.
			if _is_dragging:
				_is_dragging = false
				if hit_node_id >= 0 and _drag_from_unit_id >= 0:
					drag_proposed.emit(_drag_from_unit_id, hit_node_id)
				_drag_from_unit_id = -1
				queue_redraw()
				return
			if hit_node_id >= 0:
				# Treat unconsumed mouse-up as click for non-own units
				# (clicking an opponent unit, etc).
				pass
	elif event.pressed:
		# Right or middle click.
		if hit_node_id >= 0:
			_emit_click(hit_node_id, event.button_index)


func _emit_click(node_id: int, button: int) -> void:
	var t = _view_model.tile_for_node(node_id)
	var unit = t.get("unit")
	if unit != null:
		unit_clicked.emit(int(unit["id"]), button)
	tile_clicked.emit(node_id, button)


func _draw() -> void:
	# Ghost arrow during drag — drawn over the hex grid.
	if _is_dragging and _drag_from_unit_id >= 0:
		var color := Tokens.player_main(_view_model.my_player_id())
		color = Color(color.r, color.g, color.b, 0.65)
		var dir := (_drag_current_pos - _drag_from_pos).normalized()
		var inset := 14.0
		if _drag_from_pos.distance_to(_drag_current_pos) < inset:
			return
		var p_from := _drag_from_pos + dir * inset
		var p_to := _drag_current_pos
		draw_line(p_from, p_to, color, 3.0)
		var perp := Vector2(-dir.y, dir.x)
		var head_len := 11.0
		var head_w := 6.5
		var head := PackedVector2Array([
			p_to,
			p_to - dir * head_len + perp * head_w,
			p_to - dir * head_len - perp * head_w,
		])
		draw_colored_polygon(head, color)


func _node_id_at(local_point: Vector2) -> int:
	## Point-in-hexagon hit-test. Iterates hexes whose centers are
	## within bounding distance, then checks the actual pointy-top
	## hexagon shape. Drag-from-piece order entry (Phase 2b) needs
	## accurate edge hits, which a nearest-neighbor approximation
	## couldn't deliver.
	var bound: float = float(Tokens.HEX_R) * 1.2
	for node_id in _hex_nodes.keys():
		var hex = _hex_nodes[node_id]
		var d: float = local_point.distance_to(hex.position)
		if d > bound:
			continue
		if _point_in_pointy_hex(local_point - hex.position, float(Tokens.HEX_R)):
			return node_id
	return -1


static func _point_in_pointy_hex(p: Vector2, r: float) -> bool:
	## Pointy-top hex centered at origin: width = sqrt(3) * r along x,
	## height = 2 * r along y. Test by combining the bounding box with
	## the diagonal edge constraint.
	var w: float = r * sqrt(3.0)
	var ax: float = abs(p.x)
	var ay: float = abs(p.y)
	if ax > w * 0.5:
		return false
	if ay > r:
		return false
	# The hex's diagonal edge runs from (w/2, r/2) to (0, r). The
	# point is inside iff ay ≤ r - (ax / (w/2)) * (r/2) = r * (1 - ax/w).
	return ay <= r * (1.0 - ax / w)
