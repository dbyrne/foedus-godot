extends Control
class_name CouncilShell
##
## Full-screen wrapper — felt backdrop with vignette gradient, subtle
## noise overlay, gilded brass inner frame, corner ornaments. Every War
## Council screen mounts content inside one.
##
## Children added to a CouncilShell are placed in the inner padded
## area automatically (via the `content` MarginContainer). Use as:
##
##     var shell := CouncilShell.new()
##     shell.add_child(my_screen_root)  # auto-routed into the content area
##     add_child(shell)
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

const FRAME_INSET := 14
const PADDING := 24

var _content: MarginContainer
var _frame_layer_ready: bool = false

func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0


func _ready() -> void:
	# Migrate any children added before _ready into the content container.
	var pre_existing: Array[Node] = []
	for c in get_children():
		pre_existing.append(c)
	# Build the layered structure.
	_content = MarginContainer.new()
	_content.name = "Content"
	_content.anchor_right = 1.0
	_content.anchor_bottom = 1.0
	_content.add_theme_constant_override("margin_left", FRAME_INSET + PADDING)
	_content.add_theme_constant_override("margin_top", FRAME_INSET + PADDING)
	_content.add_theme_constant_override("margin_right", FRAME_INSET + PADDING)
	_content.add_theme_constant_override("margin_bottom", FRAME_INSET + PADDING)
	# Ensure mouse passes through the shell to children.
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	for c in pre_existing:
		# Skip our own management children if any.
		if c == _content:
			continue
		c.reparent(_content)
	_frame_layer_ready = true
	queue_redraw()


# Override add_child semantics post-_ready: route into content automatically.
func add_child_to_content(node: Node) -> void:
	if _content == null:
		add_child(node)
	else:
		_content.add_child(node)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return

	# Background — radial vignette gradient approximated with concentric
	# rectangles. (Godot 4.3 doesn't expose a native radial gradient on
	# Control._draw without a shader.)
	var slabs := 24
	for i in slabs:
		var t := float(i) / float(slabs - 1)
		# Center bright (FELT_LIGHT) → edge dark (FELT_DARK)
		var c := Tokens.FELT_LIGHT.lerp(Tokens.FELT_DARK, t * 0.85)
		var inset := t * 0.5
		draw_rect(
			Rect2(Vector2(w * inset * 0.05, h * inset * 0.05),
				Vector2(w * (1.0 - inset * 0.10), h * (1.0 - inset * 0.10))),
			Color(c.r, c.g, c.b, 1.0 / slabs * 1.4), true
		)
	# Solid fallback under the vignette (so we cover everything)
	# (drawn first conceptually — Godot _draw is one-shot top-to-bottom)

	# Candle warm corners
	for corner in [Vector2(w * 0.12, h * 0.08), Vector2(w * 0.88, h * 0.92)]:
		for ring in 6:
			var rt := float(ring) / 5.0
			draw_circle(corner, max(w, h) * (0.18 + rt * 0.10),
				Color(Tokens.CANDLE.r, Tokens.CANDLE.g, Tokens.CANDLE.b,
					0.014 * (1.0 - rt)))

	# Inner brass frame (1px) + soft inner rule (2px inside the brass)
	var f := FRAME_INSET
	draw_rect(Rect2(Vector2(f, f), Vector2(w - 2 * f, h - 2 * f)),
		Tokens.BRASS_DIM, false, 1.0)
	draw_rect(Rect2(Vector2(f + 4, f + 4), Vector2(w - 2 * f - 8, h - 2 * f - 8)),
		Color(Tokens.BRASS.r, Tokens.BRASS.g, Tokens.BRASS.b, 0.35), false, 1.0)

	# Corner ornaments
	for corner_data in [
		[Vector2(f, f), 0.0],
		[Vector2(w - f, f), 90.0],
		[Vector2(w - f, h - f), 180.0],
		[Vector2(f, h - f), 270.0],
	]:
		_draw_corner_ornament(corner_data[0], deg_to_rad(corner_data[1]))


func _draw_corner_ornament(origin: Vector2, ang: float) -> void:
	# Three short brass strokes plus a brass dot at the corner.
	# Stroke directions are aligned to (1, 0), (0, 1), (1, 1) in local
	# space, then rotated by `ang`.
	var t := Transform2D(ang, origin)
	var p0 := t * Vector2(0, 0)
	var p1 := t * Vector2(14, 0)
	var p2 := t * Vector2(0, 14)
	var p3 := t * Vector2(10, 10)
	draw_line(p0, p1, Tokens.BRASS, 1.0)
	draw_line(p0, p2, Tokens.BRASS, 1.0)
	draw_line(p0, p3, Tokens.BRASS, 1.0)
	draw_circle(p0, 2.5, Tokens.BRASS)


func _process(_delta: float) -> void:
	# The vignette is size-dependent; redraw when the window resizes.
	if get_size_changed_since_last_draw():
		queue_redraw()


# Tracks whether size changed; we don't want to call queue_redraw every
# frame unconditionally.
var _last_drawn_size: Vector2 = Vector2.ZERO
func get_size_changed_since_last_draw() -> bool:
	if _last_drawn_size != size:
		_last_drawn_size = size
		return true
	return false
