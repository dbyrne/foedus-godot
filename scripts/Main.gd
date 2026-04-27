## Bootstrap controller for foedus-godot.
##
## Wires the GameClient + HexMap together:
##   - Connect/Create/Advance/View buttons drive the play-server HTTP API.
##   - HexMap renders the latest /view response.
##   - Click a unit on the map -> selects it. Click an adjacent empty hex ->
##     sends a Move order. Click your unit's own hex -> Hold. Click a
##     non-adjacent hex with a unit selected clears selection.
class_name Main
extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var games_label: Label = $VBox/GamesLabel
@onready var output_label: RichTextLabel = $VBox/HSplit/OutputLabel
@onready var connect_btn: Button = $VBox/ConnectBtn
@onready var create_btn: Button = $VBox/CreateBtn
@onready var advance_btn: Button = $VBox/HBoxButtons/AdvanceBtn
@onready var auto_btn: Button = $VBox/HBoxButtons/AutoBtn
@onready var view_btn: Button = $VBox/HBoxButtons/ViewBtn
@onready var url_edit: LineEdit = $VBox/HBox/UrlEdit
@onready var view_player_spin: SpinBox = $VBox/ViewSelect/ViewPlayerSpin
@onready var hex_map: HexMap = $VBox/HSplit/HexMap

var client: GameClient
var current_game_id: String = ""
var current_view: Dictionary = {}
var selected_unit_id: int = -1
var num_players: int = 4


func _ready() -> void:
	client = GameClient.new()
	add_child(client)
	client.response.connect(_on_response)
	client.failure.connect(_on_failure)

	connect_btn.pressed.connect(_on_connect_pressed)
	create_btn.pressed.connect(_on_create_pressed)
	advance_btn.pressed.connect(_on_advance_pressed)
	auto_btn.pressed.connect(_on_auto_pressed)
	view_btn.pressed.connect(_on_view_pressed)
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
	var config := {
		"num_players": num_players,
		"seed": 42,
		"max_turns": 15,
		"peace_threshold": 99,
	}
	var seats := [
		{"type": "agent", "kind": "foedus.HeuristicAgent"},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 1}},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 2}},
		{"type": "agent", "kind": "foedus.RandomAgent", "args": {"seed": 3}},
	]
	view_player_spin.max_value = num_players - 1
	status_label.text = "creating game..."
	client.create_game(config, seats)


func _on_advance_pressed() -> void:
	if current_game_id.is_empty():
		status_label.text = "no game"
		return
	client.advance(current_game_id, false)


func _on_auto_pressed() -> void:
	if current_game_id.is_empty():
		return
	client.advance(current_game_id, true)


func _on_view_pressed() -> void:
	_refresh_view()


func _on_view_player_changed(_v: float) -> void:
	_refresh_view()


func _refresh_view() -> void:
	if current_game_id.is_empty():
		return
	client.view(current_game_id, int(view_player_spin.value))


# --- HexMap interaction ---


func _on_unit_clicked(unit_id: int, owner: int) -> void:
	var you: int = int(view_player_spin.value)
	if owner != you:
		# Clicked an enemy unit — for now, treat as deselect.
		selected_unit_id = -1
		hex_map.clear_selection()
		status_label.text = "(enemy unit u%d not selectable)" % unit_id
		return
	selected_unit_id = unit_id
	hex_map.select_unit(unit_id)
	status_label.text = "selected u%d (your unit)" % unit_id


func _on_hex_clicked(node_id: int) -> void:
	if selected_unit_id < 0 or current_view.is_empty():
		return
	var legal: Dictionary = current_view.get("legal_orders", {})
	var unit_legal: Array = legal.get(str(selected_unit_id), [])

	# Find a legal order on this hex: prefer Move, fall back to Hold if it's
	# the unit's own location.
	var your_units: Array = current_view.get("your_units", [])
	var unit_loc: int = -1
	for u in your_units:
		if int(u["id"]) == selected_unit_id:
			unit_loc = int(u["location"])
			break

	var chosen: Variant = null
	if node_id == unit_loc:
		for o in unit_legal:
			if o.get("type") == "Hold":
				chosen = o
				break
	else:
		for o in unit_legal:
			if o.get("type") == "Move" and int(o.get("dest", -1)) == node_id:
				chosen = o
				break

	if chosen == null:
		status_label.text = "no legal order from u%d to node %d" % [
			selected_unit_id, node_id
		]
		return

	# Pre-pop our submission with this single order; existing stored orders
	# for other units stay the responsibility of subsequent clicks.
	var orders: Dictionary = {str(selected_unit_id): chosen}
	# (For v1 we let the player submit one unit's order at a time and rely on
	# legal-orders defaulting Hold for the others. The play-server will fill
	# any unsubmitted units with Hold automatically when it's the only
	# pending player.)
	status_label.text = "submitting u%d %s..." % [selected_unit_id, chosen.type]
	var player: int = int(view_player_spin.value)
	client.submit_orders(current_game_id, player, orders)
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
		status_label.text = "advance: turn=%d terminal=%s" % [t, term]
		_refresh_view()
	elif endpoint.contains("/orders"):
		status_label.text = "orders submitted; ready=%s" % str(
				data.get("ready_to_resolve", false))
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
		lines.append("[color=green]TERMINAL[/color]")
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
