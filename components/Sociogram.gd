extends Control
class_name Sociogram
##
## Relations panel — replaces the v0 4×4 trust grid.
##
## Renders four Crests at the corners of a rounded rectangle, with
## directed arcs between every ordered pair showing leverage and
## stance. The arc's stroke width scales with |leverage|; the color
## tints toward the stance (ally/neutral/hostile); an arrowhead points
## toward the *creditor* (the player owed).
##
## Click on a crest emits `crest_clicked(player_id)` — Pairwise dossier
## (Phase 2d) subscribes.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const CrestScript = preload("res://components/Crest.gd")

signal crest_clicked(player_id: int)

var _view_model = null  # ViewModel
var _crests: Array = []  # Crest controls indexed by player_id
var _crest_centers: Array = []  # Vector2 in local coords, parallel to _crests


func set_view_model(vm) -> void:
	_view_model = vm
	_rebuild_crests()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(500, 220)
	if _view_model != null:
		_rebuild_crests()


func _rebuild_crests() -> void:
	if _view_model == null:
		return
	for c in _crests:
		c.queue_free()
	_crests.clear()
	_crest_centers.clear()
	var n: int = int(_view_model.num_players())
	if n != 4:
		# Sociogram is hard-coded for 4-player layouts in Phase 2a.
		# Generalize in Phase 3 when 2/3-player support lands.
		push_warning("Sociogram expects 4 players; got %d" % n)
		return
	# Square corners — top-left = my player, then clockwise around.
	var me: int = int(_view_model.my_player_id())
	var positions := _layout_positions()
	for slot in 4:
		var pid: int = (me + slot) % n
		var crest = CrestScript.new()
		crest.player_id = pid
		crest.crest_size = 56
		crest.position = positions[slot] - Vector2(28, 32)  # center on slot
		crest.mouse_filter = Control.MOUSE_FILTER_PASS
		crest.gui_input.connect(_on_crest_input.bind(pid))
		add_child(crest)
		_crests.append(crest)
		_crest_centers.append(positions[slot])


func _layout_positions() -> Array:
	# Square layout inside the panel, with margin so arcs have room to bend.
	var w := size.x if size.x > 0 else 500.0
	var h := size.y if size.y > 0 else 220.0
	var mx := w * 0.20
	var my := h * 0.18
	return [
		Vector2(mx, my),                # 0 = me, top-left
		Vector2(w - mx, my),            # 1 = clockwise next, top-right
		Vector2(w - mx, h - my),        # 2 = bottom-right
		Vector2(mx, h - my),            # 3 = bottom-left
	]


func _on_crest_input(event: InputEvent, pid: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		crest_clicked.emit(pid)


# --- Drawing ------------------------------------------------------------

func _draw() -> void:
	if _view_model == null or _crests.size() != 4:
		return

	# Re-layout if size changed since last build (the panel may resize
	# inside its parent container).
	var positions := _layout_positions()
	for i in 4:
		_crest_centers[i] = positions[i]
		_crests[i].position = positions[i] - Vector2(28, 32)

	# Background plate
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35), true)
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.BRASS_DIM, false, 1.0)

	# For each ordered pair, draw an arc with leverage/stance encoding.
	# We have 4 players → 12 ordered pairs. To avoid visual clutter we
	# render only the direction with positive leverage, plus a neutral
	# line for pairs with zero leverage.
	var me: int = int(_view_model.my_player_id())
	var n: int = int(_view_model.num_players())
	var seen_unordered: Dictionary = {}
	for slot_a in 4:
		for slot_b in 4:
			if slot_a == slot_b:
				continue
			var key := str(min(slot_a, slot_b)) + "-" + str(max(slot_a, slot_b))
			if seen_unordered.has(key):
				continue
			seen_unordered[key] = true
			var pid_a: int = (me + slot_a) % n
			var pid_b: int = (me + slot_b) % n
			_draw_pair_arc(slot_a, slot_b, pid_a, pid_b)


func _draw_pair_arc(slot_a: int, slot_b: int, pid_a: int, pid_b: int) -> void:
	var lev_a_to_b: int = int(_view_model.leverage(pid_a, pid_b))
	var creditor_pid: int
	var creditor_slot: int
	var debtor_slot: int
	if lev_a_to_b > 0:
		creditor_pid = pid_a; creditor_slot = slot_a; debtor_slot = slot_b
	elif lev_a_to_b < 0:
		creditor_pid = pid_b; creditor_slot = slot_b; debtor_slot = slot_a
	else:
		creditor_pid = -1; creditor_slot = slot_a; debtor_slot = slot_b
	var lev_mag: int = abs(lev_a_to_b)

	# Tint toward stance — use the more hostile of the two directions
	# so a one-sided hostility shows as red.
	var stance_color := _stance_color_pair(pid_a, pid_b)

	# Width: scaled with |leverage|, clamped.
	var width: float = 1.5 + clamp(float(lev_mag) * 0.8, 0.0, 4.5)

	var p_from: Vector2 = _crest_centers[debtor_slot]
	var p_to: Vector2 = _crest_centers[creditor_slot]
	# Curve via a midpoint pulled toward panel center for visual interest.
	var center: Vector2 = size * 0.5
	var mid: Vector2 = p_from.lerp(p_to, 0.5).lerp(center, 0.20)

	# Sample bezier
	var pts := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		var u := 1.0 - t
		var p: Vector2 = u * u * p_from + 2.0 * u * t * mid + t * t * p_to
		pts.append(p)
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], stance_color, width)

	# Arrowhead at creditor end (skip if leverage is zero).
	if creditor_pid >= 0:
		var p_tip := pts[pts.size() - 1]
		var p_pre := pts[pts.size() - 4]
		var dir := (p_tip - p_pre).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var head_len: float = 8.0 + width * 0.6
		var head_w: float = 4.0 + width * 0.5
		var head := PackedVector2Array([
			p_tip,
			p_tip - dir * head_len + perp * head_w,
			p_tip - dir * head_len - perp * head_w,
		])
		draw_colored_polygon(head, stance_color)

	# Label at midpoint.
	var label_text: String
	if lev_mag == 0:
		label_text = "even"
	else:
		label_text = "leverage +%d" % lev_mag
	var f := load(Tokens.FONT_SERIF_ITALIC) as Font
	if f != null:
		var fsize := 11
		var ts := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var label_pos: Vector2 = mid + Vector2(-ts.x * 0.5, -6)
		draw_string(f, label_pos, label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Tokens.BONE_DIM)


func _stance_color_pair(pid_a: int, pid_b: int) -> Color:
	## Use the most-hostile direction so one-sided enmity reads.
	var s_ab: String = String(_view_model.stance(pid_a, pid_b))
	var s_ba: String = String(_view_model.stance(pid_b, pid_a))
	if s_ab == "hostile" or s_ba == "hostile":
		return Color(Tokens.BLOOD.r, Tokens.BLOOD.g, Tokens.BLOOD.b, 0.85)
	if s_ab == "ally" and s_ba == "ally":
		return Color(Tokens.SABLE.r, Tokens.SABLE.g, Tokens.SABLE.b, 0.85)
	# Mixed neutral or one-sided ally.
	return Color(Tokens.BONE_DIM.r, Tokens.BONE_DIM.g, Tokens.BONE_DIM.b, 0.7)
