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


# --- Press v0 + Bundle 4 -----------------------------------------------------
##
## Press v0 round flow per turn:
##   1. Each human seat calls press_chat(player, draft) zero or more times
##      with a non-null draft to broadcast/DM messages. A null draft
##      signals "chat done" (no further chat from this seat).
##   2. Once every human has signaled chat-done, /commit is unblocked.
##   3. Each human seat calls press_commit(player, press, orders, aid_spends)
##      atomically. When all have committed, the server resolves the round.
##
## Bundle 4 adds aid_spends to /commit — list of {target_unit, target_order}
## dicts. Aid is gated on mutual-ALLY stance with the recipient in the
## previous turn's locked press.


func press_chat(game_id: String, player: int,
		draft: Variant) -> void:
	## Send a chat draft (or null to signal chat-done).
	## `draft` shape: {recipients: null | [int, ...], body: String}
	post_request("/games/%s/chat" % game_id,
			{"player": player, "draft": draft})


func press_commit(game_id: String, player: int, press: Dictionary,
		orders: Dictionary, aid_spends: Array = []) -> void:
	## Submit press tokens + orders + (optional) aid spends atomically.
	## Server returns 425 if chat phase isn't complete yet.
	post_request("/games/%s/commit" % game_id, {
		"player": player,
		"press": press,
		"orders": orders,
		"aid_spends": aid_spends,
	})
