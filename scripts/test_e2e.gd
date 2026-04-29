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
			step = 3
			print("step 3: GET /history")
			client.history(game_id)
		else:
			print("FAIL: not terminal after auto-advance: %s" % str(data))
			_finish(1)
	elif step == 3 and endpoint.contains("/history") \
			and not endpoint.contains("/view/"):
		var snapshots: Array = data.get("snapshots", [])
		if snapshots.is_empty():
			print("FAIL: empty history")
			_finish(1)
			return
		print("  history has %d snapshots; checking turn 1 view" % snapshots.size())
		step = 4
		client.history_view(game_id, 1, 0)
	elif step == 4 and endpoint.contains("/history/") \
			and endpoint.contains("/view/"):
		if typeof(data) == TYPE_DICTIONARY and data.get("is_replay", false) \
				and int(data.get("turn", -1)) == 1:
			print("  past view at turn 1 ok (is_replay=true)")
			step = 5
			print("step 5: GET /games/%s/view/0  (Bundle 4 field check)" % game_id)
			client.view(game_id, 0)
		else:
			print("FAIL: replay view did not return is_replay/turn=1: %s" % str(data))
			_finish(1)
	elif step == 5 and endpoint.contains("/view/"):
		# Bundle 4: validate that the new fields exist in the live view.
		if typeof(data) != TYPE_DICTIONARY:
			print("FAIL: view not a dict")
			_finish(1)
			return
		var missing: Array[String] = []
		for k in ["your_aid_tokens", "your_aid_pending", "your_betrayals", "last_press"]:
			if not data.has(k):
				missing.append(k)
		var state: Dictionary = data.get("state", {})
		for k in ["aid_tokens", "aid_given", "round_aid_pending"]:
			if not state.has(k):
				missing.append("state.%s" % k)
		if not missing.is_empty():
			print("FAIL: view missing Bundle 4 fields: %s" % str(missing))
			_finish(1)
			return
		print("  Bundle 4 fields present: your_aid_tokens=%s state.aid_given=%s" % [
				str(data["your_aid_tokens"]),
				str(state["aid_given"]),
		])
		print("--- ALL OK ---")
		_finish(0)


func _on_failure(endpoint: String, message: String) -> void:
	print("FAIL: %s: %s" % [endpoint, message])
	_finish(1)


func _finish(code: int) -> void:
	done = true
	quit(code)
