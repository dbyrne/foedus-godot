extends Control
class_name CourtPanel
##
## Right-rail panel for the Negotiation screen.
##
## Stacks four blocks vertically:
##   1. BrassPlate "THE COURT" header
##   2. Sociogram (4 crests + leverage arcs)
##   3. Stance dropdowns (one per other player)
##   4. Aid balance + per-ally aid-spend toggles
##   5. Chat draft (multi-line edit + send button)
##
## Pure layout / signal forwarding. PressController (separate) owns
## turn-local state.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const SociogramScript  = preload("res://components/Sociogram.gd")
const BrassPlateScript = preload("res://components/BrassPlate.gd")

signal stance_changed(other_pid: int, new_stance: String)
signal aid_spend_toggled(target_unit_id: int, on: bool)
signal chat_text_changed(text: String)
signal chat_submitted(text: String)
signal seal_pressed()

var _view_model = null  # ViewModel
var _sociogram: Node = null
var _stance_box: VBoxContainer
var _aid_box: VBoxContainer
var _chat_edit: TextEdit
var _seal_btn: Button


func set_view_model(vm) -> void:
	_view_model = vm
	_refresh()


func _ready() -> void:
	custom_minimum_size = Vector2(540, 700)
	_build_structure()
	_refresh()


func _build_structure() -> void:
	# Outer VBox
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	# Header plate
	var plate = BrassPlateScript.new()
	plate.text = "THE COURT"
	plate.font_size_px = 12
	v.add_child(plate)

	# Sociogram
	_sociogram = SociogramScript.new()
	_sociogram.custom_minimum_size = Vector2(520, 220)
	v.add_child(_sociogram)

	# Stance dropdowns container
	var stance_header = BrassPlateScript.new()
	stance_header.text = "STANCES"
	stance_header.font_size_px = 10
	v.add_child(stance_header)
	_stance_box = VBoxContainer.new()
	_stance_box.add_theme_constant_override("separation", 4)
	v.add_child(_stance_box)

	# Aid spending
	var aid_header = BrassPlateScript.new()
	aid_header.text = "AID"
	aid_header.font_size_px = 10
	v.add_child(aid_header)
	_aid_box = VBoxContainer.new()
	_aid_box.add_theme_constant_override("separation", 4)
	v.add_child(_aid_box)

	# Chat
	var chat_header = BrassPlateScript.new()
	chat_header.text = "DISPATCH"
	chat_header.font_size_px = 10
	v.add_child(chat_header)
	_chat_edit = TextEdit.new()
	_chat_edit.custom_minimum_size = Vector2(520, 80)
	_chat_edit.placeholder_text = "Address the council…"
	_chat_edit.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	_chat_edit.add_theme_font_size_override("font_size", 14)
	_chat_edit.add_theme_color_override("font_color", Tokens.BONE)
	_chat_edit.text_changed.connect(_on_chat_changed)
	v.add_child(_chat_edit)

	_seal_btn = Button.new()
	_seal_btn.text = "  Seal Intent  "
	_seal_btn.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	_seal_btn.add_theme_font_size_override("font_size", 12)
	_seal_btn.pressed.connect(_on_seal)
	v.add_child(_seal_btn)


func _refresh() -> void:
	if _view_model == null or _sociogram == null:
		return
	_sociogram.set_view_model(_view_model)
	_rebuild_stance_dropdowns()
	_rebuild_aid_toggles()


func _rebuild_stance_dropdowns() -> void:
	for c in _stance_box.get_children():
		c.queue_free()
	var me: int = int(_view_model.my_player_id())
	var n: int = int(_view_model.num_players())
	for other_pid in n:
		if other_pid == me:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [
			Tokens.faction_name(other_pid), Tokens.faction_tag(other_pid)
		]
		name_lbl.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Tokens.BONE)
		name_lbl.custom_minimum_size = Vector2(160, 0)
		row.add_child(name_lbl)
		var dd := OptionButton.new()
		dd.add_item("ally", 0)
		dd.add_item("neutral", 1)
		dd.add_item("hostile", 2)
		var current_stance: String = String(_view_model.stance(me, other_pid))
		match current_stance:
			"ally": dd.select(0)
			"hostile": dd.select(2)
			_: dd.select(1)
		dd.item_selected.connect(_on_stance_selected.bind(other_pid))
		row.add_child(dd)
		_stance_box.add_child(row)


func _rebuild_aid_toggles() -> void:
	for c in _aid_box.get_children():
		c.queue_free()
	var balance := int(_view_model.aid_tokens(_view_model.my_player_id()))
	var balance_lbl := Label.new()
	balance_lbl.text = "Tokens available: %d" % balance
	balance_lbl.add_theme_font_override(
		"font", load(Tokens.FONT_SERIF_ITALIC) as Font
	)
	balance_lbl.add_theme_font_size_override("font_size", 13)
	balance_lbl.add_theme_color_override("font_color", Tokens.CANDLE)
	_aid_box.add_child(balance_lbl)
	# One toggle per other player, "Spend 1 token on <name>".
	var me: int = int(_view_model.my_player_id())
	var n: int = int(_view_model.num_players())
	for other_pid in n:
		if other_pid == me:
			continue
		var btn := CheckBox.new()
		btn.text = "  Spend on %s" % Tokens.faction_name(other_pid)
		btn.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Tokens.BONE)
		btn.toggled.connect(_on_aid_toggle.bind(other_pid))
		_aid_box.add_child(btn)


# --- Signal forwarding --------------------------------------------------

func _on_stance_selected(idx: int, other_pid: int) -> void:
	var stance: String = ["ally", "neutral", "hostile"][idx]
	stance_changed.emit(other_pid, stance)


func _on_aid_toggle(toggled: bool, other_pid: int) -> void:
	# In Phase 2a, "spend on player X" is a coarse boolean; the actual
	# AidSpend payload picks any of X's units. Phase 2b will refine to
	# per-unit selection.
	aid_spend_toggled.emit(other_pid, toggled)


func _on_chat_changed() -> void:
	chat_text_changed.emit(_chat_edit.text)


func _on_seal() -> void:
	chat_submitted.emit(_chat_edit.text)
	seal_pressed.emit()
