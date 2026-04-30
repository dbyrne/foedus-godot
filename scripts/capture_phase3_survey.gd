extends SceneTree
##
## Multi-turn observation pass to inform Phase 3 polish ranking.
## Drives the live game ~5 turns and snaps PNGs at each key moment.
##

const SERVER  := "http://127.0.0.1:8090"
const GAME_ID := "9f8d5286-7cdc-4d47-b7fd-08f5a93fa15d"
const NUM_TURNS := 5


func _initialize() -> void:
	var GameClient = load("res://scripts/GameClient.gd")
	var Game = load("res://scripts/council/CouncilGame.gd")
	var Negotiation = load("res://scenes/council/CouncilNegotiation.tscn")
	var Orders = load("res://scenes/council/CouncilOrders.tscn")
	var Resolution = load("res://scenes/council/CouncilResolution.tscn")
	var Pairwise = load("res://scenes/council/CouncilPairwise.tscn")

	var client = GameClient.new()
	client.base_url = SERVER
	root.add_child(client)
	await create_timer(0.3).timeout

	var game = Game.new()
	root.add_child(game)
	game.attach(client, GAME_ID, 0)

	for turn_idx in NUM_TURNS:
		print("=== TURN %d ===" % turn_idx)
		# NEGOTIATION snapshot
		var neg = Negotiation.instantiate()
		root.add_child(neg)
		await create_timer(0.4).timeout
		neg.attach_game(game)
		game.refresh_view()
		await create_timer(1.8).timeout
		if game.view_model == null:
			push_error("no view"); quit(1); return
		var t: int = game.view_model.turn()
		var phase: String = game.view_model.phase()
		print("[neg] turn=%d phase=%s units=%d" % [t, phase, game.view_model.my_units().size()])
		await create_timer(0.4).timeout
		root.get_viewport().get_texture().get_image().save_png(
			"/tmp/p3-t%d-1neg.png" % turn_idx)

		# Cache prev view
		var prev_view = game.view_model._raw.duplicate(true)

		# Player 0 /chat (chat-done, empty draft)
		await _post(root, "/games/%s/chat" % GAME_ID,
			'{"player":0,"draft":{"stance":{},"intents":[]}}')
		# Advance for AIs to chat + signal done
		for i in 4:
			await _post(root, "/games/%s/advance" % GAME_ID, '{"auto":false}')
			await create_timer(0.2).timeout

		# ORDERS snapshot
		game.refresh_view()
		await create_timer(1.8).timeout
		neg.queue_free()
		await create_timer(0.3).timeout
		var ord = Orders.instantiate()
		root.add_child(ord)
		await create_timer(0.4).timeout
		ord.attach_game(game)
		# Queue Hold on first unit so we see at least one queued arrow
		var my_uid: int = -1
		if not game.view_model.my_units().is_empty():
			my_uid = int(game.view_model.my_units()[0]["id"])
		if my_uid >= 0:
			ord.order_controller.propose_order(my_uid, {"type": "Hold"})
			ord._refresh_arrows()
		await create_timer(0.5).timeout
		print("[ord] turn=%d phase=%s" % [game.view_model.turn(), game.view_model.phase()])
		root.get_viewport().get_texture().get_image().save_png(
			"/tmp/p3-t%d-2ord.png" % turn_idx)

		# Commit + advance through resolution
		var commit_body: String
		if my_uid >= 0:
			commit_body = '{"player":0,"press":{"stance":{},"intents":[]},"orders":{"%d":{"type":"Hold"}},"aid_spends":[]}' % my_uid
		else:
			commit_body = '{"player":0,"press":{"stance":{},"intents":[]},"orders":{},"aid_spends":[]}'
		await _post(root, "/games/%s/commit" % GAME_ID, commit_body)
		for i in 5:
			await _post(root, "/games/%s/advance" % GAME_ID, '{"auto":false}')
			await create_timer(0.2).timeout
		game.refresh_view()
		await create_timer(1.8).timeout
		var curr_view = game.view_model._raw.duplicate(true)

		# RESOLUTION snapshot mid-playback
		ord.queue_free()
		await create_timer(0.3).timeout
		var resolution = Resolution.instantiate()
		root.add_child(resolution)
		await create_timer(0.4).timeout
		resolution.attach_game(game)
		resolution.play_between(prev_view, curr_view)
		await create_timer(1.0).timeout
		root.get_viewport().get_texture().get_image().save_png(
			"/tmp/p3-t%d-3res.png" % turn_idx)
		await create_timer(2.5).timeout
		resolution.queue_free()
		await create_timer(0.3).timeout

		if game.view_model.is_terminal():
			print("game terminal at turn %d" % game.view_model.turn())
			break

	# Final pairwise dossier
	game.refresh_view()
	await create_timer(1.5).timeout
	var pair = Pairwise.instantiate()
	root.add_child(pair)
	await create_timer(0.4).timeout
	pair.attach_game(game)
	pair.set_focus_player(2)  # DishonestCooperator — leverage interest
	await create_timer(0.6).timeout
	root.get_viewport().get_texture().get_image().save_png("/tmp/p3-pairwise.png")
	print("captured pairwise")

	quit(0)


func _post(root_node: Node, path: String, body: String) -> void:
	var http = HTTPRequest.new()
	root_node.add_child(http)
	http.request(SERVER + path, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)
	await http.request_completed
	http.queue_free()
