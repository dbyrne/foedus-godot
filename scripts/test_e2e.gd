## End-to-end integration test against a live foedus play-server.
##
## Run flow:
##   1. foedus play-server start --port 8090   (in another terminal / bg)
##   2. godot --headless --script res://scripts/test_e2e.gd
##
## Walks healthz → create demo game → auto-advance to terminal, asserting
## each response. Exits 0 on success, 1 on any failure or 10s timeout.
extends SceneTree

const TIMEOUT_SEC: float = 15.0

var client
var step: int = 0
var game_id: String = ""
var elapsed: float = 0.0
var done: bool = false


func _initialize() -> void:
	print("--- foedus-godot e2e test ---")
	var GameClientScript = load("res://scripts/GameClient.gd")
	client = GameClientScript.new()
	root.add_child(client)
	client.response.connect(_on_response)
	client.failure.connect(_on_failure)
	# First request is kicked off from _process so the SceneTree has finished
	# its initial iteration and HTTPRequest nodes are addressable.


var _started: bool = false


func _process(delta: float) -> bool:
	elapsed += delta
	if not _started:
		_started = true
		print("step 0: GET /healthz")
		client.healthz()
	if not done and elapsed > TIMEOUT_SEC:
		print("FAIL: timeout after %.1fs at step %d" % [elapsed, step])
		return true
	return done


func _on_response(endpoint: String, data: Variant) -> void:
	print("ok: %s [step %d]" % [endpoint, step])
	if step == 0 and endpoint == "/healthz":
		step = 1
		var config: Dictionary = {
			"num_players": 2,
			"seed": 42,
			"max_turns": 5,
			"peace_threshold": 99,
		}
		var seats: Array = [
			{"type": "agent", "kind": "foedus.HeuristicAgent"},
			{"type": "agent", "kind": "foedus.RandomAgent"},
		]
		print("step 1: POST /games")
		client.create_game(config, seats)
	elif step == 1 and endpoint == "/games":
		if typeof(data) != TYPE_DICTIONARY or not data.has("game_id"):
			print("FAIL: /games response missing game_id")
			_finish(1)
			return
		game_id = data["game_id"]
		print("  game_id: %s" % game_id)
		step = 2
		print("step 2: POST /games/%s/advance auto=true" % game_id)
		client.advance(game_id, true)
	elif step == 2 and endpoint.contains("/advance"):
		if typeof(data) == TYPE_DICTIONARY and data.get("is_terminal", false):
			print("  game terminal at turn %d" % data.get("turn", -1))
			print("--- ALL OK ---")
			_finish(0)
		else:
			print("FAIL: not terminal after auto-advance: %s" % str(data))
			_finish(1)


func _on_failure(endpoint: String, message: String) -> void:
	print("FAIL: %s: %s" % [endpoint, message])
	_finish(1)


func _finish(code: int) -> void:
	done = true
	quit(code)
