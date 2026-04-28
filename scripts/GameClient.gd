## HTTP client wrapping the foedus play-server REST API.
##
## Pattern: one HTTPRequest child per outstanding request, freed on completion.
## Each call returns a Promise-like — emit signals on success/failure.
class_name GameClient
extends Node

signal response(endpoint: String, data: Variant)
signal failure(endpoint: String, message: String)

@export var base_url: String = "http://127.0.0.1:8090"


func _build_request_node(endpoint: String) -> HTTPRequest:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http, endpoint))
	return http


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray,
		http: HTTPRequest, endpoint: String) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		failure.emit(endpoint, "transport error: result=%d" % result)
		return
	var text := body.get_string_from_utf8()
	var json := JSON.new()
	if text.length() > 0 and json.parse(text) != OK:
		failure.emit(endpoint, "invalid JSON: %s" % json.get_error_message())
		return
	var data: Variant = json.data if text.length() > 0 else null
	if response_code >= 400:
		failure.emit(endpoint, "HTTP %d: %s" % [response_code, str(data)])
		return
	response.emit(endpoint, data)


func get_request(endpoint: String) -> void:
	var http := _build_request_node(endpoint)
	var err := http.request("%s%s" % [base_url, endpoint])
	if err != OK:
		http.queue_free()
		failure.emit(endpoint, "request failed to launch: %d" % err)


func post_request(endpoint: String, body: Dictionary) -> void:
	var http := _build_request_node(endpoint)
	var headers := ["Content-Type: application/json"]
	var payload := JSON.stringify(body)
	var err := http.request("%s%s" % [base_url, endpoint], headers,
			HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		failure.emit(endpoint, "request failed to launch: %d" % err)


func delete_request(endpoint: String) -> void:
	var http := _build_request_node(endpoint)
	var err := http.request("%s%s" % [base_url, endpoint], [],
			HTTPClient.METHOD_DELETE)
	if err != OK:
		http.queue_free()
		failure.emit(endpoint, "request failed to launch: %d" % err)


# --- Convenience wrappers (named after foedus.game_server endpoints) ---


func healthz() -> void:
	get_request("/healthz")


func list_games() -> void:
	get_request("/games")


func create_game(config: Dictionary, seats: Array) -> void:
	post_request("/games", {"config": config, "seats": seats})


func view(game_id: String, player: int) -> void:
	get_request("/games/%s/view/%d" % [game_id, player])


func submit_orders(game_id: String, player: int,
		orders: Dictionary) -> void:
	post_request("/games/%s/orders" % game_id,
			{"player": player, "orders": orders})


func advance(game_id: String, auto: bool = false) -> void:
	post_request("/games/%s/advance" % game_id, {"auto": auto})


func delete_game(game_id: String) -> void:
	delete_request("/games/%s" % game_id)


func history(game_id: String) -> void:
	get_request("/games/%s/history" % game_id)


func history_view(game_id: String, turn: int, player: int) -> void:
	get_request("/games/%s/history/%d/view/%d" % [game_id, turn, player])
