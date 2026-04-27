## Renders the foedus hex map from a /games/.../view payload.
##
## Reads `view.state.map.coords` (axial q,r per node), `view.state.map.node_types`,
## `view.state.ownership`, and `view.state.units`. Custom _draw() places hexes
## at axial-to-pixel positions, fills by ownership, marks node types, and
## puts circles for units.
##
## Click handling: pixel→axial conversion identifies the clicked node; emits
## `unit_clicked` if a unit is on it (your unit or theirs), else `hex_clicked`
## with the bare node id. Main.gd decides what to do (select-then-target).
class_name HexMap
extends Control

const HEX_SIZE: float = 38.0
const SQRT3: float = 1.7320508075688772

# 6 player colors; cycles for higher seat counts.
const PLAYER_COLORS: Array[Color] = [
	Color("#5b8def"),  # 0  blue
	Color("#e3534b"),  # 1  red
	Color("#5cb87a"),  # 2  green
	Color("#d9b14a"),  # 3  yellow
	Color("#9e6cb1"),  # 4  purple
	Color("#dd8e3b"),  # 5  orange
]
const NEUTRAL_COLOR: Color = Color("#2a2a2a")
const HEX_BORDER: Color = Color("#888")
const TEXT_COLOR: Color = Color("#bbb")
const SELECT_RING: Color = Color("#ffe25b")

signal hex_clicked(node_id: int)
signal unit_clicked(unit_id: int, owner: int)

var view_data: Dictionary = {}
var selected_unit_id: int = -1
# Local pending orders awaiting submit; str(unit_id) -> order dict.
var pending_orders: Dictionary = {}

# Cache: node_id (int) -> Vector2(q, r). Rebuilt on update_view.
var _coords_by_node: Dictionary = {}
# Cache: (q, r) -> node_id, for fast pixel→node lookup.
var _node_by_qr: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP


# --- public ----------------------------------------------------------------


func update_view(view: Dictionary) -> void:
	view_data = view
	_rebuild_caches()
	queue_redraw()


func clear_selection() -> void:
	if selected_unit_id != -1:
		selected_unit_id = -1
		queue_redraw()


func select_unit(unit_id: int) -> void:
	selected_unit_id = unit_id
	queue_redraw()


func set_pending_orders(orders: Dictionary) -> void:
	pending_orders = orders.duplicate()
	queue_redraw()


# --- drawing ---------------------------------------------------------------


