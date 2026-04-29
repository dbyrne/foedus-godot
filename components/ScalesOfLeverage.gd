extends Node2D
class_name ScalesOfLeverage
##
## Animated balance — a center post, a beam that tilts based on the
## difference between left and right loads, two pans hanging from beam
## ends, and small bone disks stacked on each pan to represent load.
##
## Used in the Pairwise Dossier (Phase 2) to make leverage tactile.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

@export_range(-1.0, 1.0, 0.01) var tilt: float = 0.0 :
	set(value): tilt = value; queue_redraw()

@export_range(0, 12) var left_load: int = 0 :
	set(value): left_load = value; queue_redraw()

@export_range(0, 12) var right_load: int = 0 :
	set(value): right_load = value; queue_redraw()

@export_range(60, 400, 5) var scales_size: int = 160 :
	set(value): scales_size = value; queue_redraw()


func _draw() -> void:
	var s := float(scales_size)
	# Coordinate system: origin at center; post rises upward (-y).
	# Base
	draw_rect(Rect2(Vector2(-s * 0.20, s * 0.30), Vector2(s * 0.40, s * 0.06)),
		Tokens.BRASS_DIM, true)
	draw_rect(Rect2(Vector2(-s * 0.20, s * 0.30), Vector2(s * 0.40, s * 0.06)),
		Tokens.INK, false, 1.0)
	# Post
	draw_rect(Rect2(Vector2(-s * 0.025, -s * 0.35), Vector2(s * 0.05, s * 0.65)),
		Tokens.BRASS, true)
	# Pivot finial
	draw_circle(Vector2(0, -s * 0.35), s * 0.04, Tokens.BRASS)
	draw_circle(Vector2(0, -s * 0.35), s * 0.04, Tokens.INK)

	# Beam — rotates by tilt * 0.4 radians (~23° max)
	var ang := tilt * 0.4
	var beam_len := s * 0.36
	var b_left  := Vector2(-cos(ang), sin(ang)) * beam_len + Vector2(0, -s * 0.35)
	var b_right := Vector2( cos(ang),-sin(ang)) * beam_len + Vector2(0, -s * 0.35)
	draw_line(b_left, b_right, Tokens.BRASS, 4.0)
	draw_line(b_left, b_right, Tokens.BRASS_DIM, 1.5)

	# Pans hang straight down from each beam end (gravity is real)
	var pan_drop := s * 0.18
	for end_pt in [b_left, b_right]:
		var pan_top := end_pt + Vector2(0, pan_drop)
		# Chain
		draw_line(end_pt + Vector2(-s * 0.04, 0), pan_top + Vector2(-s * 0.06, 0),
			Tokens.BRASS_DIM, 1.0)
		draw_line(end_pt + Vector2( s * 0.04, 0), pan_top + Vector2( s * 0.06, 0),
			Tokens.BRASS_DIM, 1.0)
		# Pan bowl
		var bowl := PackedVector2Array([
			pan_top + Vector2(-s * 0.10, 0),
			pan_top + Vector2( s * 0.10, 0),
			pan_top + Vector2( s * 0.07, s * 0.05),
			pan_top + Vector2(-s * 0.07, s * 0.05),
		])
		draw_colored_polygon(bowl, Tokens.BRASS_DIM)
		for i in bowl.size():
			var a := bowl[i]
			var b := bowl[(i + 1) % bowl.size()]
			draw_line(a, b, Tokens.INK, 1.0)

	# Stack the load disks on each pan
	_draw_load_stack(b_left,  pan_drop, left_load,  s)
	_draw_load_stack(b_right, pan_drop, right_load, s)


func _draw_load_stack(beam_end: Vector2, pan_drop: float, count: int, s: float) -> void:
	if count <= 0:
		return
	var pan_top := beam_end + Vector2(0, pan_drop)
	var disk_r := s * 0.04
	for i in count:
		var y_off := -disk_r * 0.6 - i * (disk_r * 1.2)
		draw_circle(pan_top + Vector2(0, y_off), disk_r, Tokens.BONE)
		draw_arc(pan_top + Vector2(0, y_off), disk_r, 0, TAU, 16, Tokens.INK, 0.6)
