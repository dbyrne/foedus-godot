extends Control
class_name BrassPlate
##
## Engraved label chrome — the small caps brass plates used as section
## headers throughout the War Council UI.
##
## Visual: brass→brassDim vertical gradient, 1px ink border, drop
## shadow, ink-colored small-caps text in bold sans, wide tracking.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##

@export var text: String = "" :
	set(value):
		text = value
		_apply_text()

@export var font_size_px: int = 10 :
	set(value):
		font_size_px = value
		_apply_text()

@export_range(2, 30, 1) var pad_x: int = 14
@export_range(2, 30, 1) var pad_y: int = 5

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_apply_text()

func _apply_text() -> void:
	if _label == null:
		return
	_label.text = text.to_upper()
	_label.add_theme_font_override(
		"font", load(Tokens.FONT_SANS) as FontFile
	)
	_label.add_theme_font_size_override("font_size", font_size_px)
	_label.add_theme_color_override("font_color", Tokens.INK)
	# wide tracking — Godot 4.3 doesn't expose CSS-style letter-spacing on
	# Label, so we approximate via spaces. The design's 0.3em equivalent
	# at 10px is ~3px per gap; users perceive small-caps tracking via
	# the inserted thin spaces.
	_label.text = " ".join(text.to_upper().split(""))
	# Resize self to label's natural size + padding.
	var lbl_size := _label.get_minimum_size()
	custom_minimum_size = Vector2(
		max(custom_minimum_size.x, lbl_size.x + pad_x * 2),
		max(custom_minimum_size.y, lbl_size.y + pad_y * 2)
	)
	queue_redraw()

func _draw() -> void:
	var sz := size
	# Drop shadow
	draw_rect(Rect2(Vector2(0, 2), sz), Color(0, 0, 0, 0.4), true)
	# Brass gradient: top bright → bottom dim. Approximate with 16
	# horizontal slabs.
	var slabs := 16
	for i in slabs:
		var t := float(i) / float(slabs - 1)
		var c := Tokens.BRASS.lerp(Tokens.BRASS_DIM, t)
		var slab_h := sz.y / float(slabs)
		draw_rect(Rect2(Vector2(0, slab_h * i), Vector2(sz.x, slab_h + 0.5)), c, true)
	# Inner highlight (top edge)
	draw_rect(Rect2(Vector2(0, 0), Vector2(sz.x, 1)), Color(1, 1, 1, 0.4), true)
	# Border
	draw_rect(Rect2(Vector2.ZERO, sz), Tokens.INK, false, 1.0)
