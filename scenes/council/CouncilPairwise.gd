extends Control
##
## Bilateral dossier — opens when a sociogram crest is clicked.
##
## Renders two crests (me + the focused player) with a ScalesOfLeverage
## between them, the leverage ledger numbers, the recent betrayal log
## involving this pair, and stance history.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md (Phase 2d)
##

const ShellScript           = preload("res://components/CouncilShell.gd")
const CrestScript           = preload("res://components/Crest.gd")
const ScalesScript          = preload("res://components/ScalesOfLeverage.gd")
const BrassPlateScript      = preload("res://components/BrassPlate.gd")

signal close_pressed

var council_game: Node = null
var focus_player: int = -1

var _root_layer: Control = null
var _me_crest = null
var _them_crest = null
var _scales = null
var _leverage_label: Label
var _ledger_label: Label
var _stance_label: Label
var _betrayals_box: VBoxContainer
var _me_stats_label: Label
var _them_stats_label: Label
var _recent_intents_box: VBoxContainer
var _their_stances_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game
	if council_game.has_signal("view_changed"):
		council_game.view_changed.connect(_on_view_changed)
	if council_game.view_model != null:
		_on_view_changed(council_game.view_model)


func set_focus_player(pid: int) -> void:
	focus_player = pid
	if council_game and council_game.view_model:
		_on_view_changed(council_game.view_model)


func _build_layout() -> void:
	var shell = ShellScript.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_layer)

	# Title plate
	var title_plate = BrassPlateScript.new()
	title_plate.text = "BILATERAL DOSSIER"
	title_plate.font_size_px = 12
	title_plate.position = Vector2(60, 60)
	_root_layer.add_child(title_plate)

	# Me / Them crests on either side, scales in middle
	_me_crest = CrestScript.new()
	_me_crest.crest_size = 140
	_me_crest.position = Vector2(180, 180)
	_root_layer.add_child(_me_crest)

	_them_crest = CrestScript.new()
	_them_crest.crest_size = 140
	_them_crest.position = Vector2(900, 180)
	_root_layer.add_child(_them_crest)

	_scales = ScalesScript.new()
	_scales.position = Vector2(640, 280)
	_scales.scales_size = 180
	_root_layer.add_child(_scales)

	_leverage_label = Label.new()
	_leverage_label.add_theme_font_override(
		"font", load(Tokens.FONT_DISPLAY) as Font
	)
	_leverage_label.add_theme_font_size_override("font_size", 28)
	_leverage_label.add_theme_color_override("font_color", Tokens.CANDLE)
	_leverage_label.position = Vector2(540, 200)
	_leverage_label.size = Vector2(200, 36)
	_leverage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leverage_label.text = "—"
	_root_layer.add_child(_leverage_label)

	_ledger_label = Label.new()
	_ledger_label.add_theme_font_override(
		"font", load(Tokens.FONT_SERIF_ITALIC) as Font
	)
	_ledger_label.add_theme_font_size_override("font_size", 14)
	_ledger_label.add_theme_color_override("font_color", Tokens.BONE_DIM)
	_ledger_label.position = Vector2(540, 240)
	_ledger_label.size = Vector2(200, 24)
	_ledger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ledger_label.text = ""
	_root_layer.add_child(_ledger_label)

	# Per-side stats labels under each crest.
	_me_stats_label = _make_stats_label()
	_me_stats_label.position = Vector2(110, 340)
	_me_stats_label.size = Vector2(220, 56)
	_root_layer.add_child(_me_stats_label)

	_them_stats_label = _make_stats_label()
	_them_stats_label.position = Vector2(830, 340)
	_them_stats_label.size = Vector2(220, 56)
	_root_layer.add_child(_them_stats_label)

	# Recent declarations panel (their last_press intents).
	var recent_plate = BrassPlateScript.new()
	recent_plate.text = "THEIR RECENT DECLARATIONS"
	recent_plate.font_size_px = 11
	recent_plate.position = Vector2(440, 360)
	_root_layer.add_child(recent_plate)

	_recent_intents_box = VBoxContainer.new()
	_recent_intents_box.position = Vector2(440, 400)
	_recent_intents_box.size = Vector2(400, 80)
	_recent_intents_box.add_theme_constant_override("separation", 4)
	_root_layer.add_child(_recent_intents_box)

	# Their stances toward everyone — read of their wider posture.
	_their_stances_label = Label.new()
	_their_stances_label.add_theme_font_override(
		"font", load(Tokens.FONT_SERIF_ITALIC) as Font
	)
	_their_stances_label.add_theme_font_size_override("font_size", 13)
	_their_stances_label.add_theme_color_override("font_color", Tokens.BONE_DIM)
	_their_stances_label.position = Vector2(60, 504)
	_their_stances_label.size = Vector2(1160, 22)
	_their_stances_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_their_stances_label.text = ""
	_root_layer.add_child(_their_stances_label)

	_stance_label = Label.new()
	_stance_label.add_theme_font_override(
		"font", load(Tokens.FONT_SANS) as Font
	)
	_stance_label.add_theme_font_size_override("font_size", 12)
	_stance_label.add_theme_color_override("font_color", Tokens.BRASS)
	_stance_label.position = Vector2(60, 480)
	_stance_label.size = Vector2(1160, 22)
	_stance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stance_label.text = ""
	_root_layer.add_child(_stance_label)

	# Betrayals header + list
	var betrayals_plate = BrassPlateScript.new()
	betrayals_plate.text = "BETRAYALS OBSERVED"
	betrayals_plate.font_size_px = 11
	betrayals_plate.position = Vector2(60, 530)
	_root_layer.add_child(betrayals_plate)

	_betrayals_box = VBoxContainer.new()
	_betrayals_box.position = Vector2(60, 570)
	_betrayals_box.size = Vector2(1160, 200)
	_betrayals_box.add_theme_constant_override("separation", 4)
	_root_layer.add_child(_betrayals_box)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "  Close  "
	close_btn.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.position = Vector2(1140, 60)
	close_btn.size = Vector2(80, 32)
	close_btn.pressed.connect(func(): close_pressed.emit())
	_root_layer.add_child(close_btn)


