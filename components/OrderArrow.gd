extends Node2D
class_name OrderArrow
##
## A drawn arrow between two hex centers, used to render queued orders
## on the HexBoard. Color comes from the issuing player; dash style
## comes from the order kind:
##
##   Move     → solid bold line, filled triangle head
##   Support  → dashed line to target's destination if known, else dashed ring
##   Hold     → small ring on the unit (no arrow)
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const KIND_MOVE    := "Move"
const KIND_SUPPORT := "Support"
const KIND_HOLD    := "Hold"

@export var from_pos: Vector2 = Vector2.ZERO :
	set(value): from_pos = value; queue_redraw()

@export var to_pos: Vector2 = Vector2.ZERO :
	set(value): to_pos = value; queue_redraw()

@export var kind: String = KIND_MOVE :
	set(value): kind = value; queue_redraw()

@export_range(0, 3) var player_id: int = 0 :
	set(value): player_id = value; queue_redraw()

@export var ghost: bool = false :
	set(value): ghost = value; queue_redraw()


func _draw() -> void:
	var color := Tokens.player_main(player_id)
	var alpha: float = 0.55 if ghost else 0.95
	color = Color(color.r, color.g, color.b, alpha)

	match kind:
		KIND_MOVE:
			_draw_move_arrow(from_pos, to_pos, color)
		KIND_SUPPORT:
			# When from_pos == to_pos the caller has no destination info;
			# fall back to dashed ring around the target unit's location.
			if from_pos.distance_squared_to(to_pos) < 1.0:
				_draw_support_ring(to_pos, color)
			else:
				_draw_support_line(from_pos, to_pos, color)
		KIND_HOLD:
			_draw_hold_ring(to_pos, color)


func _draw_move_arrow(a: Vector2, b: Vector2, color: Color) -> void:
	var dir := (b - a).normalized()
	# Step in from the unit's center so the arrow doesn't sit under
	# the disk's outline.
	var inset := 14.0
	var p_from := a + dir * inset
	var p_to := b - dir * inset
	draw_line(p_from, p_to, color, 3.5)
	# Filled triangle head.
	var perp := Vector2(-dir.y, dir.x)
	var head_len := 12.0
	var head_w := 7.0
	var head := PackedVector2Array([
		p_to,
		p_to - dir * head_len + perp * head_w,
		p_to - dir * head_len - perp * head_w,
	])
	draw_colored_polygon(head, color)


func _draw_support_line(a: Vector2, b: Vector2, color: Color) -> void:
	## Dashed line from supporter to target's destination (or current location).
	var dir := (b - a).normalized()
	var inset := 14.0
	var p_from := a + dir * inset
	var p_to := b - dir * inset
	var dash_len := 7.0
	var gap := 4.0
	var seg_total := dash_len + gap
	var distance := p_from.distance_to(p_to)
	var t := 0.0
	while t < distance:
		var t_end: float = min(t + dash_len, distance)
		var s := p_from + dir * t
		var e := p_from + dir * t_end
		draw_line(s, e, color, 2.5)
		t += seg_total
	# Open arrowhead.
	var perp := Vector2(-dir.y, dir.x)
	var head_len := 11.0
	var head_w := 6.5
	draw_line(p_to, p_to - dir * head_len + perp * head_w, color, 2.0)
	draw_line(p_to, p_to - dir * head_len - perp * head_w, color, 2.0)


func _draw_support_ring(target: Vector2, color: Color) -> void:
	## Short dashed ring around the supported unit's hex (used when the
	## target's destination is not yet known).
	var radius := 18.0
	var dash_arc := 0.35  # radians
	var gap_arc := 0.20
	var seg := dash_arc + gap_arc
	var ang := 0.0
	while ang < TAU:
		var pts := PackedVector2Array()
		var arc_end: float = min(ang + dash_arc, TAU)
		var samples := 6
		for i in samples + 1:
			var t := ang + (arc_end - ang) * (i / float(samples))
			pts.append(target + Vector2(cos(t), sin(t)) * radius)
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], color, 2.0)
		ang += seg


func _draw_hold_ring(target: Vector2, color: Color) -> void:
	## A small filled ring marker at the unit, distinct from selection
	## halo (which is candle-yellow dashed).
	draw_arc(target, 17.0, 0, TAU, 32, color, 2.0)
