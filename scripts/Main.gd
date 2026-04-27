## Bootstrap controller for foedus-godot.
##
## Order-entry flow:
##   1. Click your unit on the map -> it highlights (selected).
##   2. Click a destination hex -> records a *pending* order locally
##      (Move to that node, or Hold if it's the unit's own location).
##   3. Repeat for other units.
##   4. Click "Submit orders" -> the accumulated orders are sent to
##      /games/{id}/orders. Unspecified units default to Hold (server
##      already does this; we send Holds explicitly for clarity).
##   5. Once all human seats have submitted, click "Advance" to resolve.
##
## The client never auto-submits on click; that would clobber other units'
## pending orders since the server's submit replaces the whole player dict.
class_name Main
extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var games_label: Label = $VBox/GamesLabel
@onready var output_label: RichTextLabel = $VBox/HSplit/OutputLabel
@onready var connect_btn: Button = $VBox/ConnectBtn
@onready var create_btn: Button = $VBox/CreateBtn
@onready var create_human_btn: Button = $VBox/CreateHumanBtn
@onready var advance_btn: Button = $VBox/HBoxButtons/AdvanceBtn
@onready var auto_btn: Button = $VBox/HBoxButtons/AutoBtn
@onready var view_btn: Button = $VBox/HBoxButtons/ViewBtn
@onready var submit_btn: Button = $VBox/HBoxButtons/SubmitBtn
@onready var reset_btn: Button = $VBox/HBoxButtons/ResetBtn
@onready var url_edit: LineEdit = $VBox/HBox/UrlEdit
@onready var view_player_spin: SpinBox = $VBox/ViewSelect/ViewPlayerSpin
@onready var hex_map: Control = $VBox/HSplit/HexMap

var client: GameClient
var current_game_id: String = ""
var current_view: Dictionary = {}
var selected_unit_id: int = -1
var num_players: int = 4
# str(unit_id) -> order dict (e.g. {"type": "Move", "dest": 5}). Drained on submit.
var pending_orders: Dictionary = {}


func _ready() -> void:
	client = GameClient.new()
	add_child(client)
	client.response.connect(_on_response)
	client.failure.connect(_on_failure)

	connect_btn.pressed.connect(_on_connect_pressed)
	create_btn.pressed.connect(_on_create_pressed)
	create_human_btn.pressed.connect(_on_create_human_pressed)
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


func _on_connect_pressed() -> void:
	client.base_url = url_edit.text.strip_edges()
	status_label.text = "checking %s/healthz..." % client.base_url
	client.healthz()


func _on_create_pressed() -> void:
	var seats := [
		{"type": "agent", "kind": "foedus.HeuristicAgent"},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 1}},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 2}},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 3}},
	]
	_create_with_seats(seats)


func _on_create_human_pressed() -> void:
	# Player 0 is you; rest are agents.
	var seats := [
		{"type": "human", "name": "you"},
		{"type": "agent", "kind": "foedus.HeuristicAgent"},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 2}},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 3}},
	]
	_create_with_seats(seats)
	view_player_spin.value = 0


func _create_with_seats(seats: Array) -> void:
	var config := {
		"num_players": seats.size(),
		"seed": 42,
		"max_turns": 25,
		"peace_threshold": 99,
	}
	num_players = seats.size()
	view_player_spin.max_value = num_players - 1
	pending_orders.clear()
	hex_map.set_pending_orders({})
	status_label.text = "creating game..."
	client.create_game(config, seats)


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
	# Switching viewing player invalidates pending orders (they were for
	# the previous player's units).
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	_refresh_view()


func _refresh_view() -> void:
	if current_game_id.is_empty():
		return
	client.view(current_game_id, int(view_player_spin.value))


func _on_submit_pressed() -> void:
	if current_game_id.is_empty():
		status_label.text = "no game"
		return
	if current_view.is_empty():
		status_label.text = "no view to submit from"
		return
	# Fill missing units with explicit Hold so what we send matches what the
	# user sees on the map.
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


func _on_reset_pressed() -> void:
	pending_orders.clear()
	hex_map.set_pending_orders({})
	selected_unit_id = -1
	hex_map.clear_selection()
	status_label.text = "pending orders cleared"


# --- HexMap interaction ---


func _on_unit_clicked(unit_id: int, owner: int) -> void:
	var you: int = int(view_player_spin.value)
	if owner != you:
		# Enemy unit clicked — for now, deselect. Future: support orders
		# might target enemy units (SupportMove against), tackle then.
		selected_unit_id = -1
		hex_map.clear_selection()
		status_label.text = "(u%d belongs to player %d, not you)" % [
			unit_id, owner
		]
		return
	selected_unit_id = unit_id
	hex_map.select_unit(unit_id)
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
		status_label.text = "no legal order from u%d to node %d" % [
			selected_unit_id, node_id
		]
		return

	pending_orders[str(selected_unit_id)] = chosen
	hex_map.set_pending_orders(pending_orders)
	status_label.text = "queued u%d %s (%d order%s pending)" % [
		selected_unit_id,
		str(chosen.get("type", "")),
		pending_orders.size(),
		"" if pending_orders.size() == 1 else "s",
	]
	selected_unit_id = -1
	hex_map.clear_selection()


# --- HTTP responses ---


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
	# Pending orders from a previous turn are stale once we get a new view.
	pending_orders.clear()
	hex_map.set_pending_orders({})
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
