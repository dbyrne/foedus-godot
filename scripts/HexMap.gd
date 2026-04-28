## Renders the foedus hex map from a /games/.../view payload.
##
## Reads `view.state.map.coords` (axial q,r per node), `view.state.map.node_types`,
## `view.state.ownership`, and `view.state.units`. Custom _draw() places hexes
## at axial-to-pixel positions, fills by ownership, marks node types, and
## puts circles for units.
##
## Click handling: pixel→axial conversion identifies the clicked node; emits
## `unit_clicked` if a unit is on it, else `hex_clicked` with the bare node id.
## Mouse hovering over a hex draws a highlight; hovering over a unit emits
## `unit_hovered` so the parent can show details.
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
const HEX_BORDER: Color = Color("#666")
const TEXT_COLOR: Color = Color("#ddd")
const NODE_LABEL_COLOR: Color = Color("#999")
const SELECT_RING: Color = Color("#ffe25b")
const HOVER_RING: Color = Color("#ffffff")
const HOME_MARKER: Color = Color(1, 1, 1, 0.85)
const SUPPLY_MARKER: Color = Color(1, 1, 1, 0.55)


static func player_color(p: Variant) -> Color:
	if p == null:
		return NEUTRAL_COLOR
	var pid: int = int(p)
	if pid < 0:
		return NEUTRAL_COLOR
	return PLAYER_COLORS[pid % PLAYER_COLORS.size()]


signal hex_clicked(node_id: int)
signal unit_clicked(unit_id: int, owner: int)

const ANIMATION_DURATION_MS: int = 500
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 2.5
const ZOOM_STEP: float = 1.10

var view_data: Dictionary = {}
var selected_unit_id: int = -1
var hover_node_id: int = -1
# Local pending orders awaiting submit; str(unit_id) -> order dict.
var pending_orders: Dictionary = {}
# In-flight movement animations after a turn resolves.
# str(unit_id) -> {from: Vector2(q,r), to: Vector2(q,r), started_at: int(ms)}
var _anim_starts: Dictionary = {}

# Zoom + pan state. All hex math goes through _axial_to_pixel /
# _pixel_to_axial so the same offsets apply to drawing AND hit-testing.
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var _panning: bool = false

# Cache: node_id (int) -> Vector2(q, r). Rebuilt on update_view.
var _coords_by_node: Dictionary = {}
# Cache: (q, r) -> node_id, for fast pixel→node lookup.
var _node_by_qr: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


# --- public ----------------------------------------------------------------


func update_view(view: Dictionary) -> void:
	# Diff units against previous view to start movement animations.
	_anim_starts = _compute_movement_anims(view_data, view)
	# When the game changes (different game_id), recenter.
	var prev_game: String = str(view_data.get("game_id", ""))
	var new_game: String = str(view.get("game_id", ""))
	if prev_game != new_game:
		reset_view_transform()
	view_data = view
	_rebuild_caches()
	queue_redraw()


func reset_view_transform() -> void:
	zoom = 1.0
	pan_offset = Vector2.ZERO
	queue_redraw()


func _compute_movement_anims(prev_view: Dictionary,
		new_view: Dictionary) -> Dictionary:
	if prev_view.is_empty():
		return {}
	var prev_state: Dictionary = prev_view.get("state", {})
	var new_state: Dictionary = new_view.get("state", {})
	var prev_units: Dictionary = prev_state.get("units", {})
	var new_units: Dictionary = new_state.get("units", {})
	var prev_coords: Dictionary = prev_state.get("map", {}).get("coords", {})
	var new_coords: Dictionary = new_state.get("map", {}).get("coords", {})
	var now: int = Time.get_ticks_msec()
	var anims: Dictionary = {}
	for uid in new_units:
		if not prev_units.has(uid):
			continue  # newly built — no animation
		var old_loc: int = int(prev_units[uid]["location"])
		var new_loc: int = int(new_units[uid]["location"])
		if old_loc == new_loc:
			continue  # no movement
		var src_qr: Variant = prev_coords.get(str(old_loc))
		var dst_qr: Variant = new_coords.get(str(new_loc))
		if src_qr == null or dst_qr == null:
			continue
		anims[uid] = {
			"from": Vector2(src_qr[0], src_qr[1]),
			"to": Vector2(dst_qr[0], dst_qr[1]),
			"started_at": now,
		}
	return anims


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


# --- hover tracking --------------------------------------------------------


