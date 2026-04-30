extends Control
##
## Resolution playback screen — animates the events between two
## consecutive snapshots (prev → curr).
##
## Animation strategy:
##   - Hex board renders the PREV snapshot's state.
##   - For each event in ResolutionTimeline order, schedule a Tween
##     beat:
##       * move event:      lerp the unit's UnitPiece from prev → curr
##                          hex over MOVE_DURATION
##       * dislodge event:  CombatBeat flash at the hex; remove the
##                          UnitPiece
##       * leverage event:  thin gold thread from src → tgt for a
##                          short flash
##       * score event:     small floating "+N" wax-seal mote rising
##                          from the player's home hex
##   - When the timeline finishes, swap to the CURR snapshot's state
##     and emit `playback_finished`.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md (Phase 2c)
##

const ShellScript        = preload("res://components/CouncilShell.gd")
const HexBoardScript     = preload("res://components/HexBoard.gd")
const TensionScript      = preload("res://components/TensionMeter.gd")
const BrassPlateScript   = preload("res://components/BrassPlate.gd")
const CombatBeatScript   = preload("res://components/CombatBeat.gd")
const ViewModelScript    = preload("res://scripts/council/ViewModel.gd")
const TimelineScript     = preload("res://scripts/council/ResolutionTimeline.gd")

const MOVE_DURATION  := 0.50
const BEAT_DURATION  := 0.50
const LEVERAGE_FLASH := 0.30
const INTER_EVENT_GAP := 0.12

signal playback_finished

var council_game: Node = null
var _shell: Node = null
var _hex_board: Node = null
var _tension: Node = null
var _root_layer: Control = null
var _arrow_layer: Node2D = null
var _events: Array = []
var _prev_view_model = null
var _curr_view_model = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()


func attach_game(game) -> void:
	council_game = game


func play_between(prev_view: Dictionary, curr_view: Dictionary) -> void:
	## Public entry: kick off the playback animation.
	_prev_view_model = ViewModelScript.new(prev_view)
	_curr_view_model = ViewModelScript.new(curr_view)
	_events = TimelineScript.from_snapshots(prev_view, curr_view)
	_hex_board.set_view_model(_prev_view_model)
	_tension.phase = "orders"
	_tension.timer_text = "T %d → %d" % [
		_prev_view_model.turn(), _curr_view_model.turn()
	]
	_tension.value = 1.0
	# Schedule events sequentially.
	_play_next_event(0)


func _build_layout() -> void:
	_shell = ShellScript.new()
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shell)

	_root_layer = Control.new()
	_root_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_layer)

	_tension = TensionScript.new()
	_tension.position = Vector2(60, 50)
	_tension.custom_minimum_size = Vector2(1160, 36)
	_tension.size = Vector2(1160, 36)
	_tension.phase = "orders"
	_root_layer.add_child(_tension)

	var board_label = BrassPlateScript.new()
	board_label.text = "RESOLUTION"
	board_label.font_size_px = 11
	board_label.position = Vector2(60, 100)
	_root_layer.add_child(board_label)

	var board_wrap := Control.new()
	board_wrap.position = Vector2(60, 132)
	board_wrap.size = Vector2(1160, 700)
	_root_layer.add_child(board_wrap)
	_hex_board = HexBoardScript.new()
	_hex_board.position = Vector2(580, 350)
	board_wrap.add_child(_hex_board)
	# Arrow / effect layer matches HexBoard's transform.
	_arrow_layer = Node2D.new()
	_arrow_layer.position = _hex_board.position
	board_wrap.add_child(_arrow_layer)


func _play_next_event(idx: int) -> void:
	if idx >= _events.size():
		_finish_playback()
		return
	var ev: Dictionary = _events[idx]
	match String(ev.get("kind", "")):
		"move":
			_play_move_event(ev, idx)
		"dislodge":
			_play_dislodge_event(ev, idx)
		"leverage":
			_play_leverage_event(ev, idx)
		_:
			# ownership and score don't have dedicated visuals in 2c
			# (they're implied by the move/dislodge animations); skip
			# without a beat.
			_after_event(idx, 0.0)


