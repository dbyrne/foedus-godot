## Bootstrap controller for foedus-godot.
##
## Order-entry flow:
##   - Click your unit on the map -> selects it. The OrderList panel shows
##     EVERY legal order for that unit (Hold, Move-to-X, Support-of-Y) as buttons.
##   - Map-click shortcuts cover the most common cases:
##     * Click own hex   -> Hold (queued)
##     * Click adjacent  -> Move (queued)
##     Anything else (Support, non-adjacent) -> use the OrderList panel.
##   - Submit orders sends the queued dict; unspecified units default to Hold.
##
## UI state machine:
##   - No active game  -> GameCreate visible, GameOverBanner hidden,
##                        ScoreboardList empty
##   - Active game     -> GameCreate hidden, ScoreboardList populated each /view
##   - Game terminal   -> GameCreate visible (so you can start another),
##                        GameOverBanner shows winner / scores
class_name Main
extends Control

const SEAT_LABELS: Array[String] = [
	"Human", "HeuristicAgent", "RandomAgent",
]

@onready var status_label: Label = $VBox/StatusLabel
@onready var games_label: Label = $VBox/GamesLabel
@onready var output_label: RichTextLabel = $VBox/HSplit/LeftPanel/OutputLabel
@onready var connect_btn: Button = $VBox/HBox/ConnectBtn
@onready var create_btn: Button = $VBox/GameCreate/HPresets/CreateBtn
@onready var preset_all_btn: Button = $VBox/GameCreate/HPresets/PresetAllBtn
@onready var preset_human_btn: Button = $VBox/GameCreate/HPresets/PresetHumanBtn
@onready var advance_btn: Button = $VBox/HBoxButtons/AdvanceBtn
@onready var auto_btn: Button = $VBox/HBoxButtons/AutoBtn
@onready var view_btn: Button = $VBox/HBoxButtons/ViewBtn
@onready var submit_btn: Button = $VBox/HBoxButtons/SubmitBtn
@onready var reset_btn: Button = $VBox/HBoxButtons/ResetBtn
@onready var url_edit: LineEdit = $VBox/HBox/UrlEdit
@onready var view_player_spin: SpinBox = $VBox/ViewSelect/ViewPlayerSpin
@onready var replay_turn_spin: SpinBox = $VBox/ViewSelect/ReplayTurnSpin
@onready var replay_live_btn: Button = $VBox/ViewSelect/ReplayLiveBtn
@onready var replay_status: Label = $VBox/ViewSelect/ReplayStatus
@onready var num_players_spin: SpinBox = $VBox/GameCreate/HSeats/NumPlayersSpin
@onready var max_turns_spin: SpinBox = $VBox/GameCreate/HConfig/MaxTurnsSpin
@onready var peace_spin: SpinBox = $VBox/GameCreate/HConfig/PeaceSpin
@onready var seed_spin: SpinBox = $VBox/GameCreate/HConfig/SeedSpin
@onready var order_list: VBoxContainer = $VBox/HSplit/LeftPanel/OrderScroll/OrderList
@onready var hex_map: Control = $VBox/HSplit/HexMap
@onready var game_create: VBoxContainer = $VBox/GameCreate
@onready var scoreboard_list: VBoxContainer = $VBox/HSplit/LeftPanel/ScoreboardList
@onready var game_over_banner: PanelContainer = $VBox/GameOverBanner
@onready var game_over_label: Label = $VBox/GameOverBanner/GameOverLabel
# Bundle 4 / press v0 UI:
@onready var send_chat_btn: Button = $VBox/HBoxButtons/SendChatBtn
@onready var skip_chat_btn: Button = $VBox/HBoxButtons/SkipChatBtn
@onready var stance_list: VBoxContainer = $VBox/HSplit/LeftPanel/Bundle4Tabs/Press/VBox/StanceList
@onready var intent_list: VBoxContainer = $VBox/HSplit/LeftPanel/Bundle4Tabs/Press/VBox/IntentList
@onready var chat_recipients_edit: LineEdit = $VBox/HSplit/LeftPanel/Bundle4Tabs/Press/VBox/ChatRow/RecipientsEdit
@onready var chat_body_edit: LineEdit = $VBox/HSplit/LeftPanel/Bundle4Tabs/Press/VBox/ChatBodyEdit
@onready var aid_balance_label: Label = $VBox/HSplit/LeftPanel/Bundle4Tabs/Aid/VBox/AidBalance
@onready var aid_spend_list: VBoxContainer = $VBox/HSplit/LeftPanel/Bundle4Tabs/Aid/VBox/AidSpendList
@onready var trust_grid: GridContainer = $VBox/HSplit/LeftPanel/Bundle4Tabs/Aid/VBox/TrustGrid
@onready var detente_indicator: Label = $VBox/HSplit/LeftPanel/Bundle4Tabs/Info/VBox/DetenteIndicator
@onready var betrayals_list: VBoxContainer = $VBox/HSplit/LeftPanel/Bundle4Tabs/Info/VBox/BetrayalsList