func _process(_delta: float) -> void:
	if view_data.is_empty():
		if hover_node_id != -1:
			hover_node_id = -1
			queue_redraw()
		return
	var local: Vector2 = get_local_mouse_position()
	var inside: bool = Rect2(Vector2.ZERO, size).has_point(local)
	var new_hover: int = -1
	if inside:
		var origin: Vector2 = size / 2.0
		var qr: Vector2i = _pixel_to_axial(local - origin)
		new_hover = _node_at_qr(qr.x, qr.y)
	if new_hover != hover_node_id:
		hover_node_id = new_hover
		queue_redraw()
	# Active movement animations: redraw every frame, prune finished ones.
	if not _anim_starts.is_empty():
		var now: int = Time.get_ticks_msec()
		var done: Array = []
		for uid in _anim_starts:
			if now - int(_anim_starts[uid]["started_at"]) >= ANIMATION_DURATION_MS:
				done.append(uid)
		for uid in done:
			_anim_starts.erase(uid)
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
			player_color(owner_v) if owner_v != null else NEUTRAL_COLOR
		)
		draw_polygon(corners, [fill])
		draw_polyline(_close_loop(corners), HEX_BORDER, 1.5)

		var nt: String = str(node_types.get(node_id_str, "plain"))
		if nt == "home":
			draw_circle(px, HEX_SIZE * zoom * 0.34, HOME_MARKER)
			draw_arc(px, HEX_SIZE * zoom * 0.34, 0.0, TAU, 28, Color.BLACK, 1.0)
		elif nt == "supply":
			draw_circle(px, HEX_SIZE * zoom * 0.20, SUPPLY_MARKER)

		# Node id label, top-left of hex
		draw_string(font, px + Vector2(-HEX_SIZE * zoom * 0.55, -HEX_SIZE * zoom * 0.55),
				node_id_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, NODE_LABEL_COLOR)

	# Hover highlight (drawn after hexes, before units)
	if hover_node_id >= 0 and _coords_by_node.has(hover_node_id):
		var hqr: Vector2 = _coords_by_node[hover_node_id]
		var hpx: Vector2 = _axial_to_pixel(hqr.x, hqr.y, origin)
		var hcorners := _hex_corners(hpx)
		draw_polyline(_close_loop(hcorners), HOVER_RING, 2.5)

	# Units (drawn after hexes so they sit on top)
	for unit_id_str in units:
		var u: Dictionary = units[unit_id_str]
		var loc_str: String = str(u["location"])
		if not coords.has(loc_str):
			continue
		var px2: Vector2
		var anim: Variant = _anim_starts.get(unit_id_str)
		if anim != null:
			var elapsed: int = Time.get_ticks_msec() - int(anim["started_at"])
			var t: float = clampf(
					float(elapsed) / float(ANIMATION_DURATION_MS), 0.0, 1.0)
			# Ease-out cubic so the unit decelerates into its destination.
			t = 1.0 - pow(1.0 - t, 3.0)
			var from_qr: Vector2 = anim["from"]
			var to_qr: Vector2 = anim["to"]
			var from_px: Vector2 = _axial_to_pixel(from_qr.x, from_qr.y, origin)
			var to_px: Vector2 = _axial_to_pixel(to_qr.x, to_qr.y, origin)
			px2 = from_px.lerp(to_px, t)
		else:
			var qr2: Array = coords[loc_str]
			px2 = _axial_to_pixel(qr2[0], qr2[1], origin)
		var ucolor: Color = player_color(u["owner"])

		# Slightly larger, with white outline + dark inner ring for contrast.
		draw_circle(px2, HEX_SIZE * zoom * 0.34, ucolor)
		draw_arc(px2, HEX_SIZE * zoom * 0.34, 0.0, TAU, 32, Color.WHITE, 2.0)
		draw_arc(px2, HEX_SIZE * zoom * 0.34, 0.0, TAU, 32, Color(0, 0, 0, 0.4), 1.0)
		# Unit id text — centered, white with black shadow for readability.
		var label: String = "u%d" % int(u["id"])
		var tx: float = -HEX_SIZE * zoom * 0.18
		var ty: float = HEX_SIZE * zoom * 0.13
		draw_string(font, px2 + Vector2(tx + 1, ty + 1),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.7))
		draw_string(font, px2 + Vector2(tx, ty),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

		if int(u["id"]) == selected_unit_id:
			draw_arc(px2, HEX_SIZE * zoom * 0.45, 0.0, TAU, 36, SELECT_RING, 3.5)

	# Pending-order overlays.
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
			draw_arc(src_px, HEX_SIZE * zoom * 0.55, 0.0, TAU, 36, SELECT_RING, 2.0)
		elif t == "SupportHold":
			# Line from supporter to target unit's hex.
			var target_uid: int = int(order.get("target", -1))
			var target_data: Dictionary = units.get(str(target_uid), {})
			if target_data.is_empty():
				continue
			var target_qr: Array = coords[str(target_data["location"])]
			var target_px: Vector2 = _axial_to_pixel(target_qr[0], target_qr[1], origin)
			_draw_dashed_line(src_px, target_px, SELECT_RING)
		elif t == "SupportMove":
			# Line from supporter to target_dest, marked at the supporter side.
			var tgt_dest_id: int = int(order.get("target_dest", -1))
			if not coords.has(str(tgt_dest_id)):
				continue
			var tgt_qr: Array = coords[str(tgt_dest_id)]
			var tgt_px: Vector2 = _axial_to_pixel(tgt_qr[0], tgt_qr[1], origin)
			_draw_dashed_line(src_px, tgt_px, SELECT_RING)
			draw_arc(src_px, HEX_SIZE * zoom * 0.55, 0.0, TAU, 36, SELECT_RING, 1.5)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2 = (to - from).normalized()
	var src: Vector2 = from + dir * (HEX_SIZE * zoom * 0.36)
	var dst: Vector2 = to - dir * (HEX_SIZE * zoom * 0.36)
	draw_line(src, dst, color, 3.0)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_a: Vector2 = dst - dir * 11.0 + perp * 6.0
	var head_b: Vector2 = dst - dir * 11.0 - perp * 6.0
	draw_line(dst, head_a, color, 3.0)
	draw_line(dst, head_b, color, 3.0)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2 = (to - from).normalized()
	var distance: float = from.distance_to(to)
	var src: Vector2 = from + dir * (HEX_SIZE * zoom * 0.36)
	var dst: Vector2 = to - dir * (HEX_SIZE * zoom * 0.36)
	var avail: float = src.distance_to(dst)
	var dash: float = 7.0
	var gap: float = 5.0
	var step: float = dash + gap
	var n: int = int(avail / step)
	for i in range(n):
		var a: Vector2 = src + dir * (i * step)
		var b: Vector2 = a + dir * dash
		draw_line(a, b, color, 2.0)


func _draw_placeholder() -> void:
	var font: Font = ThemeDB.fallback_font
	var msg := "(no game — use the form above to create one)"
	draw_string(font, size / 2.0 - Vector2(msg.length() * 4.0, 0),
			msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)


# --- input -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	# --- mouse wheel zoom (centered on cursor) ---
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, ZOOM_STEP)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			return
		# Middle-button (or right-button) drag panning.
		if mb.button_index == MOUSE_BUTTON_MIDDLE \
				or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			return
		# Left-click hex/unit selection (existing behavior).
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
		return

	# --- panning while held ---
	if event is InputEventMouseMotion and _panning:
		var mm: InputEventMouseMotion = event
		pan_offset += mm.relative
		queue_redraw()


