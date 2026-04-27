## Bootstrap controller for foedus-godot.
##
## Order-entry flow:
##   - Click your unit on the map -> selects it. The OrderList panel shows
##     EVERY legal order for that unit (Hold, Move-to-X, SupportHold-of-Y,
##     SupportMove-Y-to-Z) as buttons.
##   - Map clicks are a shortcut for the most common cases:
##     * Click own hex   -> Hold (queued)
##     * Click adjacent  -> Move (queued)
##     Anything else (Support, non-adjacent) -> use the OrderList panel.
##   - Submit orders sends the queued dict; unspecified units default to Hold.
##
## Game-creation form replaces the previous hardcoded demos. The two preset
## buttons just pre-fill the seat dropdowns; you can still click Create with
## any custom mix.
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
@onready var num_players_spin: SpinBox = $VBox/GameCreate/HSeats/NumPlayersSpin
@onready var max_turns_spin: SpinBox = $VBox/GameCreate/HConfig/MaxTurnsSpin
@onready var peace_spin: SpinBox = $VBox/GameCreate/HConfig/PeaceSpin
@onready var seed_spin: SpinBox = $VBox/GameCreate/HConfig/SeedSpin
@onready var order_list: VBoxContainer = $VBox/HSplit/LeftPanel/OrderScroll/OrderList
@onready var hex_map: Control = $VBox/HSplit/HexMap

var seat_options: Array[OptionButton] = []
var client: GameClient
var current_game_id: String = ""
var current_view: Dictionary = {}
var selected_unit_id: int = -1
var pending_orders: Dictionary = {}


func _ready() -> void:
	client = GameClient.new()
	add_child(client)
	client.response.connect(_on_response)
	client.failure.connect(_on_failure)

	# Cache + populate seat OptionButtons.
	for i in range(6):
		var opt: OptionButton = get_node("VBox/GameCreate/HSeats/Seat%dOpt" % i)
		for label in SEAT_LABELS:
			opt.add_item(label)
		# Defaults: seat 0 Heuristic, others Random.
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
	reset_btn.pressed.connect(_on_reset_pressed)
	view_player_spin.value_changed.connect(_on_view_player_changed)

	hex_map.unit_clicked.connect(_on_unit_clicked)
	hex_map.hex_clicked.connect(_on_hex_clicked)

	status_label.text = "Set URL and click Connect"
	games_label.text = "(no active game)"
	output_label.text = "[i]waiting...[/i]"


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
	seat_options[0].select(1)  # Heuristic
	for i in range(1, 4):
		seat_options[i].select(2)  # Random


func _on_preset_human_pressed() -> void:
	num_players_spin.value = 4
	_apply_num_players(4)
	seat_options[0].select(0)  # Human
	seat_options[1].select(1)  # Heuristic
	for i in range(2, 4):
		seat_options[i].select(2)  # Random


func _on_create_pressed() -> void:
	var n: int = int(num_players_spin.value)
	var seats: Array = []
	for i in range(n):
		var idx: int = seat_options[i].selected
		match idx:
			0:  # Human
				seats.append({"type": "human", "name": "P%d" % i})
			1:  # Heuristic
				seats.append({"type": "agent", "kind": "foedus.HeuristicAgent"})
			2:  # Random
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
	client.advance(current_game_id, false)


func _on_auto_pressed() -> void:
	if current_game_id.is_empty():
		return
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


func _refresh_view() -> void:
	if current_game_id.is_empty():
		return
	client.view(current_game_id, int(view_player_spin.value))


func _on_submit_pressed() -> void:
	if current_game_id.is_empty() or current_view.is_empty():
		return
	var orders: Dictionary = {}
	for u in current_view.get("your_units", []):
		var uid_str: String = str(u["id"])
		orders[uid_str] = pending_orders.get(uid_str, {"type": "Hold"})
	if orders.is_empty():
		status_label.text = "(no units to submit orders for)"
		return
	var player: int = int(view_player_spin.value)
	status_label.text = "submitting %d order(s) for player %d..." % [
		orders.size(), player
	]
	client.submit_orders(current_game_id, player, orders)
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()


func _on_reset_pressed() -> void:
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()
	status_label.text = "pending orders cleared"


# --- HexMap interaction (selection + map-click shortcuts) ------------------


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
	# Map-click shortcut: only Move/Hold. Supports come from the OrderList panel.
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


# --- order list panel ------------------------------------------------------


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
	# Group: Hold first, then Move (sorted by dest), then SupportHold,
	# then SupportMove. Predictable scan order for the user.
	var groups: Dictionary = {"Hold": [], "Move": [], "SupportHold": [], "SupportMove": []}
	for o in legal:
		var t: String = str(o.get("type", ""))
		if groups.has(t):
			groups[t].append(o)
	for group_type in ["Hold", "Move", "SupportHold", "SupportMove"]:
		for o in groups[group_type]:
			var btn := Button.new()
			btn.text = _format_order(o)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			# Capture o by value via dict copy.
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
		"SupportHold":
			return "Support hold of u%d" % int(o.get("target", -1))
		"SupportMove":
			return "Support u%d → node %d" % [
				int(o.get("target", -1)),
				int(o.get("target_dest", -1)),
			]
		_:
			return "(unknown)"


# --- HTTP responses --------------------------------------------------------


func _on_response(endpoint: String, data: Variant) -> void:
	if endpoint == "/healthz":
		status_label.text = "connected: %s" % JSON.stringify(data)
	elif endpoint == "/games" and typeof(data) == TYPE_DICTIONARY \
			and data.has("game_id"):
		current_game_id = data["game_id"]
		games_label.text = "game_id: %s" % current_game_id
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
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_clear_order_list()
	_render_text(view)


func _render_text(view: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("[b]turn %d / %d[/b]" % [
			view.get("turn", 0), view.get("max_turns", 0)])
	lines.append("you: player %d  •  submitted=%s" % [
			view.get("you", -1), str(view.get("submitted", false))])
	lines.append("scores: %s" % JSON.stringify(view.get("scores", {})))
	lines.append("eliminated: %s" % str(view.get("eliminated", [])))
	if view.get("is_terminal", false):
		lines.append("[color=#7fdc7f]TERMINAL[/color]")
		var winner: Variant = view.get("winner", null)
		var winners: Array = view.get("winners", [])
		if winner != null:
			lines.append("winner: player %d" % winner)
		elif not winners.is_empty():
			lines.append("winners (collective): %s" % str(winners))
	else:
		lines.append("awaiting humans: %s" % str(view.get("awaiting_humans", [])))
	lines.append("")
	lines.append("[u]your units:[/u]")
	for u in view.get("your_units", []):
		lines.append("  u%s @ node %s" % [u.get("id"), u.get("location")])
	output_label.text = "\n".join(lines)