func _draw() -> void:
	if view_data.is_empty():
		_draw_placeholder()
		return

	var origin: Vector2 = size / 2.0
	var state: Dictionary = view_data.get("state", {})
	var map_data: Dictionary = state.get("map", {})
	var coords: Dictionary = map_data.get("coords", {})
	var node_types: Dictionary = map_data.get("node_types", {})
	var ownership: Dictionary = state.get("ownership", {})
	var units: Dictionary = state.get("units", {})
	var font: Font = ThemeDB.fallback_font

	# Hexes
	for node_id_str in coords:
		var qr: Array = coords[node_id_str]
		var px: Vector2 = _axial_to_pixel(qr[0], qr[1], origin)
		var corners := _hex_corners(px)

		var owner_v: Variant = ownership.get(node_id_str)
		var fill: Color = (
			_player_color(owner_v) if owner_v != null else NEUTRAL_COLOR
		)
		draw_polygon(corners, [fill])
		draw_polyline(_close_loop(corners), HEX_BORDER, 1.0)

		var nt: String = str(node_types.get(node_id_str, "plain"))
		if nt == "home":
			draw_circle(px, HEX_SIZE * 0.32, Color(1, 1, 1, 0.85))
		elif nt == "supply":
			draw_circle(px, HEX_SIZE * 0.18, Color(1, 1, 1, 0.85))

		# Node id label, top-left of hex
		draw_string(font, px + Vector2(-HEX_SIZE * 0.55, -HEX_SIZE * 0.55),
				node_id_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)

	# Units (drawn after hexes so they sit on top)
	for unit_id_str in units:
		var u: Dictionary = units[unit_id_str]
		var loc_str: String = str(u["location"])
		if not coords.has(loc_str):
			continue
		var qr2: Array = coords[loc_str]
		var px2: Vector2 = _axial_to_pixel(qr2[0], qr2[1], origin)
		var ucolor: Color = _player_color(u["owner"])

		draw_circle(px2, HEX_SIZE * 0.30, ucolor)
		draw_arc(px2, HEX_SIZE * 0.30, 0.0, TAU, 28, Color.BLACK, 1.5)
		draw_string(font, px2 + Vector2(-HEX_SIZE * 0.18, HEX_SIZE * 0.10),
				"u%d" % int(u["id"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

		if int(u["id"]) == selected_unit_id:
			draw_arc(px2, HEX_SIZE * 0.42, 0.0, TAU, 36, SELECT_RING, 3.0)

	# Pending-order overlays: a thin line from source to destination per
	# pending Move; a small ring on the source for pending Hold.
	for unit_id_str in pending_orders:
		var order: Dictionary = pending_orders[unit_id_str]
		var u_data: Dictionary = units.get(unit_id_str, {})
		if u_data.is_empty():
			continue
		var src_loc_str: String = str(u_data["location"])
		if not coords.has(src_loc_str):
			continue
		var src_qr: Array = coords[src_loc_str]
		var src_px: Vector2 = _axial_to_pixel(src_qr[0], src_qr[1], origin)
		var t: String = str(order.get("type", ""))
		if t == "Move":
			var dest_id: int = int(order.get("dest", -1))
			var dest_str: String = str(dest_id)
			if not coords.has(dest_str):
				continue
			var dest_qr: Array = coords[dest_str]
			var dest_px: Vector2 = _axial_to_pixel(dest_qr[0], dest_qr[1], origin)
			_draw_arrow(src_px, dest_px, SELECT_RING)
		elif t == "Hold":
			draw_arc(src_px, HEX_SIZE * 0.50, 0.0, TAU, 36, SELECT_RING, 2.0)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	# Pull endpoints in a bit so arrows don't collide with unit circles.
	var dir: Vector2 = (to - from).normalized()
	var src: Vector2 = from + dir * (HEX_SIZE * 0.32)
	var dst: Vector2 = to - dir * (HEX_SIZE * 0.32)
	draw_line(src, dst, color, 2.5)
	# Arrowhead.
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_a: Vector2 = dst - dir * 10.0 + perp * 5.0
	var head_b: Vector2 = dst - dir * 10.0 - perp * 5.0
	draw_line(dst, head_a, color, 2.5)
	draw_line(dst, head_b, color, 2.5)


func _draw_placeholder() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, size / 2.0 - Vector2(40, 0),
			"(no game)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)


# --- input -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if view_data.is_empty():
		return
	var origin: Vector2 = size / 2.0
	var local: Vector2 = mb.position - origin
	var qr: Vector2i = _pixel_to_axial(local)
	var node_id: int = _node_at_qr(qr.x, qr.y)
	if node_id < 0:
		return

	var unit_id: int = _unit_at_node(node_id)
	if unit_id >= 0:
		var u: Dictionary = view_data["state"]["units"][str(unit_id)]
		unit_clicked.emit(unit_id, int(u["owner"]))
	else:
		hex_clicked.emit(node_id)


# --- helpers ---------------------------------------------------------------


func _rebuild_caches() -> void:
	_coords_by_node.clear()
	_node_by_qr.clear()
	if view_data.is_empty():
		return
	var coords: Dictionary = view_data.get("state", {}).get("map", {}).get("coords", {})
	for node_id_str in coords:
		var qr: Array = coords[node_id_str]
		var nid: int = int(node_id_str)
		_coords_by_node[nid] = Vector2(qr[0], qr[1])
		_node_by_qr[Vector2i(qr[0], qr[1])] = nid


func _player_color(p: Variant) -> Color:
	if p == null:
		return NEUTRAL_COLOR
	var pid: int = int(p)
	if pid < 0:
		return NEUTRAL_COLOR
	return PLAYER_COLORS[pid % PLAYER_COLORS.size()]


func _axial_to_pixel(q: float, r: float, origin: Vector2) -> Vector2:
	# Pointy-top hex axial->pixel.
	var x: float = SQRT3 * (q + r / 2.0) * HEX_SIZE
	var y: float = 1.5 * r * HEX_SIZE
	return origin + Vector2(x, y)


func _pixel_to_axial(local: Vector2) -> Vector2i:
	# Inverse of _axial_to_pixel; rounds to the nearest hex via cube rounding.
	var q_frac: float = (SQRT3 / 3.0 * local.x - 1.0 / 3.0 * local.y) / HEX_SIZE
	var r_frac: float = (2.0 / 3.0 * local.y) / HEX_SIZE
	return _hex_round(q_frac, r_frac)


func _hex_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: int = int(round(q))
	var rr: int = int(round(r))
	var rs: int = int(round(s))
	var dq: float = abs(rq - q)
	var dr: float = abs(rr - r)
	var ds: float = abs(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)


func _hex_corners(center: Vector2) -> PackedVector2Array:
	# Pointy-top: corner i at angle (i + 0.5) * 60° from horizontal.
	var pts := PackedVector2Array()
	for i in range(6):
		var ang: float = (i + 0.5) * PI / 3.0
		pts.append(center + Vector2(HEX_SIZE * cos(ang), HEX_SIZE * sin(ang)))
	return pts


func _close_loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


func _node_at_qr(q: int, r: int) -> int:
	var v: Vector2i = Vector2i(q, r)
	return int(_node_by_qr.get(v, -1))


func _unit_at_node(node_id: int) -> int:
	var units: Dictionary = view_data.get("state", {}).get("units", {})
	for unit_id_str in units:
		var u: Dictionary = units[unit_id_str]
		if int(u["location"]) == node_id:
			return int(u["id"])
	return -1
