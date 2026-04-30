extends Control
class_name Throne
##
## Matchmaking seat — a high-back chair silhouette in brass tones, with
## an optional Crest mounted in the seat or "(empty)" italic if
## unoccupied.
##
## Used by the Phase 3 matchmaking screen; primitive lives in Phase 1
## per spec to avoid revisiting fonts/theme later.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

@export var occupied: bool = false :
	set(value): occupied = value; _refresh()

@export_range(0, 3) var player_id: int = 0 :
	set(value): player_id = value; _refresh()

@export_range(80, 400, 5) var throne_size: int = 140 :
	set(value):
		throne_size = value
		custom_minimum_size = Vector2(value, value * 1.3)
		queue_redraw()
		_refresh()

const CrestScript = preload("res://components/Crest.gd")

var _crest: Node  # Crest, but typed loosely to avoid class_name ordering issues


func _ready() -> void:
	custom_minimum_size = Vector2(throne_size, throne_size * 1.3)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	if _crest != null:
		_crest.queue_free()
		_crest = null
	if occupied:
		_crest = CrestScript.new()
		_crest.player_id = player_id
		var cs := int(throne_size * 0.42)
		_crest.crest_size = cs
		# Center the crest inside the panel (panel: x∈[0.31, 0.69], y∈[0.10, 0.62] of throne size)
		var panel_cx := throne_size * 0.50
		var panel_cy := throne_size * 1.30 * 0.36  # vertical center of panel
		_crest.position = Vector2(panel_cx - cs * 0.5, panel_cy - cs * 0.6)
		add_child(_crest)
	queue_redraw()


func _draw() -> void:
	var w := float(throne_size)
	var h := w * 1.3

	# Drop shadow under seat for depth.
	draw_rect(Rect2(Vector2(w * 0.08, h * 0.78), Vector2(w * 0.84, h * 0.04)),
		Color(0, 0, 0, 0.5), true)

	# Backrest — pointed-arch top, tall sides (reads as a high-back
	# wooden throne rather than a banner).
	var back := PackedVector2Array([
		Vector2(w * 0.50, h * 0.00),  # peak
		Vector2(w * 0.62, h * 0.06),
		Vector2(w * 0.74, h * 0.04),
		Vector2(w * 0.78, h * 0.10),
		Vector2(w * 0.78, h * 0.66),
		Vector2(w * 0.22, h * 0.66),
		Vector2(w * 0.22, h * 0.10),
		Vector2(w * 0.26, h * 0.04),
		Vector2(w * 0.38, h * 0.06),
	])
	draw_colored_polygon(back, Tokens.FELT_LIGHT)
	# Inner panel (darker) — reads as a recessed velvet pad
	var panel := PackedVector2Array([
		Vector2(w * 0.31, h * 0.10),
		Vector2(w * 0.69, h * 0.10),
		Vector2(w * 0.69, h * 0.62),
		Vector2(w * 0.31, h * 0.62),
	])
	draw_colored_polygon(panel, Tokens.FELT_DARK)
	# Backrest outline + panel outline in brass
	for poly in [back, panel]:
		for i in poly.size():
			draw_line(poly[i], poly[(i + 1) % poly.size()], Tokens.BRASS_DIM, 1.5)

	# Armrests — small rounded extensions on either side
	draw_rect(Rect2(Vector2(w * 0.10, h * 0.55), Vector2(w * 0.16, h * 0.08)),
		Tokens.FELT_LIGHT, true)
	draw_rect(Rect2(Vector2(w * 0.10, h * 0.55), Vector2(w * 0.16, h * 0.08)),
		Tokens.BRASS_DIM, false, 1.5)
	draw_rect(Rect2(Vector2(w * 0.74, h * 0.55), Vector2(w * 0.16, h * 0.08)),
		Tokens.FELT_LIGHT, true)
	draw_rect(Rect2(Vector2(w * 0.74, h * 0.55), Vector2(w * 0.16, h * 0.08)),
		Tokens.BRASS_DIM, false, 1.5)

	# Seat — wider than backrest, slight forward overhang
	var seat := Rect2(Vector2(w * 0.08, h * 0.66), Vector2(w * 0.84, h * 0.10))
	draw_rect(seat, Tokens.FELT_LIGHT, true)
	draw_rect(seat, Tokens.BRASS_DIM, false, 1.5)

	# Legs — front pair visible
	draw_rect(Rect2(Vector2(w * 0.12, h * 0.76), Vector2(w * 0.08, h * 0.22)),
		Tokens.FELT_DARK, true)
	draw_rect(Rect2(Vector2(w * 0.12, h * 0.76), Vector2(w * 0.08, h * 0.22)),
		Tokens.BRASS_DIM, false, 1.0)
	draw_rect(Rect2(Vector2(w * 0.80, h * 0.76), Vector2(w * 0.08, h * 0.22)),
		Tokens.FELT_DARK, true)
	draw_rect(Rect2(Vector2(w * 0.80, h * 0.76), Vector2(w * 0.08, h * 0.22)),
		Tokens.BRASS_DIM, false, 1.0)
	# Foot finials
	draw_circle(Vector2(w * 0.16, h * 0.99), w * 0.05, Tokens.BRASS)
	draw_circle(Vector2(w * 0.84, h * 0.99), w * 0.05, Tokens.BRASS)

	# Brass finials at backrest peak + corners
	draw_circle(Vector2(w * 0.50, h * -0.02), w * 0.04, Tokens.BRASS)
	draw_circle(Vector2(w * 0.22, h * 0.10), w * 0.03, Tokens.BRASS)
	draw_circle(Vector2(w * 0.78, h * 0.10), w * 0.03, Tokens.BRASS)

	# Empty-state label inside the panel
	if not occupied:
		var f := load(Tokens.FONT_SERIF_ITALIC) as Font
		var fsize := int(w * 0.10)
		var msg := "(empty)"
		var ts := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(f, Vector2((w - ts.x) / 2.0, h * 0.40), msg,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Tokens.BONE_DIM)
