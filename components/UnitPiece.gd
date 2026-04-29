extends Node2D
class_name UnitPiece
##
## Top-down sculpted disk used inside CouncilHex to represent a unit.
##
## Renders concentric disks (ink ring, dim color, main color), a white
## glint ellipse, label glyph, optional candle-yellow selected halo,
## optional ghost (faded) modulation.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
## Reference: design's d3-council-base.jsx UnitPiece.
##

@export_range(0, 3) var player_id: int = 0 :
	set(value): player_id = value; queue_redraw()

@export var label: String = "A" :
	set(value): label = value; queue_redraw()

@export_range(8, 80, 1) var piece_size: int = 22 :
	set(value): piece_size = value; queue_redraw()

@export var selected: bool = false :
	set(value): selected = value; queue_redraw()

@export var ghost: bool = false :
	set(value): ghost = value; queue_redraw()


func _draw() -> void:
	var r := piece_size / 2.0
	var p_main := Tokens.player_main(player_id)
	var p_dim  := Tokens.player_dim(player_id)
	var alpha := 0.4 if ghost else 1.0

	# Drop shadow (Node2D draws at local origin)
	if not ghost:
		draw_circle(Vector2(0, r * 0.15), r * 0.95, Color(0, 0, 0, 0.6 * alpha))

	# Base ring (ink)
	draw_circle(Vector2.ZERO, r * 0.95, Color(Tokens.INK, alpha))
	# Dim shade
	draw_circle(Vector2.ZERO, r * 0.85, Color(p_dim, alpha))
	# Main color
	draw_circle(Vector2.ZERO, r * 0.78, Color(p_main, alpha))

	# Glint — white ellipse upper-left
	# Godot Node2D doesn't have a draw_ellipse; approximate with small
	# circle. Visually close at unit-piece scale.
	draw_circle(Vector2(-r * 0.25, -r * 0.30), r * 0.30,
		Color(1, 1, 1, 0.25 * alpha))

	# Label glyph
	var f := load(Tokens.FONT_DISPLAY) as FontFile
	if f != null and label != "":
		var fsize := int(piece_size * 0.55)
		var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(f, Vector2(-ts.x / 2.0, ts.y / 4.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color(Tokens.BONE, alpha))

	# Selection halo — candle dashed circle
	if selected:
		var halo_r := r + 5
		var dash_count := 24
		for i in dash_count:
			if i % 2 == 0:
				var a0 := i * (TAU / dash_count)
				var a1 := (i + 1) * (TAU / dash_count)
				var p0 := Vector2(cos(a0), sin(a0)) * halo_r
				var p1 := Vector2(cos(a1), sin(a1)) * halo_r
				draw_line(p0, p1, Tokens.CANDLE, 1.5)
