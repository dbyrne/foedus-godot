extends Control
class_name WaxEnvelope
##
## Sealed letter / aid token icon. Bone-colored rectangle with diagonal
## fold lines and an optional wax seal disk (player color + label).
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
## Reference: design's d3-council-base.jsx WaxEnvelope.
##

@export_range(12, 200, 2) var icon_size: int = 28 :
	set(value):
		icon_size = value
		custom_minimum_size = Vector2(value, value * 0.7)
		queue_redraw()

@export var sealed: bool = true :
	set(value): sealed = value; queue_redraw()

@export var seal_color: Color = Tokens.BLOOD :
	set(value): seal_color = value; queue_redraw()

@export var label: String = "" :
	set(value): label = value; queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size * 0.7)


func _draw() -> void:
	# Source SVG is 40x28 (width 40 → 0.7 ratio).
	var w := float(icon_size)
	var h := w * 0.7
	var sx := w / 40.0
	var sy := h / 28.0

	# Envelope body
	draw_rect(Rect2(Vector2(2, 4) * Vector2(sx, sy), Vector2(36, 22) * Vector2(sx, sy)),
		Tokens.BONE, true)
	draw_rect(Rect2(Vector2(2, 4) * Vector2(sx, sy), Vector2(36, 22) * Vector2(sx, sy)),
		Tokens.INK, false, 1.0)
	# Diagonal fold lines (the "M 2 4 L 20 18 L 38 4" path)
	draw_line(Vector2(2, 4) * Vector2(sx, sy),
		Vector2(20, 18) * Vector2(sx, sy), Tokens.INK, 0.8)
	draw_line(Vector2(20, 18) * Vector2(sx, sy),
		Vector2(38, 4) * Vector2(sx, sy), Tokens.INK, 0.8)

	# Seal disk
	if sealed:
		var center := Vector2(20, 20) * Vector2(sx, sy)
		var radius: float = 5.0 * min(sx, sy)
		draw_circle(center, radius, seal_color)
		draw_arc(center, radius, 0, TAU, 32, Tokens.INK, 0.8)
		if label != "":
			var f := load(Tokens.FONT_DISPLAY) as Font
			var fsize := int(radius * 1.4)
			var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
			draw_string(f, center + Vector2(-ts.x / 2, ts.y / 4), label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Tokens.BONE)