func _on_view_changed(vm) -> void:
	if vm == null or _me_crest == null:
		return
	var me: int = int(vm.my_player_id())
	var them: int = focus_player
	if them < 0:
		# Default focus: pick the player with the most absolute leverage.
		them = _default_focus(vm, me)

	_me_crest.player_id = me
	_them_crest.player_id = them

	var lev_me_them: int = int(vm.leverage(me, them))
	var aid_me_them: int = int(vm.aid_given(me, them))
	var aid_them_me: int = int(vm.aid_given(them, me))

	_scales.left_load = aid_me_them
	_scales.right_load = aid_them_me
	# Tilt: positive when right is heavier
	var total: int = aid_me_them + aid_them_me
	if total == 0:
		_scales.tilt = 0.0
	else:
		_scales.tilt = clamp(
			float(aid_them_me - aid_me_them) / float(max(1, total)) * 1.2,
			-1.0, 1.0
		)

	if lev_me_them > 0:
		_leverage_label.text = "leverage +%d (you owe me)" % lev_me_them
	elif lev_me_them < 0:
		_leverage_label.text = "leverage %d (I owe you)" % lev_me_them
	else:
		_leverage_label.text = "even"
	_ledger_label.text = "given %d · received %d" % [aid_me_them, aid_them_me]

	var s_me_them: String = String(vm.stance(me, them))
	var s_them_me: String = String(vm.stance(them, me))
	_stance_label.text = "STANCE — %s → %s : %s    /    %s → %s : %s" % [
		Tokens.faction_tag(me), Tokens.faction_tag(them), s_me_them.to_upper(),
		Tokens.faction_tag(them), Tokens.faction_tag(me), s_them_me.to_upper(),
	]

	# Per-side score + unit count.
	_me_stats_label.text = "%s\nscore %d · %s" % [
		Tokens.faction_tag(me),
		int(vm.score(me)),
		_units_phrase(vm.units_owned_by(me).size()),
	]
	_them_stats_label.text = "%s\nscore %d · %s" % [
		Tokens.faction_tag(them),
		int(vm.score(them)),
		_units_phrase(vm.units_owned_by(them).size()),
	]

	# Their last-locked-press intents — what did they publish last turn?
	for c in _recent_intents_box.get_children():
		c.queue_free()
	var their_press: Variant = vm._raw.get("last_press", {}).get(str(them))
	var their_intents: Array = []
	if their_press != null:
		their_intents = their_press.get("intents", [])
	if their_intents.is_empty():
		_recent_intents_box.add_child(_dim_label(
			"(no declarations on record)"))
	else:
		for it in their_intents:
			var ord: Dictionary = it.get("declared_order", {})
			var verb := String(ord.get("type", "?"))
			var detail := ""
			if ord.has("dest"):
				detail = "→n%s" % str(ord["dest"])
			elif ord.has("target_unit"):
				detail = "·u%s" % str(ord["target_unit"])
			var line := Label.new()
			line.text = "  u%d  %s%s" % [
				int(it.get("unit_id", -1)),
				verb.to_upper(),
				detail,
			]
			line.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
			line.add_theme_font_size_override("font_size", 14)
			line.add_theme_color_override("font_color", Tokens.BONE)
			_recent_intents_box.add_child(line)

	# Their stance toward every other player — broader posture read.
	var stance_parts: Array = []
	if their_press != null:
		var their_stance: Dictionary = their_press.get("stance", {})
		for other in vm.num_players():
			if other == them:
				continue
			var s: Variant = their_stance.get(str(other))
			if s == null:
				continue
			stance_parts.append("%s→%s:%s" % [
				Tokens.faction_tag(them),
				Tokens.faction_tag(int(other)),
				String(s).to_upper(),
			])
	if stance_parts.is_empty():
		_their_stances_label.text = "(no broader stance on record)"
	else:
		_their_stances_label.text = "  ·  ".join(stance_parts)

	# Betrayal log filtered to this pair.
	for c in _betrayals_box.get_children():
		c.queue_free()
	for b in vm.your_betrayals():
		var betrayer: int = int(b.get("betrayer", -1))
		if betrayer != them:
			continue
		_betrayals_box.add_child(_betrayal_row(b))
	if _betrayals_box.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "(no betrayals from this player)"
		empty.add_theme_font_override(
			"font", load(Tokens.FONT_SERIF_ITALIC) as Font
		)
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Tokens.BONE_DIM)
		_betrayals_box.add_child(empty)


