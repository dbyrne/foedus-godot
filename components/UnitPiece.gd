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
	set(value): player_id = value; _refresh_label(); queue_redraw()

@export var label: String = "A" :
	set(value): label = value; _refresh_label(); queue_redraw()

@export_range(8, 80, 1) var piece_size: int = 22 :
	set(value): piece_size = value; _refresh_label(); queue_redraw()

@export var selected: bool = false :
	set(value): selected = value; queue_redraw()

@export var ghost: bool = false :
	set(value): ghost = value; queue_redraw()

var _label_node: Label


func _ready() -> void:
	_refresh_label()


func _refresh_label() -> void:
	if not is_inside_tree():
		return
	if _label_node == null:
		_label_node = Label.new()
		_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label_node.add_theme_font_override(
			"font", load(Tokens.FONT_DISPLAY) as Font
		)
		_label_node.add_theme_color_override("font_color", Tokens.BONE)
		add_child(_label_node)
	var fsize := int(piece_size * 0.6)
	_label_node.add_theme_font_size_override("font_size", fsize)
	_label_node.text = label
	# Center the Label on the Node2D's local origin.
	var w := piece_size + 8
	var h := piece_size + 8
	_label_node.size = Vector2(w, h)
	_label_node.position = Vector2(-w * 0.5, -h * 0.5)


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
	draw_circle(Vector2(-r * 0.25, -r * 0.30), r * 0.30,
		Color(1, 1, 1, 0.25 * alpha))

	# Label glyph is rendered by the _label_node Label child (added in
	# _ready / _refresh_label). Labels handle theme-font-overrides
	# correctly with variable fonts; raw draw_string does not.
	if ghost and _label_node != null:
		_label_node.modulate = Color(1, 1, 1, 0.4)
	elif _label_node != null:
		_label_node.modulate = Color(1, 1, 1, 1)

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