var seat_options: Array[OptionButton] = []
var client: GameClient
var sound: SoundManager
var current_game_id: String = ""
var current_view: Dictionary = {}
var selected_unit_id: int = -1
var pending_orders: Dictionary = {}
var _was_terminal: bool = false
# Bundle 4 / press v0 state. `pending_stance` maps other_player_id -> stance
# string ("ally"|"neutral"|"hostile"). `pending_aid` is an array of
# {target_unit} dicts ready to send on /commit.
var pending_stance: Dictionary = {}
var pending_aid: Array = []
# `pending_intents` maps unit_id (int) -> {declared_order: Dict|null,
# recipients_raw: String}. `null` declared_order = skip (don't publish an
# intent for that unit). `recipients_raw` is the raw text from the per-row
# LineEdit (empty = public broadcast; "0,2" = bilateral).
var pending_intents: Dictionary = {}
# Cached map from a "stable spend key" (target_unit:order) to
# the AidSpend dict, so toggling spend buttons can find their entry.
var _aid_spend_keys: Dictionary = {}
# Replay state. `current_live_turn` is the server's authoritative latest;
# `in_replay` is true when the user is viewing a past snapshot.
var in_replay: bool = false
var current_live_turn: int = 0


func _ready() -> void:
	client = GameClient.new()
	add_child(client)
	client.response.connect(_on_response)
	client.failure.connect(_on_failure)

	sound = SoundManager.new()
	add_child(sound)

	for i in range(6):
		var opt: OptionButton = get_node("VBox/GameCreate/HSeats/Seat%dOpt" % i)
		for label in SEAT_LABELS:
			opt.add_item(label)
		opt.select(1 if i == 0 else 2)
		seat_options.append(opt)
	num_players_spin.value_changed.connect(_on_num_players_changed)
	_apply_num_players(int(num_players_spin.value))

	connect_btn.pressed.connect(_on_connect_pressed)
	create_btn.pressed.connect(_on_create_pressed)
	preset_all_btn.pressed.connect(_on_preset_all_pressed)
	preset_human_btn.pressed.connect(_on_preset_human_pressed)
	advance_btn.pressed.connect(_on_advance_pressed)
	auto_btn.pressed.connect(_on_auto_pressed)
	view_btn.pressed.connect(_on_view_pressed)
	submit_btn.pressed.connect(_on_submit_pressed)
	send_chat_btn.pressed.connect(_on_send_chat_pressed)
	skip_chat_btn.pressed.connect(_on_skip_chat_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	view_player_spin.value_changed.connect(_on_view_player_changed)
	replay_turn_spin.value_changed.connect(_on_replay_turn_changed)
	replay_live_btn.pressed.connect(_on_replay_live_pressed)

	hex_map.unit_clicked.connect(_on_unit_clicked)
	hex_map.hex_clicked.connect(_on_hex_clicked)

	status_label.text = "Set URL and click Connect"
	games_label.text = "(no active game)"
	output_label.text = "[i]waiting...[/i]"
	game_over_banner.visible = false
	game_create.visible = true


# --- game creation ---------------------------------------------------------


func _on_num_players_changed(_v: float) -> void:
	_apply_num_players(int(num_players_spin.value))


func _apply_num_players(n: int) -> void:
	for i in range(6):
		seat_options[i].visible = (i < n)
	view_player_spin.max_value = max(0, n - 1)


func _on_preset_all_pressed() -> void:
	num_players_spin.value = 4
	_apply_num_players(4)
	seat_options[0].select(1)
	for i in range(1, 4):
		seat_options[i].select(2)


func _on_preset_human_pressed() -> void:
	num_players_spin.value = 4
	_apply_num_players(4)
	seat_options[0].select(0)
	seat_options[1].select(1)
	for i in range(2, 4):
		seat_options[i].select(2)


func _on_create_pressed() -> void:
	sound.click()
	var n: int = int(num_players_spin.value)
	var seats: Array = []
	for i in range(n):
		var idx: int = seat_options[i].selected
		match idx:
			0:
				seats.append({"type": "human", "name": "P%d" % i})
			1:
				seats.append({"type": "agent", "kind": "foedus.HeuristicAgent"})
			2:
				seats.append({
					"type": "agent",
					"kind": "foedus.RandomAgent",
					"args": {"seed": int(seed_spin.value) + i},
				})
	var config: Dictionary = {
		"num_players": n,
		"seed": int(seed_spin.value),
		"max_turns": int(max_turns_spin.value),
		"peace_threshold": int(peace_spin.value),
	}
	pending_orders.clear()
	hex_map.set_pending_orders({})
	_clear_order_list()
	_clear_scoreboard()
	game_over_banner.visible = false
	status_label.text = "creating game (%d players)..." % n
	client.create_game(config, seats)


# --- core HTTP actions -----------------------------------------------------


func _on_connect_pressed() -> void:
	client.base_url = url_edit.text.strip_edges()
	status_label.text = "checking %s/healthz..." % client.base_url
	client.healthz()


func _on_advance_pressed() -> void:
	if current_game_id.is_empty():
		return
	sound.advance()
	client.advance(current_game_id, false)


func _on_auto_pressed() -> void:
	if current_game_id.is_empty():
		return
	sound.advance()
	client.advance(current_game_id, true)


func _on_view_pressed() -> void:
	_refresh_view()


func _on_view_player_changed(_v: float) -> void:
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()
	_refresh_view()


func _on_replay_turn_changed(v: float) -> void:
	if current_game_id.is_empty():
		return
	var turn: int = int(v)
	if turn >= current_live_turn:
		# Snap back to live.
		in_replay = false
		_refresh_view()
	else:
		in_replay = true
		client.history_view(current_game_id, turn, int(view_player_spin.value))


func _on_replay_live_pressed() -> void:
	in_replay = false
	replay_turn_spin.set_value_no_signal(current_live_turn)
	_refresh_view()


func _refresh_view() -> void:
	if current_game_id.is_empty():
		return
	if in_replay:
		client.history_view(current_game_id,
				int(replay_turn_spin.value),
				int(view_player_spin.value))
	else:
		client.view(current_game_id, int(view_player_spin.value))


func _update_replay_ui() -> void:
	if in_replay:
		replay_status.text = "  [REPLAY  turn %d / live %d]" % [
			int(replay_turn_spin.value), current_live_turn
		]
		replay_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		submit_btn.disabled = true
		advance_btn.disabled = true
		auto_btn.disabled = true
	else:
		replay_status.text = "  (live)"
		replay_status.add_theme_color_override("font_color", Color(0.55, 0.78, 0.55))
		submit_btn.disabled = false
		advance_btn.disabled = false
		auto_btn.disabled = false


func _on_submit_pressed() -> void:
	## Press v0 commit: submit press tokens (stance) + orders + aid spends
	## atomically. Server returns 425 if chat phase isn't complete yet —
	## use "Skip chat" first if you didn't /chat anything else.
	if current_game_id.is_empty() or current_view.is_empty():
		return
	sound.submit()
	var orders: Dictionary = {}
	for u in current_view.get("your_units", []):
		var uid_str: String = str(u["id"])
		orders[uid_str] = pending_orders.get(uid_str, {"type": "Hold"})
	var player: int = int(view_player_spin.value)
	# Build the press payload from `pending_stance` + `pending_intents`.
	var stance_dict: Dictionary = {}
	for pid in pending_stance.keys():
		stance_dict[str(pid)] = pending_stance[pid]
	var intents: Array = _build_intents_payload()
	var press: Dictionary = {"stance": stance_dict, "intents": intents}
	status_label.text = ("commit: %d order(s), %d stance, %d intent(s), %d aid for P%d..."
			% [orders.size(), pending_stance.size(), intents.size(),
			   pending_aid.size(), player])
	client.press_commit(current_game_id, player, press, orders, pending_aid)
	pending_orders.clear()
	pending_aid.clear()
	pending_intents.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()


func _build_intents_payload() -> Array:
	## Build the press.intents array from the per-unit intent UI.
	## Each entry is {unit_id, declared_order, visible_to: null | [pid, ...]}.
	## A `null` visible_to means public broadcast; an explicit list narrows
	## the visibility to those specific recipients.
	var out: Array = []
	for uid in pending_intents.keys():
		var entry: Dictionary = pending_intents[uid]
		var declared: Variant = entry.get("declared_order", null)
		if declared == null:
			continue  # skipped
		var rec_raw: String = entry.get("recipients_raw", "")
		var visible_to: Variant = null
		if not rec_raw.is_empty():
			var rs: Array = []
			for piece in rec_raw.split(","):
				var s: String = piece.strip_edges()
				if s.is_valid_int():
					rs.append(int(s))
			if rs.size() > 0:
				visible_to = rs
		out.append({
			"unit_id": int(uid),
			"declared_order": declared,
			"visible_to": visible_to,
		})
	return out


func _on_send_chat_pressed() -> void:
	## Send a chat draft (does NOT signal chat-done). Player must still
	## click "Skip chat" or click "Commit" after the chat phase completes.
	if current_game_id.is_empty() or current_view.is_empty():
		return
	var body: String = chat_body_edit.text.strip_edges()
	if body.is_empty():
		status_label.text = "(chat body is empty; nothing sent)"
		return
	var recipients_raw: String = chat_recipients_edit.text.strip_edges()
	var recipients: Variant = null
	if not recipients_raw.is_empty():
		var rs: Array = []
		for piece in recipients_raw.split(","):
			var s: String = piece.strip_edges()
			if s.is_empty():
				continue
			if s.is_valid_int():
				rs.append(int(s))
		if rs.size() > 0:
			recipients = rs
	var player: int = int(view_player_spin.value)
	var draft: Dictionary = {"recipients": recipients, "body": body}
	client.press_chat(current_game_id, player, draft)
	chat_body_edit.text = ""
	status_label.text = "chat sent (recipients=%s)" % str(recipients)


func _on_skip_chat_pressed() -> void:
	## Signal chat-done with no message. After this returns, /commit
	## becomes valid (assuming all other humans have also signaled).
	if current_game_id.is_empty():
		return
	var player: int = int(view_player_spin.value)
	client.press_chat(current_game_id, player, null)
	status_label.text = "chat-done signaled for P%d" % player


func _on_reset_pressed() -> void:
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()
	status_label.text = "pending orders cleared"


# --- HexMap interaction ---------------------------------------------------


func _on_unit_clicked(unit_id: int, owner: int) -> void:
	var you: int = int(view_player_spin.value)
	if owner != you:
		selected_unit_id = -1
		hex_map.clear_selection()
		_clear_order_list()
		status_label.text = "(u%d belongs to player %d, not you)" % [unit_id, owner]
		return
	selected_unit_id = unit_id
	hex_map.select_unit(unit_id)
	_populate_order_list(unit_id)
	status_label.text = "selected u%d (your unit)" % unit_id


func _on_hex_clicked(node_id: int) -> void:
	if selected_unit_id < 0 or current_view.is_empty():
		return
	var unit_loc: int = -1
	for u in current_view.get("your_units", []):
		if int(u["id"]) == selected_unit_id:
			unit_loc = int(u["location"])
			break

	var legal: Array = current_view.get("legal_orders", {}).get(
			str(selected_unit_id), [])
	var chosen: Variant = null
	if node_id == unit_loc:
		for o in legal:
			if str(o.get("type", "")) == "Hold":
				chosen = o
				break
	else:
		for o in legal:
			if str(o.get("type", "")) == "Move" \
					and int(o.get("dest", -1)) == node_id:
				chosen = o
				break
	if chosen == null:
		status_label.text = "no Move/Hold from u%d to node %d (try the order panel)" % [
			selected_unit_id, node_id
		]
		return
	_queue_order(selected_unit_id, chosen)


# --- order list panel -----------------------------------------------------


func _clear_order_list() -> void:
	for child in order_list.get_children():
		child.queue_free()


func _populate_order_list(unit_id: int) -> void:
	_clear_order_list()
	var legal: Array = current_view.get("legal_orders", {}).get(
			str(unit_id), [])
	if legal.is_empty():
		var label := Label.new()
		label.text = "(no legal orders)"
		order_list.add_child(label)
		return
	var groups: Dictionary = {"Hold": [], "Move": [], "Support": []}
	for o in legal:
		var t: String = str(o.get("type", ""))
		if groups.has(t):
			groups[t].append(o)
	for group_type in ["Hold", "Move", "Support"]:
		for o in groups[group_type]:
			var btn := Button.new()
			btn.text = _format_order(o)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_order_button_pressed.bind(unit_id, o.duplicate(true)))
			order_list.add_child(btn)


