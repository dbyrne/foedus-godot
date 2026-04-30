extends SceneTree
##
## Headless regression for CouncilGame's live-server call sequence.
##

class MockClient:
	extends Node

	signal response(endpoint: String, data: Variant)
	signal failure(endpoint: String, message: String)

	var calls: Array = []

	func view(game_id: String, player: int) -> void:
		calls.append({
			"method": "view",
			"game_id": game_id,
			"player": player,
		})

	func press_chat(game_id: String, player: int, draft: Variant) -> void:
		calls.append({
			"method": "press_chat",
			"game_id": game_id,
			"player": player,
			"draft": draft,
		})

	func press_commit(game_id: String, player: int, press: Dictionary,
			orders: Dictionary, aid_spends: Array = []) -> void:
		calls.append({
			"method": "press_commit",
			"game_id": game_id,
			"player": player,
			"press": press,
			"orders": orders,
			"aid_spends": aid_spends,
		})


func _initialize() -> void:
	var failures := 0
	print("--- CouncilGame flow ---")

	var Game = load("res://scripts/council/CouncilGame.gd")
	var ViewModel = load("res://scripts/council/ViewModel.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")

	var client = MockClient.new()
	var game = Game.new()
	root.add_child(client)
	root.add_child(game)
	game.attach(client, "game-123", 0)

	game.view_model = ViewModel.new(Fix.negotiation_view())
	game.press.seed_from_view(game.view_model)
	game.press.set_chat("  Parley at dawn.  ")
	game.press.toggle_aid(1, true)
	game.press.add_intent(2, {"type": "Move", "dest": 4}, null)

	game.seal_intent()
	failures += _expect("seal sends /chat", client.calls.size() == 1
			and client.calls[0].get("method") == "press_chat")
	var draft: Variant = client.calls[0].get("draft")
	failures += _expect("seal carries chat draft", draft is Dictionary
			and String(draft.get("body", "")) == "Parley at dawn.")

	client.calls.clear()
	client.response.emit("/games/game-123/chat", {"ok": true})
	failures += _expect("chat response refreshes view", client.calls.size() == 1
			and client.calls[0].get("method") == "view")

	client.calls.clear()
	var orders := {"2": {"type": "Move", "dest": 4}}
	game.submit_orders(orders)
	failures += _expect("orders submit uses /commit", client.calls.size() == 1
			and client.calls[0].get("method") == "press_commit")
	failures += _expect("commit carries orders",
			Dictionary(client.calls[0].get("orders", {})).has("2"))
	failures += _expect("commit carries press",
			Dictionary(client.calls[0].get("press", {})).has("stance")
			and Dictionary(client.calls[0].get("press", {})).has("intents"))
	var intents: Array = Dictionary(client.calls[0].get("press", {})).get("intents", [])
	failures += _expect("commit uses visible_to for intents",
			intents.size() == 1
			and Dictionary(intents[0]).has("visible_to")
			and not Dictionary(intents[0]).has("recipients"))
	var aid_spends: Array = client.calls[0].get("aid_spends", [])
	failures += _expect("commit carries wire-format aid spend",
			aid_spends.size() == 1
			and Dictionary(aid_spends[0].get("target_order", {})).get("type") == "Hold")

	client.calls.clear()
	client.response.emit("/games/game-123/commit", {"ok": true})
	failures += _expect("commit response refreshes view", client.calls.size() == 1
			and client.calls[0].get("method") == "view")

	if failures == 0:
		print("--- ALL OK ---")
		quit(0)
	else:
		print("--- %d FAILURES ---" % failures)
		quit(1)


func _expect(name: String, cond: bool, detail: String = "") -> int:
	if cond:
		print("ok: ", name)
		return 0
	push_error("FAIL: %s - %s" % [name, detail])
	return 1
