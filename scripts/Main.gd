## Bootstrap UI for foedus-godot.
##
## Minimal text-based controller for v0:
##   - Healthz / connect to the foedus play-server
##   - Create a 4-agent demo game
##   - Step turns and display the state textually
##
## This is the seed for richer UI work. The next layer is a hex-map renderer
## (HexMap.gd / HexMap.tscn) that consumes the same `view` payload and draws
## the board, plus an order-entry panel that lets a human player point and
## click to issue Move / Support orders.
class_name Main
extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var games_label: Label = $VBox/GamesLabel
@onready var output_label: RichTextLabel = $VBox/OutputLabel
@onready var connect_btn: Button = $VBox/ConnectBtn
@onready var create_btn: Button = $VBox/CreateBtn
@onready var advance_btn: Button = $VBox/AdvanceBtn
@onready var auto_btn: Button = $VBox/AutoBtn
@onready var view_btn: Button = $VBox/ViewBtn
@onready var url_edit: LineEdit = $VBox/HBox/UrlEdit

var client: GameClient
var current_game_id: String = ""
var current_player: int = 0
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
	status_label.text = "creating game..."
	client.create_game(config, seats)


func _on_advance_pressed() -> void:
	if current_game_id.is_empty():
		status_label.text = "no game"
		return
	client.advance(current_game_id, false)


func _on_auto_pressed() -> void:
	if current_game_id.is_empty():
		status_label.text = "no game"
		return
	client.advance(current_game_id, true)


func _on_view_pressed() -> void:
	if current_game_id.is_empty():
		status_label.text = "no game"
		return
	client.view(current_game_id, current_player)


func _on_response(endpoint: String, data: Variant) -> void:
	if endpoint == "/healthz":
		status_label.text = "connected: %s" % JSON.stringify(data)
	elif endpoint == "/games" and typeof(data) == TYPE_DICTIONARY \
			and data.has("game_id"):
		current_game_id = data["game_id"]
		games_label.text = "game_id: %s" % current_game_id
		_render_view(data["view"])
	elif endpoint.contains("/advance"):
		var t: int = data.get("turn", -1)
		var term: bool = data.get("is_terminal", false)
		var awaiting: Array = data.get("awaiting_humans", [])
		status_label.text = "advance: turn=%d terminal=%s awaiting=%s" % [
			t, term, str(awaiting)
		]
		# Re-fetch the player view for nicer display.
		client.view(current_game_id, current_player)
	elif endpoint.contains("/view/"):
		_render_view(data)
	else:
		output_label.text = "[code]%s -> %s[/code]" % [
			endpoint, JSON.stringify(data)
		]


func _on_failure(endpoint: String, message: String) -> void:
	status_label.text = "FAILURE %s: %s" % [endpoint, message]


func _render_view(view: Variant) -> void:
	if typeof(view) != TYPE_DICTIONARY:
		output_label.text = "[i](no view)[/i]"
		return
	var lines: Array[String] = []
	lines.append("[b]turn %d / %d[/b]" % [view.get("turn", 0),
			view.get("max_turns", 0)])
	lines.append("you: player %d  •  submitted=%s" % [
		view.get("you", -1), str(view.get("submitted", false))
	])
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