func _on_order_button_pressed(unit_id: int, order: Dictionary) -> void:
	_queue_order(unit_id, order)


func _queue_order(unit_id: int, order: Dictionary) -> void:
	pending_orders[str(unit_id)] = order
	hex_map.set_pending_orders(pending_orders)
	status_label.text = "queued u%d %s (%d order%s pending)" % [
		unit_id,
		_format_order(order),
		pending_orders.size(),
		"" if pending_orders.size() == 1 else "s",
	]
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()


func _format_order(o: Dictionary) -> String:
	var t: String = str(o.get("type", ""))
	match t:
		"Hold":
			return "Hold"
		"Move":
			return "Move → node %d" % int(o.get("dest", -1))
		"Support":
			var req: int = int(o.get("require_dest", -1))
			if req >= 0:
				return "Support u%d → node %d" % [int(o.get("target", -1)), req]
			return "Support u%d" % int(o.get("target", -1))
		_:
			return "(unknown)"


# --- scoreboard -----------------------------------------------------------


func _clear_scoreboard() -> void:
	for child in scoreboard_list.get_children():
		child.queue_free()


func _populate_scoreboard(view: Dictionary) -> void:
	_clear_scoreboard()
	var seats: Dictionary = view.get("seats", {})
	var scores: Dictionary = view.get("scores", {})
	var eliminated: Array = view.get("eliminated", [])
	var winner: Variant = view.get("winner", null)
	var winners: Array = view.get("winners", [])
	var max_score: float = -1.0
	for k in scores:
		var v: float = float(scores[k])
		if v > max_score:
			max_score = v

	# Order: by score desc, eliminated last.
	var ordered: Array = []
	for k in seats.keys():
		ordered.append(int(k))
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var a_elim: bool = a in eliminated
		var b_elim: bool = b in eliminated
		if a_elim != b_elim:
			return b_elim  # non-eliminated first
		var sa: float = float(scores.get(str(a), 0))
		var sb: float = float(scores.get(str(b), 0))
		return sa > sb
	)

	for player_id in ordered:
		var seat: Dictionary = seats[str(player_id)]
		var s: float = float(scores.get(str(player_id), 0))
		var is_elim: bool = player_id in eliminated
		var is_winner: bool = (winner != null and int(winner) == player_id) \
				or (player_id in winners)

		var row := HBoxContainer.new()

		var swatch := ColorRect.new()
		swatch.color = HexMap.player_color(player_id)
		swatch.custom_minimum_size = Vector2(14, 14)
		row.add_child(swatch)

		var label := Label.new()
		var kind_short: String = _short_seat(seat)
		var prefix: String = "P%d  %s" % [player_id, kind_short]
		var suffix: String = ""
		if is_elim:
			suffix = "  [eliminated]"
		elif is_winner:
			suffix = "  ★ WINNER"
		label.text = "  %s  •  score %d%s" % [prefix, int(s), suffix]
		if is_elim:
			label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		elif is_winner:
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		elif s == max_score and max_score > 0:
			label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
		row.add_child(label)
		scoreboard_list.add_child(row)


