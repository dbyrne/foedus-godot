extends Control
##
## Win / end-of-game screen.
##
## Renders one large crowned crest per winner (multi-winner détente
## victories show all crested side-by-side), a score-breakdown table,
## the détente-vs-score-victory flag, and a "view replay" button.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md (Phase 2d)
##

const ShellScript      = preload("res://components/CouncilShell.gd")
const CrestScript      = preload("res://components/Crest.gd")
const BrassPlateScript = preload("res://components/BrassPlate.gd")

signal view_replay_pressed
signal exit_pressed

var council_game: Node = null
var _root_layer: Control = null
var _crests_row: HBoxContainer
var _score_grid: GridContainer
var _victory_label: Label
var _winners_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game
	if council_game.has_signal("view_changed"):
		council_game.view_changed.connect(_on_view_changed)
	if council_game.view_model != null:
		_on_view_changed(council_game.view_model)


func _build_layout() -> void:
	var shell = ShellScript.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_layer)

	# Centered title
	var title := Label.new()
	title.text = "VICTORY"
	title.add_theme_font_override("font", load(Tokens.FONT_DISPLAY) as Font)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Tokens.CANDLE)
	title.position = Vector2(0, 80)
	title.size = Vector2(1280, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_layer.add_child(title)

	_victory_label = Label.new()
	_victory_label.text = "—"
	_victory_label.add_theme_font_override(
		"font", load(Tokens.FONT_SERIF_ITALIC) as Font
	)
	_victory_label.add_theme_font_size_override("font_size", 22)
	_victory_label.add_theme_color_override("font_color", Tokens.BONE_DIM)
	_victory_label.position = Vector2(0, 170)
	_victory_label.size = Vector2(1280, 30)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_layer.add_child(_victory_label)

	# Crests row centered
	_crests_row = HBoxContainer.new()
	_crests_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_crests_row.add_theme_constant_override("separation", 30)
	_crests_row.position = Vector2(0, 220)
	_crests_row.size = Vector2(1280, 200)
	_root_layer.add_child(_crests_row)

	_winners_label = Label.new()
	_winners_label.text = "—"
	_winners_label.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
	_winners_label.add_theme_font_size_override("font_size", 18)
	_winners_label.add_theme_color_override("font_color", Tokens.BONE)
	_winners_label.position = Vector2(0, 430)
	_winners_label.size = Vector2(1280, 28)
	_winners_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_layer.add_child(_winners_label)

	# Score breakdown (BrassPlate header + 4-row grid)
	var score_plate = BrassPlateScript.new()
	score_plate.text = "FINAL SCORES"
	score_plate.font_size_px = 11
	score_plate.position = Vector2(440, 480)
	_root_layer.add_child(score_plate)

	_score_grid = GridContainer.new()
	_score_grid.columns = 3
	_score_grid.add_theme_constant_override("h_separation", 24)
	_score_grid.add_theme_constant_override("v_separation", 6)
	_score_grid.position = Vector2(440, 520)
	_score_grid.size = Vector2(400, 200)
	_root_layer.add_child(_score_grid)

	# Buttons
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	actions.position = Vector2(0, 760)
	actions.size = Vector2(1280, 50)
	_root_layer.add_child(actions)

	var replay := _make_button("View Replay")
	replay.pressed.connect(func(): view_replay_pressed.emit())
	actions.add_child(replay)

	var quit_btn := _make_button("Exit")
	quit_btn.pressed.connect(func(): exit_pressed.emit())
	actions.add_child(quit_btn)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.add_theme_font_override("font", load(Tokens.FONT_SANS) as Font)
	b.add_theme_font_size_override("font_size", 12)
	return b


func _on_view_changed(vm) -> void:
	if vm == null or _crests_row == null:
		return
	# Clear existing crests + scores.
	for c in _crests_row.get_children():
		c.queue_free()
	for c in _score_grid.get_children():
		c.queue_free()

	# Victory mode.
	if vm.detente_reached():
		_victory_label.text = "by treaty — détente prevailed"
	else:
		_victory_label.text = "by force of arms"

	# Winners — render large crests.
	var winners: Array = vm.winners()
	for pid_v in winners:
		var pid: int = int(pid_v)
		var crest = CrestScript.new()
		crest.player_id = pid
		crest.crest_size = 160
		_crests_row.add_child(crest)

	if winners.is_empty():
		_winners_label.text = "(no clear victor)"
	elif winners.size() == 1:
		_winners_label.text = "%s of %s reigns triumphant" % [
			Tokens.faction_name(int(winners[0])),
			Tokens.faction_tag(int(winners[0])),
		]
	else:
		var names: Array = []
		for pid in winners:
			names.append(Tokens.faction_name(int(pid)))
		_winners_label.text = "Sovereigns: " + ", ".join(names)

	# Final scoreboard — sorted descending.
	var rows: Array = []
	for pid in vm.num_players():
		rows.append({"pid": pid, "score": vm.score(pid)})
	rows.sort_custom(func(a, b): return a.score > b.score)
	for row in rows:
		var pid: int = int(row.pid)
		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [
			Tokens.faction_name(pid), Tokens.faction_tag(pid)
		]
		name_lbl.add_theme_font_override("font", load(Tokens.FONT_SERIF) as Font)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Tokens.BONE)
		name_lbl.custom_minimum_size = Vector2(180, 0)
		_score_grid.add_child(name_lbl)
		var score_lbl := Label.new()
		score_lbl.text = "%.1f" % float(row.score)
		score_lbl.add_theme_font_override("font", load(Tokens.FONT_MONO) as Font)
		score_lbl.add_theme_font_size_override("font_size", 16)
		score_lbl.add_theme_color_override(
			"font_color",
			Tokens.CANDLE if pid in winners else Tokens.BONE_DIM
		)
		score_lbl.custom_minimum_size = Vector2(80, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_score_grid.add_child(score_lbl)
		var status_lbl := Label.new()
		status_lbl.text = "✦ Sovereign" if pid in winners else "—"
		status_lbl.add_theme_font_override(
			"font", load(Tokens.FONT_SERIF_ITALIC) as Font
		)
		status_lbl.add_theme_font_size_override("font_size", 14)
		status_lbl.add_theme_color_override(
			"font_color",
			Tokens.CANDLE if pid in winners else Tokens.BONE_DIM
		)
		_score_grid.add_child(status_lbl)
