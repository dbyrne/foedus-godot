extends Node2D
class_name HexBoard
##
## Full hex-grid renderer driven by a ViewModel. Instantiates one
## CouncilHex per tile, positions them via Tokens.hex_to_px(q, r),
## tracks hovered/selected hexes for click feedback.
##
## Drag-state for order entry is deferred to Phase 2b.
##
## Signals:
##   tile_clicked(node_id, button)   — left or right click on any hex
##   unit_clicked(unit_id, button)   — left or right click on a hex with a unit
##
## Usage:
##   var board := HexBoard.new()
##   board.set_view_model(view_model)
##   add_child(board)
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const CouncilHexScript = preload("res://components/CouncilHex.gd")

signal tile_clicked(node_id: int, button: int)
signal unit_clicked(unit_id: int, button: int)

var _view_model = null  # ViewModel; loose typing avoids class_name ordering
var _hex_nodes: Dictionary = {}   # node_id → CouncilHex Node2D
var _selected_unit_id: int = -1


func set_view_model(vm) -> void:
	_view_model = vm
	_rebuild()


func selected_unit_id() -> int:
	return _selected_unit_id


func set_selected_unit_id(uid: int) -> void:
	_selected_unit_id = uid
	_refresh_selection_overlay()


func _ready() -> void:
	if _view_model != null:
		_rebuild()


func _rebuild() -> void:
	# Tear down existing hexes.
	for node_id in _hex_nodes.keys():
		_hex_nodes[node_id].queue_free()
	_hex_nodes.clear()
	if _view_model == null:
		return
	# Instantiate one CouncilHex per tile.
	for tile in _view_model.tiles():
		var hex = CouncilHexScript.new()
		var hex_tile := {
			"q": tile["q"],
			"r": tile["r"],
			"terrain": _terrain_for_node_type(tile["node_type"]),
			"supply": _supply_for_tile(tile),
			"owner": tile["owner"],
			"home": tile["home_player"],
			"unit": tile["unit"],
		}
		hex.tile = hex_tile
		hex.position = Tokens.hex_to_px(tile["q"], tile["r"])
		add_child(hex)
		_hex_nodes[tile["node_id"]] = hex
	_refresh_selection_overlay()


func _refresh_selection_overlay() -> void:
	if _view_model == null:
		return
	for node_id in _hex_nodes.keys():
		var hex = _hex_nodes[node_id]
		var t = _view_model.tile_for_node(node_id)
		var selected := false
		if _selected_unit_id >= 0 and t.get("unit") != null:
			selected = int(t["unit"]["id"]) == _selected_unit_id
		hex.selected = selected


func _terrain_for_node_type(node_type: String) -> String:
	## CouncilHex's `terrain` field uses lowercase names; the wire's
	## NodeType enum is uppercase. Map them here so the engine's enum
	## stays the source of truth and CouncilHex stays string-keyed.
	match node_type:
		"FOREST":   return "forest"
		"MOUNTAIN": return "mountain"
		"WATER":    return "water"
		# HOME, SUPPLY, PLAIN all render as the "plain" base; their
		# distinguishing markers (banner / chest) are drawn from
		# tile.home / tile.supply, not from the terrain face.
		_: return "plain"


func _supply_for_tile(tile: Dictionary) -> int:
	## CouncilHex.supply is 0 (none), 1 (regular chest), 2 (high-value crown).
	## Only SUPPLY-type nodes show a marker; HOMEs always render their banner
	## but no supply chest even though they yield score.
	if tile.get("node_type") != "SUPPLY":
		return 0
	return int(tile.get("supply_value", 1))


# --- Input handling -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or _view_model == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var local: Vector2 = to_local(event.position)
		var hit_node_id := _node_id_at(local)
		if hit_node_id < 0:
			return
		var t = _view_model.tile_for_node(hit_node_id)
		var unit = t.get("unit")
		if unit != null:
			unit_clicked.emit(int(unit["id"]), event.button_index)
		tile_clicked.emit(hit_node_id, event.button_index)


func _node_id_at(local_point: Vector2) -> int:
	## Point-in-hexagon hit-test. Iterates hexes whose centers are
	## within bounding distance, then checks the actual pointy-top
	## hexagon shape. Drag-from-piece order entry (Phase 2b) needs
	## accurate edge hits, which a nearest-neighbor approximation
	## couldn't deliver.
	var bound: float = float(Tokens.HEX_R) * 1.2
	for node_id in _hex_nodes.keys():
		var hex = _hex_nodes[node_id]
		var d: float = local_point.distance_to(hex.position)
		if d > bound:
			continue
		if _point_in_pointy_hex(local_point - hex.position, float(Tokens.HEX_R)):
			return node_id
	return -1


static func _point_in_pointy_hex(p: Vector2, r: float) -> bool:
	## Pointy-top hex centered at origin: width = sqrt(3) * r along x,
	## height = 2 * r along y. Test by combining the bounding box with
	## the diagonal edge constraint.
	var w: float = r * sqrt(3.0)
	var ax: float = abs(p.x)
	var ay: float = abs(p.y)
	if ax > w * 0.5:
		return false
	if ay > r:
		return false
	# The hex's diagonal edge runs from (w/2, r/2) to (0, r). The
	# point is inside iff ay ≤ r - (ax / (w/2)) * (r/2) = r * (1 - ax/w).
	return ay <= r * (1.0 - ax / w)