func _short_seat(seat: Dictionary) -> String:
	var t: String = str(seat.get("type", ""))
	if t == "human":
		var name: String = str(seat.get("name", "human"))
		return "[Human] %s" % name
	if t == "agent":
		var kind: String = str(seat.get("kind", ""))
		var bare: String = kind.split(".")[-1] if kind.contains(".") else kind
		return "[Agent] %s" % bare
	if t == "remote":
		return "[Remote] %s" % str(seat.get("url", "?"))
	return t


# --- game-over banner ----------------------------------------------------


func _show_game_over(view: Dictionary) -> void:
	var winner: Variant = view.get("winner", null)
	var winners: Array = view.get("winners", [])
	var scores: Dictionary = view.get("scores", {})
	var detente: bool = view.get("detente_reached", false)

	var msg: String
	if winner != null:
		msg = "GAME OVER  ★  Winner: Player %d  (score %d)" % [
			int(winner), int(float(scores.get(str(winner), 0)))
		]
	elif not winners.is_empty():
		var ids: Array[String] = []
		for w in winners:
			ids.append("P%s" % str(w))
		var prefix := "DÉTENTE" if detente else "GAME OVER"
		msg = "%s  ★  Co-winners: %s" % [prefix, ", ".join(ids)]
	else:
		msg = "GAME OVER  •  Tie"
	game_over_label.text = msg
	game_over_banner.visible = true
	game_create.visible = true


