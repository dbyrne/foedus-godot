extends Control
class_name TensionMeter
##
## Phase + countdown + heartbeat bar — sits at the top of every game
## screen. Color shifts between negotiation (candle/brass) and orders
## (ember/blood) phases.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

const PHASE_NEGOTIATION := "negotiation"
const PHASE_ORDERS      := "orders"

@export_enum("negotiation", "orders") var phase: String = "negotiation" :
	set(value): phase = value; _refresh_text(); queue_redraw()

@export var timer_text: String = "02:14" :
	set(value): timer_text = value; _refresh_text(); queue_redraw()

@export_range(0.0, 1.0, 0.01) var value: float = 0.5 :
	set(value): value = value; queue_redraw()

var _phase_label: Label
var _timer_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(360, 36)
	_phase_label = Label.new()
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_label.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	_phase_label.add_theme_font_size_override("font_size", 10)
	_phase_label.add_theme_color_override("font_color", Tokens.BRASS)
	add_child(_phase_label)

	_timer_label = Label.new()
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label.add_theme_font_override("font", load(Tokens.FONT_MONO) as Font)
	_timer_label.add_theme_font_size_override("font_size", 14)
	add_child(_timer_label)
	_refresh_text()


func _refresh_text() -> void:
	if _phase_label == null:
		return
	var phase_str := "II · ORDERS" if phase == PHASE_ORDERS else "I · NEGOTIATION"
	_phase_label.text = " ".join(phase_str.split(""))
	_timer_label.text = timer_text
	_timer_label.add_theme_color_override(
		"font_color",
		Tokens.EMBER if phase == PHASE_ORDERS else Tokens.CANDLE
	)
	_position_labels()


func _position_labels() -> void:
	if _phase_label == null:
		return
	_phase_label.position = Vector2(18, (size.y - 14) * 0.5)
	_phase_label.size = Vector2(180, 16)
	_timer_label.position = Vector2(size.x - 60, (size.y - 18) * 0.5)
	_timer_label.size = Vector2(46, 18)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _process(_delta: float) -> void:
	if _phase_label != null:
		_position_labels()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Outer panel
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.4), true)
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.BRASS_DIM, false, 1.0)

	# Phase label is drawn by the _phase_label Label child (handles
	# variable fonts via theme overrides correctly).

	# Vertical divider
	var divider_x := 200.0
	draw_line(Vector2(divider_x, h * 0.25), Vector2(divider_x, h * 0.75),
		Tokens.BRASS_DIM, 1.0)

	# Heartbeat fill bar
	var bar_x := divider_x + 12
	var bar_y := h / 2 - 3
	var bar_w := w - bar_x - 70
	var bar_h := 6.0
	# Track
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)),
		Color(0, 0, 0, 0.5), true)
	# Fill — gradient by lerp slabs
	var fill_w := bar_w * value
	var slabs := 24
	var c0 := Tokens.CANDLE if phase == PHASE_NEGOTIATION else Tokens.EMBER
	var c1 := Tokens.BRASS  if phase == PHASE_NEGOTIATION else Tokens.BLOOD
	for i in slabs:
		var t := float(i) / float(slabs - 1)
		var sx := bar_x + (fill_w / slabs) * i
		var sw := fill_w / slabs + 0.5
		if sx + sw > bar_x + fill_w:
			sw = (bar_x + fill_w) - sx
		if sw > 0:
			draw_rect(Rect2(Vector2(sx, bar_y), Vector2(sw, bar_h)),
				c0.lerp(c1, t), true)

	# Heartbeat polyline overlay (decorative ECG)
	var ecg_pts := PackedVector2Array()
	var samples := 32
	for i in samples + 1:
		var t := float(i) / samples
		var x := bar_x + bar_w * t
		var y := bar_y + bar_h / 2
		var phase_t := t * 4.0
		var spike := 0.0
		if phase_t > 1.0 and phase_t < 1.3:
			spike = -bar_h * 0.5
		elif phase_t > 1.3 and phase_t < 1.6:
			spike =  bar_h * 0.5
		ecg_pts.append(Vector2(x, y + spike))
	for i in ecg_pts.size() - 1:
		draw_line(ecg_pts[i], ecg_pts[i + 1], Color(Tokens.BONE, 0.6), 0.6)

	# Timer is drawn by the _timer_label Label child.
