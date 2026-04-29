extends Control
class_name Crest
##
## Sculpted heraldic shield with player color and per-faction sigil.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
## Reference: design's d3-council-base.jsx Crest component.
##

@export_range(0, 3) var player_id: int = 0 :
	set(value): player_id = value; queue_redraw()

@export_range(16, 200, 2) var crest_size: int = 40 :
	set(value):
		crest_size = value
		custom_minimum_size = Vector2(value, value * 70.0 / 60.0)
		queue_redraw()

@export var broken: bool = false :
	set(value): broken = value; queue_redraw()

@export var dim: bool = false :
	set(value): dim = value; queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(crest_size, crest_size * 70.0 / 60.0)


func _draw() -> void:
	var s := float(crest_size)
	var k := s / 60.0
	var p_main := Tokens.player_main(player_id)
	var p_dim  := Tokens.player_dim(player_id)
	if dim:
		p_main = p_main.darkened(0.4)
		p_dim = p_dim.darkened(0.4)

	# Shield outline — sample the Bezier curves into a polygon
	var pts := _shield_outline(k)

	# Filled shield with vertical gradient via two stacked polys
	# Approximate gradient: split shield into slabs by y, fill each with
	# lerp(p_main, p_dim).
	var ymin := pts[0].y
	var ymax := ymin
	for v in pts:
		ymin = min(ymin, v.y); ymax = max(ymax, v.y)
	var slabs := 12
	for i in slabs:
		var y0 := ymin + (ymax - ymin) * (float(i) / slabs)
		var y1 := ymin + (ymax - ymin) * (float(i + 1) / slabs)
		var t := float(i) / float(slabs - 1)
		var c := p_main.lerp(p_dim, t)
		var slab_pts := _clip_polygon_to_y_band(pts, y0, y1)
		if slab_pts.size() >= 3:
			draw_colored_polygon(slab_pts, c)

	# Outline
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	for i in outline_pts.size() - 1:
		draw_line(outline_pts[i], outline_pts[i + 1], Tokens.BRASS, 1.5)

	# Inner soft highlight rim
	var inner := PackedVector2Array()
	for v in pts:
		# Shrink toward centroid
		var cx := s / 2.0
		var cy := s * 70.0 / 60.0 / 2.0
		var d := Vector2(cx, cy) - v
		inner.append(v + d.normalized() * 2.5)
	var inner_close := inner.duplicate()
	inner_close.append(inner[0])
	for i in inner_close.size() - 1:
		draw_line(inner_close[i], inner_close[i + 1], Color(1, 1, 1, 0.15), 0.5)

	# Sigil
	_draw_sigil(player_id, k)

	# Broken overlay
	if broken:
		draw_line(Vector2(s * 0.23, s * 0.4), Vector2(s * 0.77, s * 0.8), Tokens.INK, 3.0)
		draw_line(Vector2(s * 0.23, s * 0.4), Vector2(s * 0.77, s * 0.8), Tokens.BLOOD, 1.5)


func _shield_outline(k: float) -> PackedVector2Array:
	# Shield path from design: M 6 6 L 54 6 L 54 38
	# C 54 56 30 66 30 66 C 30 66 6 56 6 38 Z (in 60-unit space)
	var pts := PackedVector2Array()
	pts.append(Vector2(6, 6) * k)
	pts.append(Vector2(54, 6) * k)
	pts.append(Vector2(54, 38) * k)
	# Bottom-right curve
	for i in 21:
		var t := i / 20.0
		pts.append(_bezier(
			Vector2(54, 38), Vector2(54, 56), Vector2(30, 66), Vector2(30, 66), t
		) * k)
	# Bottom-left curve
	for i in 21:
		var t := i / 20.0
		pts.append(_bezier(
			Vector2(30, 66), Vector2(30, 66), Vector2(6, 56), Vector2(6, 38), t
		) * k)
	return pts


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u*u*u * p0 + 3.0*u*u*t * p1 + 3.0*u*t*t * p2 + t*t*t * p3


func _clip_polygon_to_y_band(pts: PackedVector2Array, y0: float, y1: float) -> PackedVector2Array:
	# Simple Sutherland–Hodgman clip against two horizontal lines.
	# Adequate for our shield outline (convex-ish in y).
	var clipped := _clip_above(pts, y0)
	clipped = _clip_below(clipped, y1)
	return clipped


func _clip_above(pts: PackedVector2Array, y_min: float) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var a_in := a.y >= y_min
		var b_in := b.y >= y_min
		if a_in:
			out.append(a)
			if not b_in:
				out.append(_intercept_y(a, b, y_min))
		elif b_in:
			out.append(_intercept_y(a, b, y_min))
	return out


func _clip_below(pts: PackedVector2Array, y_max: float) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var a_in := a.y <= y_max
		var b_in := b.y <= y_max
		if a_in:
			out.append(a)
			if not b_in:
				out.append(_intercept_y(a, b, y_max))
		elif b_in:
			out.append(_intercept_y(a, b, y_max))
	return out


func _intercept_y(a: Vector2, b: Vector2, y: float) -> Vector2:
	if abs(b.y - a.y) < 0.001:
		return a
	var t := (y - a.y) / (b.y - a.y)
	return a + (b - a) * t


func _draw_sigil(pid: int, k: float) -> void:
	match pid:
		0:  # Aelia — diamond/spear
			var pts := PackedVector2Array([
				Vector2(30, 18) * k, Vector2(36, 30) * k,
				Vector2(30, 50) * k, Vector2(24, 30) * k,
			])
			draw_colored_polygon(pts, Tokens.BONE)
		1:  # Borovic — circle + vertical bar
			draw_arc(Vector2(30, 32) * k, 10 * k, 0, TAU, 32, Tokens.BONE, 2.0)
			draw_line(Vector2(30, 20) * k, Vector2(30, 48) * k, Tokens.BONE, 2.0)
		2:  # Cyrene — sun (disk + radiating)
			draw_circle(Vector2(30, 32) * k, 6 * k, Tokens.BONE)
			for i in 8:
				var ang := i * (TAU / 8.0)
				var p1 := Vector2(30 + cos(ang) * 8, 32 + sin(ang) * 8) * k
				var p2 := Vector2(30 + cos(ang) * 12, 32 + sin(ang) * 12) * k
				draw_line(p1, p2, Tokens.BONE, 1.2)
		3:  # Drevan — leaf
			var leaf := PackedVector2Array([
				Vector2(30, 16) * k, Vector2(38, 24) * k,
				Vector2(38, 36) * k, Vector2(30, 50) * k,
				Vector2(22, 36) * k, Vector2(22, 24) * k,
			])
			draw_colored_polygon(leaf, Tokens.BONE)