# --- HTTP responses --------------------------------------------------------


func _on_response(endpoint: String, data: Variant) -> void:
	if endpoint == "/healthz":
		status_label.text = "connected: %s" % JSON.stringify(data)
	elif endpoint == "/games" and typeof(data) == TYPE_DICTIONARY \
			and data.has("game_id"):
		current_game_id = data["game_id"]
		games_label.text = "game_id: %s" % current_game_id
		game_create.visible = false
		_apply_view(data["view"])
	elif endpoint.contains("/advance"):
		var t: int = data.get("turn", -1)
		var term: bool = data.get("is_terminal", false)
		var awaiting: Array = data.get("awaiting_humans", [])
		status_label.text = "advance: turn=%d terminal=%s awaiting=%s" % [
			t, term, str(awaiting)
		]
		_refresh_view()
	elif endpoint.contains("/orders"):
		var ready: bool = data.get("ready_to_resolve", false)
		status_label.text = "orders submitted; ready_to_resolve=%s" % str(ready)
		_refresh_view()
	elif endpoint.contains("/commit"):
		var advanced: bool = data.get("round_advanced", false)
		status_label.text = "commit OK; round_advanced=%s" % str(advanced)
		_refresh_view()
	elif endpoint.contains("/chat"):
		# /chat returns {ok, chat_phase_complete, ...}; refresh the view
		# so the UI can reflect changed phase / awaiting state.
		_refresh_view()
	elif endpoint.contains("/view/"):
		_apply_view(data)