func _play_move_event(ev: Dictionary, idx: int) -> void:
	# Visual: unit piece lerps along the hex line. We keep it simple:
	# a CombatBeat-style halo at the destination + a brief delay.
	# Phase 3 will add a real per-unit lerp by tracking individual
	# UnitPiece nodes.
	var to_node: int = int(ev.get("to_node", -1))
	var to_tile: Dictionary = _prev_view_model.tile_for_node(to_node)
	if to_tile.is_empty():
		_after_event(idx, 0.0); return
	var to_pos: Vector2 = Tokens.hex_to_px(int(to_tile["q"]), int(to_tile["r"]))
	_spawn_beat(to_pos, Tokens.player_main(int(ev.get("player_id", 0))),
		MOVE_DURATION)
	_after_event(idx, MOVE_DURATION)


func _play_dislodge_event(ev: Dictionary, idx: int) -> void:
	var at_node: int = int(ev.get("at_node", -1))
	var tile: Dictionary = _prev_view_model.tile_for_node(at_node)
	if tile.is_empty():
		_after_event(idx, 0.0); return
	var pos: Vector2 = Tokens.hex_to_px(int(tile["q"]), int(tile["r"]))
	# Blood-red beat — a kill.
	_spawn_beat(pos, Tokens.BLOOD, BEAT_DURATION)
	_after_event(idx, BEAT_DURATION)


func _play_leverage_event(ev: Dictionary, idx: int) -> void:
	# Brief gold thread from creditor's home → debtor's home.
	var from_pid: int = int(ev.get("from_player", -1))
	var to_pid: int = int(ev.get("to_player", -1))
	var from_pos: Vector2 = _home_pos_for_player(from_pid)
	var to_pos: Vector2 = _home_pos_for_player(to_pid)
	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		_after_event(idx, 0.0); return
	var line := Node2D.new()
	_arrow_layer.add_child(line)
	# Build a one-shot Node2D that draws the thread + fades.
	var thread := _ThreadFlash.new()
	thread.from_pos = from_pos
	thread.to_pos = to_pos
	thread.color = Tokens.CANDLE
	_arrow_layer.add_child(thread)
	thread.play(LEVERAGE_FLASH)
	_after_event(idx, LEVERAGE_FLASH)


func _after_event(idx: int, base_dur: float) -> void:
	var t := create_tween()
	t.tween_interval(base_dur + INTER_EVENT_GAP)
	t.tween_callback(func(): _play_next_event(idx + 1))


func _spawn_beat(pos: Vector2, color: Color, duration: float) -> void:
	var beat = CombatBeatScript.new()
	beat.position = pos
	beat.burst_color = color
	_arrow_layer.add_child(beat)
	beat.play(duration)


func _home_pos_for_player(pid: int) -> Vector2:
	if _prev_view_model == null:
		return Vector2.ZERO
	for tile in _prev_view_model.tiles():
		if tile.get("home_player") == pid:
			return Tokens.hex_to_px(int(tile["q"]), int(tile["r"]))
	return Vector2.ZERO


func _finish_playback() -> void:
	# Swap board to the post-resolution state.
	if _curr_view_model != null:
		_hex_board.set_view_model(_curr_view_model)
	playback_finished.emit()


# --- Inner helper class for short-lived gold thread effect -------------

class _ThreadFlash extends Node2D:
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	var color: Color = Color(1, 1, 1, 1)
	var t: float = 0.0 :
		set(value): t = value; queue_redraw()

	func play(duration: float) -> void:
		var tween := create_tween()
		tween.tween_property(self, "t", 1.0, duration)
		tween.tween_callback(queue_free)

	func _draw() -> void:
		var alpha: float = sin(t * PI) * 0.85
		if alpha <= 0.0:
			return
		var c := Color(color.r, color.g, color.b, alpha)
		draw_line(from_pos, to_pos, c, 2.0)
