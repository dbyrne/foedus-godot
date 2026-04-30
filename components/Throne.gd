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
		_crest.crest_size = int(throne_size * 0.5)
		_crest.position = Vector2(throne_size * 0.25, throne_size * 0.35)
		add_child(_crest)
	queue_redraw()


func _draw() -> void:
	var w := float(throne_size)
	var h := w * 1.3
	# Backrest — tall rectangle with arched top
	var back := PackedVector2Array([
		Vector2(w * 0.18, h * 0.05),  # top-left
		Vector2(w * 0.30, h * 0.0),
		Vector2(w * 0.70, h * 0.0),
		Vector2(w * 0.82, h * 0.05),
		Vector2(w * 0.82, h * 0.65),
		Vector2(w * 0.18, h * 0.65),
	])
	draw_colored_polygon(back, Tokens.FELT_LIGHT)
	for i in back.size():
		var a := back[i]
		var b := back[(i + 1) % back.size()]
		draw_line(a, b, Tokens.BRASS_DIM, 1.5)

	# Seat
	var seat := Rect2(Vector2(w * 0.10, h * 0.65), Vector2(w * 0.80, h * 0.10))
	draw_rect(seat, Tokens.FELT_LIGHT, true)
	draw_rect(seat, Tokens.BRASS_DIM, false, 1.5)

	# Legs
	draw_rect(Rect2(Vector2(w * 0.14, h * 0.75), Vector2(w * 0.06, h * 0.20)),
		Tokens.FELT_DARK, true)
	draw_rect(Rect2(Vector2(w * 0.80, h * 0.75), Vector2(w * 0.06, h * 0.20)),
		Tokens.FELT_DARK, true)

	# Brass finials at backrest top corners
	draw_circle(Vector2(w * 0.20, h * 0.04), w * 0.04, Tokens.BRASS)
	draw_circle(Vector2(w * 0.80, h * 0.04), w * 0.04, Tokens.BRASS)

	# Empty-state label
	if not occupied:
		var f := load(Tokens.FONT_SERIF_ITALIC) as Font
		var fsize := int(w * 0.10)
		var msg := "(empty)"
		var ts := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(f, Vector2((w - ts.x) / 2.0, h * 0.45), msg,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Tokens.BONE_DIM)