func _on_failure(endpoint: String, message: String) -> void:
	status_label.text = "FAILURE %s: %s" % [endpoint, message]


func _apply_view(view: Variant) -> void:
	if typeof(view) != TYPE_DICTIONARY:
		return
	current_view = view
	hex_map.update_view(view)
	pending_orders.clear()
	pending_aid.clear()
	pending_intents.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()
	_populate_scoreboard(view)
	_render_text(view)
	_populate_stance_list(view)
	_populate_intent_list(view)
	_populate_aid_panel(view)
	_populate_info_panel(view)
	# Sync replay tracking with server's view.
	in_replay = bool(view.get("is_replay", false))
	var server_live_turn: int = int(view.get("current_turn",
			view.get("turn", 0)))
	if server_live_turn > current_live_turn or not in_replay:
		current_live_turn = server_live_turn
	replay_turn_spin.max_value = max(0.0, float(current_live_turn))
	replay_turn_spin.set_value_no_signal(int(view.get("turn", 0)))
	_update_replay_ui()
	var terminal_now: bool = view.get("is_terminal", false)
	if terminal_now:
		_show_game_over(view)
		# Play game-over chime once on transition into terminal.
		if not _was_terminal:
			var you_won: bool = false
			var winner: Variant = view.get("winner", null)
			var winners: Array = view.get("winners", [])
			var you: int = view.get("you", -1)
			if winner != null and int(winner) == you:
				you_won = true
			elif you in winners:
				you_won = true
			if you_won:
				sound.game_over_won()
			else:
				sound.game_over_lost()
	else:
		game_over_banner.visible = false
	_was_terminal = terminal_now


