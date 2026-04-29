extends Control
##
## Phase 1 demo scene — visual review surface for every War Council
## primitive at every relevant variant.
##
## Build the layout programmatically so the .tscn stays minimal (just
## a Control node pointing at this script).
##
## Components are preloaded by path (not via class_name) because
## headless `--script` invocation doesn't always register class_names
## before parse — preload is unambiguous.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

const BrassPlateScript      = preload("res://components/BrassPlate.gd")
const CrestScript           = preload("res://components/Crest.gd")
const WaxEnvelopeScript     = preload("res://components/WaxEnvelope.gd")
const ThroneScript          = preload("res://components/Throne.gd")
const UnitPieceScript       = preload("res://components/UnitPiece.gd")
const TensionMeterScript    = preload("res://components/TensionMeter.gd")
const ScalesOfLeverageScript = preload("res://components/ScalesOfLeverage.gd")
const CouncilHexScript      = preload("res://components/CouncilHex.gd")
const CouncilShellScript    = preload("res://components/CouncilShell.gd")

func _ready() -> void:
	# Mount everything inside a CouncilShell so the felt + frame
	# render correctly.
	var shell := CouncilShellScript.new()
	shell.anchor_right = 1.0
	shell.anchor_bottom = 1.0
	add_child(shell)

	# Wait one frame so CouncilShell._ready creates its content node.
	await get_tree().process_frame

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child_to_content(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	v.add_child(_section("CRESTS — heraldic shields per faction", _build_crests()))
	v.add_child(_section("UNIT PIECES — sculpted disks per player + states", _build_unit_pieces()))
	v.add_child(_section("COUNCIL HEXES — terrain × supply × home", _build_hexes()))
	v.add_child(_section("BRASS PLATES — engraved labels at three sizes", _build_brass_plates()))
	v.add_child(_section("WAX ENVELOPES — sealed letters / aid tokens", _build_envelopes()))
	v.add_child(_section("TENSION METERS — phase × value", _build_tension_meters()))
	v.add_child(_section("SCALES OF LEVERAGE — tilt × load", _build_scales()))
	v.add_child(_section("THRONES — matchmaking seats (occupied + empty)", _build_thrones()))


func _section(title: String, body: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var plate := BrassPlateScript.new()
	plate.text = title
	plate.font_size_px = 11
	box.add_child(plate)
	var row_wrap := MarginContainer.new()
	row_wrap.add_theme_constant_override("margin_left", 0)
	row_wrap.add_theme_constant_override("margin_top", 6)
	row_wrap.add_child(body)
	box.add_child(row_wrap)
	return box


func _build_crests() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for pid in 4:
		var c := CrestScript.new()
		c.player_id = pid
		c.crest_size = 60
		row.add_child(c)
	var broken := CrestScript.new()
	broken.player_id = 0
	broken.crest_size = 60
	broken.broken = true
	row.add_child(broken)
	var dimmed := CrestScript.new()
	dimmed.player_id = 1
	dimmed.crest_size = 60
	dimmed.dim = true
	row.add_child(dimmed)
	return row


func _build_unit_pieces() -> Control:
	# UnitPiece is Node2D — we wrap each in a Control with an
	# embedded SubViewport-free workaround: a Node2D parented to a
	# Control by way of a manual Control that owns the Node2D and
	# offsets it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for pid in 4:
		row.add_child(_node2d_in_control(_make_unit(pid, "A", false, false), 36, 36))
	row.add_child(_node2d_in_control(_make_unit(0, "B", true, false), 36, 36))
	row.add_child(_node2d_in_control(_make_unit(1, "C", false, true), 36, 36))
	return row


func _make_unit(pid: int, label: String, selected: bool, ghost: bool) -> Node2D:
	var u: Node2D = UnitPieceScript.new()
	u.player_id = pid
	u.label = label
	u.piece_size = 26
	u.selected = selected
	u.ghost = ghost
	return u


func _build_hexes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	# Build a small line of hexes side-by-side with varied tile data.
	var sample_tiles := [
		{"q": 0, "r": 0, "terrain": "plain",    "supply": 0, "owner": null, "home": null, "unit": null},
		{"q": 1, "r": 0, "terrain": "forest",   "supply": 1, "owner": 0,    "home": null, "unit": null},
		{"q": 2, "r": 0, "terrain": "mountain", "supply": 0, "owner": 1,    "home": null, "unit": null},
		{"q": 3, "r": 0, "terrain": "water",    "supply": 0, "owner": null, "home": null, "unit": null},
		{"q": 4, "r": 0, "terrain": "plain",    "supply": 2, "owner": 2,    "home": null, "unit": null},
		{"q": 5, "r": 0, "terrain": "plain",    "supply": 0, "owner": 3,    "home": 3,    "unit": null},
		{"q": 6, "r": 0, "terrain": "plain",    "supply": 1, "owner": 0,    "home": 0,    "unit": {"player": 0, "label": "A"}},
		{"q": 7, "r": 0, "terrain": "forest",   "supply": 0, "owner": 2,    "home": null, "unit": {"player": 2, "label": "B"}},
	]
	# CouncilHex is Node2D — wrap each in a Control sized to fit.
	for t in sample_tiles:
		var h := CouncilHexScript.new()
		# Override q/r so each hex draws at a fresh local origin
		# (we set position to 0 inside the Control wrapper).
		var local_tile: Dictionary = t.duplicate()
		local_tile["q"] = 0
		local_tile["r"] = 0
		h.tile = local_tile
		var wrap := _node2d_in_control(h, 78, 78)
		row.add_child(wrap)
	return row


func _build_brass_plates() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for fsz in [9, 11, 14]:
		var p := BrassPlateScript.new()
		p.text = "WAR COUNCIL"
		p.font_size_px = fsz
		row.add_child(p)
	return row


func _build_envelopes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for params in [
		{"sealed": true,  "label": "A", "color": Tokens.BLOOD},
		{"sealed": true,  "label": "B", "color": Tokens.AZURE},
		{"sealed": true,  "label": "",  "color": Tokens.OCHRE},
		{"sealed": false, "label": "",  "color": Tokens.BLOOD},
	]:
		var e := WaxEnvelopeScript.new()
		e.icon_size = 36
		e.sealed = params["sealed"]
		e.label = params["label"]
		e.seal_color = params["color"]
		row.add_child(e)
	return row


func _build_tension_meters() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	for params in [
		{"phase": "negotiation", "value": 0.20, "timer": "03:42"},
		{"phase": "negotiation", "value": 0.85, "timer": "00:18"},
		{"phase": "orders",      "value": 0.50, "timer": "00:45"},
	]:
		var m := TensionMeterScript.new()
		m.phase = params["phase"]
		m.value = params["value"]
		m.timer_text = params["timer"]
		m.custom_minimum_size = Vector2(560, 36)
		col.add_child(m)
	return col


func _build_scales() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for params in [
		{"tilt": -1.0, "left": 6, "right": 0},
		{"tilt": -0.4, "left": 4, "right": 1},
		{"tilt":  0.0, "left": 3, "right": 3},
		{"tilt":  0.6, "left": 1, "right": 5},
		{"tilt":  1.0, "left": 0, "right": 7},
	]:
		var s := ScalesOfLeverageScript.new()
		s.tilt = params["tilt"]
		s.left_load = params["left"]
		s.right_load = params["right"]
		s.scales_size = 140
		row.add_child(_node2d_in_control(s, 160, 160))
	return row


func _build_thrones() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for params in [
		{"occupied": true,  "pid": 0},
		{"occupied": false, "pid": 0},
		{"occupied": true,  "pid": 2},
		{"occupied": false, "pid": 0},
	]:
		var t := ThroneScript.new()
		t.occupied = params["occupied"]
		t.player_id = params["pid"]
		t.throne_size = 120
		row.add_child(t)
	return row


func _node2d_in_control(n2d: Node2D, w: int, h: int) -> Control:
	# Wrap a Node2D in a Control so it can sit inside HBox/VBox layouts.
	# Position the Node2D at the control's center.
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.add_child(n2d)
	n2d.position = Vector2(w / 2.0, h / 2.0)
	return c
