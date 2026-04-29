extends Node2D
class_name CouncilHex
##
## A hex tile rendered in the War Council style — sculpted face with
## terrain decals, optional supply marker (chest at supply=1, crown at
## supply=2), home banner, owner-color ring, selection halo, and
## optional unit piece child.
##
## Tile data is passed as a Dictionary (not yet a Resource) so the
## existing GameClient can feed `view.state.map.tiles[i]`-shaped
## records directly. Schema:
##   {
##     "q": int, "r": int,
##     "terrain": "plain"|"forest"|"mountain"|"water",
##     "supply": 0|1|2,
##     "owner": int|null,    # player_id or null
##     "home": int|null,     # player_id whose home is here
##     "unit": {"player": int, "label": String}|null,
##   }
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
## Reference: design's d3-council-base.jsx CouncilHex.
##

const TERRAIN_COLORS := {
	"plain":    Color("#3a4a3e"),
	"forest":   Color("#2d3a2d"),
	"mountain": Color("#4a4338"),
	"water":    Color("#1f3640"),
}

@export var tile: Dictionary = {} :
	set(value): tile = value; _refresh_unit(); queue_redraw()

@export var selected: bool = false :
	set(value): selected = value; queue_redraw()

@export var highlight: Color = Color(0, 0, 0, 0) :
	set(value): highlight = value; queue_redraw()

const UnitPieceScript = preload("res://components/UnitPiece.gd")

var _unit_piece: Node2D  # UnitPiece, typed loosely


func _ready() -> void:
	_refresh_unit()


func _refresh_unit() -> void:
	if not is_inside_tree():
		return
	if _unit_piece != null:
		_unit_piece.queue_free()
		_unit_piece = null
	var u = tile.get("unit") if tile is Dictionary else null
	if u != null:
		_unit_piece = UnitPieceScript.new()
		_unit_piece.player_id = int(u.get("player", 0))
		_unit_piece.label = String(u.get("label", "A"))
		_unit_piece.piece_size = 26
		_unit_piece.selected = selected
		add_child(_unit_piece)


func _draw() -> void:
	var q := int(tile.get("q", 0))
	var r := int(tile.get("r", 0))
	var center := Tokens.hex_to_px(q, r)
	# Position the Node2D at the hex center; everything below draws
	# relative to that.
	position = center
	var hr := float(Tokens.HEX_R - 1)

	var terrain := String(tile.get("terrain", "plain"))
	var base_color: Color = TERRAIN_COLORS.get(terrain, TERRAIN_COLORS["plain"])

	# Drop shadow
	_draw_hexagon(Vector2(0, 2), hr, Color(0, 0, 0, 0.4), Color(0, 0, 0, 0))
	# Base
	_draw_hexagon(Vector2.ZERO, hr, base_color, Tokens.INK)

	# Owner-tint inset ring
	var owner = tile.get("owner")
	if owner != null:
		var oc := Tokens.player_main(int(owner))
		_draw_hexagon_ring(Vector2.ZERO, hr - 2, Color(oc.r, oc.g, oc.b, 0.55), 1.5)

	# Terrain decals
	match terrain:
		"mountain":
			var pts := PackedVector2Array([
				Vector2(-10, 6), Vector2(-3, -8), Vector2(3, 2),
				Vector2(10, -10), Vector2(14, 6),
			])
			draw_colored_polygon(pts, Color(Tokens.INK, 0.6))
			for i in pts.size():
				draw_line(pts[i], pts[(i + 1) % pts.size()],
					Color(Tokens.BONE_DIM, 0.5), 0.5)
		"forest":
			for offset in [Vector2(-8, 2), Vector2(0, -4), Vector2(8, 4)]:
				draw_line(offset + Vector2(0, 6), offset + Vector2(0, -2),
					Color(Tokens.INK, 0.7), 1.0)
				draw_line(offset + Vector2(0, -2), offset + Vector2(-3, 0),
					Color(Tokens.INK, 0.7), 1.0)
				draw_line(offset + Vector2(0, -6), offset + Vector2(3, 0),
					Color(Tokens.INK, 0.7), 1.0)
		"water":
			for off_y in [0, 5]:
				var wave := PackedVector2Array()
				for x in range(-10, 12, 2):
					wave.append(Vector2(x, off_y + sin(x * 0.6) * 1.5))
				for i in wave.size() - 1:
					draw_line(wave[i], wave[i + 1], Color(Tokens.BONE_DIM, 0.5), 0.8)

	# Supply marker
	var supply := int(tile.get("supply", 0))
	if supply == 1:
		var anchor := Vector2(hr - 12, -hr + 10)
		draw_rect(Rect2(anchor + Vector2(-5, -3), Vector2(10, 7)),
			Tokens.BRASS_DIM, true)
		draw_rect(Rect2(anchor + Vector2(-5, -3), Vector2(10, 7)),
			Tokens.INK, false, 0.5)
		draw_rect(Rect2(anchor + Vector2(-5, -5), Vector2(10, 3)),
			Tokens.BRASS, true)
	elif supply == 2:
		var anchor := Vector2(hr - 13, -hr + 10)
		var crown := PackedVector2Array([
			anchor + Vector2(-7, 4), anchor + Vector2(-7, -2),
			anchor + Vector2(0, -8), anchor + Vector2(7, -2),
			anchor + Vector2(7, 4),
		])
		draw_colored_polygon(crown, Tokens.BRASS)
		for i in crown.size():
			draw_line(crown[i], crown[(i + 1) % crown.size()], Tokens.INK, 1.0)
		draw_circle(anchor + Vector2(0, -1), 2.5, Tokens.CANDLE)

	# Home banner
	var home = tile.get("home")
	if home != null:
		var hp := Vector2(-hr + 9, -hr + 10)
		var hc := Tokens.player_main(int(home))
		draw_rect(Rect2(hp + Vector2(-3, -6), Vector2(1.5, 14)),
			Tokens.BONE_DIM, true)
		var banner := PackedVector2Array([
			hp + Vector2(-1.5, -6), hp + Vector2(8, -6),
			hp + Vector2(6, -2),    hp + Vector2(8, 2),
			hp + Vector2(-1.5, 2),
		])
		draw_colored_polygon(banner, hc)
		for i in banner.size():
			draw_line(banner[i], banner[(i + 1) % banner.size()], Tokens.INK, 0.5)

	# Highlight overlay
	if highlight.a > 0:
		_draw_hexagon(Vector2.ZERO, hr, Color(highlight.r, highlight.g, highlight.b, 0.18), Color(0, 0, 0, 0))

	# Selection halo
	if selected:
		_draw_hexagon_ring(Vector2.ZERO, hr + 2, Tokens.CANDLE, 2.0)

	# Unit piece is a child Node2D; it draws at our origin automatically.


func _draw_hexagon(center: Vector2, radius: float, fill: Color, stroke: Color) -> void:
	var pts := _hex_corners(center, radius)
	if fill.a > 0:
		draw_colored_polygon(pts, fill)
	if stroke.a > 0:
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], stroke, 1.0)


func _draw_hexagon_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var pts := _hex_corners(center, radius)
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], color, width)


func _hex_corners(center: Vector2, radius: float) -> PackedVector2Array:
	# Pointy-top hexagon: corners at angles 30, 90, 150, 210, 270, 330.
	var pts := PackedVector2Array()
	for i in 6:
		var ang_deg := 30.0 + i * 60.0
		var ang := deg_to_rad(ang_deg)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return pts