func _render_text(view: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("[b]turn %d / %d[/b]" % [
			view.get("turn", 0), view.get("max_turns", 0)])
	lines.append("you: P%d  •  submitted=%s" % [
			view.get("you", -1), str(view.get("submitted", false))])
	if view.get("is_terminal", false):
		lines.append("[color=#7fdc7f]TERMINAL[/color]")
	else:
		lines.append("awaiting humans: %s" % str(view.get("awaiting_humans", [])))
	lines.append("")
	lines.append("[u]your units:[/u]")
	for u in view.get("your_units", []):
		lines.append("  u%s @ node %s" % [u.get("id"), u.get("location")])
	output_label.text = "\n".join(lines)


# --- Bundle 4 / press v0 panels --------------------------------------------


func _stance_string(s: String) -> String:
	## Normalize an incoming stance string (engine emits "ally"/"neutral"/"hostile").
	var s2 := s.to_lower()
	if s2 == "ally" or s2 == "neutral" or s2 == "hostile":
		return s2
	return "neutral"


func _populate_stance_list(view: Dictionary) -> void:
	for child in stance_list.get_children():
		child.queue_free()
	pending_stance.clear()
	var you: int = int(view.get("you", -1))
	var seats: Dictionary = view.get("seats", {})
	var eliminated: Array = view.get("eliminated", [])
	# Read previous-turn stance from view.last_press[me] if available, so the
	# UI starts pre-populated with the player's prior declaration.
	var last_press: Dictionary = view.get("last_press", {})
	var my_last: Dictionary = last_press.get(str(you), {})
	var my_last_stance: Dictionary = my_last.get("stance", {})
	for k in seats.keys():
		var pid: int = int(k)
		if pid == you or pid in eliminated:
			continue
		var prior: String = _stance_string(str(my_last_stance.get(str(pid), "neutral")))
		pending_stance[pid] = prior
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = HexMap.player_color(pid)
		swatch.custom_minimum_size = Vector2(12, 12)
		row.add_child(swatch)
		var label := Label.new()
		label.text = "  P%d  " % pid
		row.add_child(label)
		var opt := OptionButton.new()
		opt.add_item("ALLY")
		opt.add_item("NEUTRAL")
		opt.add_item("HOSTILE")
		var idx := 1  # NEUTRAL by default
		match prior:
			"ally": idx = 0
			"neutral": idx = 1
			"hostile": idx = 2
		opt.select(idx)
		opt.item_selected.connect(_on_stance_changed.bind(pid))
		row.add_child(opt)
		stance_list.add_child(row)


func _on_stance_changed(idx: int, pid: int) -> void:
	var s := "neutral"
	match idx:
		0: s = "ally"
		1: s = "neutral"
		2: s = "hostile"
	pending_stance[pid] = s


func _populate_aid_panel(view: Dictionary) -> void:
	for child in aid_spend_list.get_children():
		child.queue_free()
	for child in trust_grid.get_children():
		child.queue_free()
	_aid_spend_keys.clear()

	var balance: int = int(view.get("your_aid_tokens", 0))
	aid_balance_label.text = "Aid tokens: %d  (cap %d)" % [
		balance,
		int(view.get("state", {}).get("config", {}).get("aid_token_cap", 10)),
	]

	# Backable ally intents — read other players' round_press_pending from
	# state, intersect with mutual-ALLY in last_press, surface each Move
	# intent as a click-to-spend row.
	var you: int = int(view.get("you", -1))
	var state: Dictionary = view.get("state", {})
	# round_press_pending isn't currently in serialize_state; we use the
	# "last_press" snapshot for displaying *prior-round* intents instead.
	# Aid spends can target current-round canon — but we don't know current
	# round intents yet, so rows are produced from last_press as a hint.
	var last_press: Dictionary = view.get("last_press", {})
	var my_last_stance: Dictionary = last_press.get(str(you), {}).get("stance", {})

	for k in last_press.keys():
		var other_pid: int = int(k)
		if other_pid == you:
			continue
		var their: Dictionary = last_press[k]
		var their_stance: Dictionary = their.get("stance", {})
		# Mutual-ALLY check.
		var i_ally: bool = _stance_string(str(my_last_stance.get(str(other_pid), "neutral"))) == "ally"
		var they_ally: bool = _stance_string(str(their_stance.get(str(you), "neutral"))) == "ally"
		if not (i_ally and they_ally):
			continue
		for intent in their.get("intents", []):
			var declared: Dictionary = intent.get("declared_order", {})
			if declared.get("type", "") != "Move":
				continue
			var unit_id: int = int(intent.get("unit_id", -1))
			var dest: int = int(declared.get("dest", -1))
			var key := "u%d:Move:n%d" % [unit_id, dest]
			_aid_spend_keys[key] = {
				"target_unit": unit_id,
			}
			var btn := Button.new()
			btn.toggle_mode = true
			btn.text = "P%d's u%d → node %d  [1 token]" % [other_pid, unit_id, dest]
			btn.toggled.connect(_on_aid_toggle.bind(key))
			aid_spend_list.add_child(btn)
	if aid_spend_list.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "(no mutual-ALLY partners with declared Move intents)"
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		aid_spend_list.add_child(hint)

	# Trust ledger: G[a,b] = aid given by a to b. Display as a labeled
	# n×n grid with corner labels.
	var aid_given: Dictionary = state.get("aid_given", {})
	var seats: Dictionary = view.get("seats", {})
	var pids: Array = []
	for sk in seats.keys():
		pids.append(int(sk))
	pids.sort()
	trust_grid.columns = pids.size() + 1
	# Header row: empty corner + column headers.
	var corner := Label.new()
	corner.text = "from\to"
	corner.custom_minimum_size = Vector2(56, 0)
	trust_grid.add_child(corner)
	for col_pid in pids:
		var h := Label.new()
		h.text = "P%d" % col_pid
		h.add_theme_color_override("font_color", HexMap.player_color(col_pid))
		trust_grid.add_child(h)
	for row_pid in pids:
		var row_label := Label.new()
		row_label.text = "P%d" % row_pid
		row_label.add_theme_color_override("font_color", HexMap.player_color(row_pid))
		trust_grid.add_child(row_label)
		for col_pid in pids:
			var v: int = int(aid_given.get("%d,%d" % [row_pid, col_pid], 0))
			var cell := Label.new()
			if row_pid == col_pid:
				cell.text = "—"
				cell.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			else:
				cell.text = str(v)
				if v > 0:
					cell.add_theme_color_override("font_color", Color(0.85, 0.65, 0.25))
				else:
					cell.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			trust_grid.add_child(cell)


func _on_aid_toggle(toggled: bool, key: String) -> void:
	var spend: Dictionary = _aid_spend_keys.get(key, {})
	if spend.is_empty():
		return
	if toggled:
		pending_aid.append(spend)
	else:
		for i in range(pending_aid.size() - 1, -1, -1):
			if pending_aid[i].hash() == spend.hash():
				pending_aid.remove_at(i)
				break


func _populate_info_panel(view: Dictionary) -> void:
	for child in betrayals_list.get_children():
		child.queue_free()
	var state: Dictionary = view.get("state", {})
	var streak: int = int(state.get("mutual_ally_streak", 0))
	var threshold_raw: Variant = state.get("config", {}).get("detente_threshold", 0)
	var threshold: int = int(threshold_raw) if threshold_raw != null else 0
	if threshold <= 0:
		detente_indicator.text = "Détente streak: %d  (détente disabled)" % streak
	else:
		detente_indicator.text = "Détente streak: %d / %d turns" % [streak, threshold]
		if streak >= threshold:
			detente_indicator.add_theme_color_override("font_color",
					Color(0.5, 0.86, 0.5))
		else:
			detente_indicator.add_theme_color_override("font_color",
					Color(0.78, 0.82, 0.92))
	for b in view.get("your_betrayals", []):
		var line := Label.new()
		var actual: Dictionary = b.get("actual_order", {})
		var declared: Dictionary = b.get("intent", {}).get("declared_order", {})
		line.text = "T%d  P%d declared %s, did %s" % [
			int(b.get("turn", 0)),
			int(b.get("betrayer", -1)),
			_format_order(declared),
			_format_order(actual),
		]
		line.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		betrayals_list.add_child(line)
	if betrayals_list.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "(no betrayals observed by you yet)"
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		betrayals_list.add_child(hint)


func _populate_intent_list(view: Dictionary) -> void:
	for child in intent_list.get_children():
		child.queue_free()
	var your_units: Array = view.get("your_units", [])
	if your_units.is_empty():
		var hint := Label.new()
		hint.text = "(no units)"
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		intent_list.add_child(hint)
		return
	var legal_map: Dictionary = view.get("legal_orders", {})
	for u in your_units:
		var uid: int = int(u.get("id", -1))
		if uid < 0:
			continue
		var loc: int = int(u.get("location", -1))
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "u%d @ n%d  " % [uid, loc]
		row.add_child(label)
		var opt := OptionButton.new()
		opt.add_item("(no intent)")
		# Map option index -> declared_order dict (or null for "skip").
		var orders_for_opt: Array = [null]
		var legal: Array = legal_map.get(str(uid), [])
		for o in legal:
			var od: Dictionary = o
			opt.add_item(_format_order(od))
			orders_for_opt.append(od)
		opt.select(0)
		opt.item_selected.connect(_on_intent_order_changed.bind(uid, orders_for_opt))
		row.add_child(opt)
		var rec_label := Label.new()
		rec_label.text = "  to:"
		row.add_child(rec_label)
		var rec_edit := LineEdit.new()
		rec_edit.placeholder_text = "all (or 0,2)"
		rec_edit.custom_minimum_size = Vector2(80, 0)
		rec_edit.text_changed.connect(_on_intent_recipients_changed.bind(uid))
		row.add_child(rec_edit)
		intent_list.add_child(row)


func _on_intent_order_changed(idx: int, unit_id: int,
		orders_for_opt: Array) -> void:
	var declared: Variant = orders_for_opt[idx] if idx < orders_for_opt.size() else null
	var entry: Dictionary = pending_intents.get(unit_id, {"recipients_raw": ""})
	entry["declared_order"] = declared
	if declared == null:
		# Skipped — drop the entry entirely so _build_intents_payload skips it.
		pending_intents.erase(unit_id)
	else:
		pending_intents[unit_id] = entry


func _on_intent_recipients_changed(text: String, unit_id: int) -> void:
	var entry: Dictionary = pending_intents.get(unit_id,
			{"declared_order": null, "recipients_raw": ""})
	entry["recipients_raw"] = text
	pending_intents[unit_id] = entry