func _zoom_at(focus_pos: Vector2, factor: float) -> void:
	# Keep `focus_pos` (in widget coords) stable across the zoom by adjusting
	# pan_offset. Forward transform: pixel = origin + pan + zoom * hex_offset.
	var origin: Vector2 = size / 2.0
	var hex_off: Vector2 = (focus_pos - origin - pan_offset)
	var new_zoom: float = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom):
		return
	# After zoom change, hex_off scales by (new_zoom / zoom). Cancel that
	# scaling on focus_pos by adjusting pan.
	pan_offset += hex_off - hex_off * (new_zoom / zoom)
	zoom = new_zoom
	queue_redraw()


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


func _axial_to_pixel(q: float, r: float, origin: Vector2) -> Vector2:
	var s: float = HEX_SIZE * zoom
	var x: float = SQRT3 * (q + r / 2.0) * s
	var y: float = 1.5 * r * s
	return origin + pan_offset + Vector2(x, y)


func _pixel_to_axial(local: Vector2) -> Vector2i:
	# `local` is widget-coords-minus-origin; account for pan + zoom.
	var s: float = HEX_SIZE * zoom
	var p: Vector2 = local - pan_offset
	var q_frac: float = (SQRT3 / 3.0 * p.x - 1.0 / 3.0 * p.y) / s
	var r_frac: float = (2.0 / 3.0 * p.y) / s
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
	var pts := PackedVector2Array()
	var s: float = HEX_SIZE * zoom
	for i in range(6):
		var ang: float = (i + 0.5) * PI / 3.0
		pts.append(center + Vector2(s * cos(ang), s * sin(ang)))
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