func _default_focus(vm, me: int) -> int:
	## Pick the non-me player with the largest |leverage| as the
	## default focus when no specific click happened.
	var best_pid := -1
	var best_mag := -1
	for pid in vm.num_players():
		if pid == me:
			continue
		var mag: int = int(abs(vm.leverage(me, pid)))
		if mag > best_mag:
			best_mag = mag
			best_pid = pid
	if best_pid < 0:
		# No leverage with anyone — pick player_id (me+1) % n.
		best_pid = (me + 1) % max(1, vm.num_players())
	return best_pid


func _units_phrase(n: int) -> String:
	return "%d unit" % n if n == 1 else "%d units" % n


func _make_stats_label() -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Tokens.BONE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(Tokens.FONT_SERIF_ITALIC) as Font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Tokens.BONE_DIM)
	return l


func _betrayal_row(b: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var turn_label := Label.new()
	turn_label.text = "T%d" % int(b.get("turn", 0))
	turn_label.add_theme_font_override("font", load(Tokens.FONT_MONO) as Font)
	turn_label.add_theme_font_size_override("font_size", 13)
	turn_label.add_theme_color_override("font_color", Tokens.EMBER)
	turn_label.custom_minimum_size = Vector2(40, 0)
	row.add_child(turn_label)
	var intent: Dictionary = b.get("intent", {})
	var declared: Dictionary = intent.get("declared_order", {})
	var actual: Dictionary = b.get("actual_order", {})
	var unit_id: int = int(intent.get("unit_id", -1))
	var msg := Label.new()
	msg.text = "u%d declared %s but issued %s" % [
		unit_id,
		String(declared.get("type", "?")),
		String(actual.get("type", "?")),
	]
	msg.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", Tokens.BONE)
	row.add_child(msg)
	return row
