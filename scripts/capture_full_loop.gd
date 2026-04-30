extends SceneTree
##
## Final-check capture: drive a fresh live game through the full Phase 2
## Council loop and snap one PNG per phase.
##
## Captures:
##   /tmp/run-1-negotiation.png   — turn 0 NEGOTIATION
##   /tmp/run-2-orders.png        — turn 0 ORDERS (after press locked)
##   /tmp/run-3-resolution.png    — Resolution playback turn 0 → 1
##   /tmp/run-4-next-turn.png     — turn 1 NEGOTIATION (post-resolution)
##   /tmp/run-5-pairwise.png      — Pairwise dossier (focus the AI Cooperator)
##

const SERVER  := "http://127.0.0.1:8090"
const GAME_ID := "624c4bb5-7f75-48ee-ad87-2a19956a4b50"


func _initialize() -> void:
	var GameClient = load("res://scripts/GameClient.gd")
	var Game = load("res://scripts/council/CouncilGame.gd")
	var ViewModel = load("res://scripts/council/ViewModel.gd")
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

	# --- Capture 1: NEGOTIATION ---
	var neg = Negotiation.instantiate()
	root.add_child(neg)
	await create_timer(0.4).timeout
	neg.attach_game(game)
	game.refresh_view()
	await create_timer(2.0).timeout
	if game.view_model == null:
		push_error("no view at turn 0"); quit(1); return
	print("[1] turn=%d phase=%s" % [game.view_model.turn(), game.view_model.phase()])
	root.get_viewport().get_texture().get_image().save_png("/tmp/run-1-negotiation.png")
	print("captured: /tmp/run-1-negotiation.png")

	# --- Drive press round forward via direct HTTP (CouncilGame's
	# seal_intent uses methods that don't yet exist on GameClient;
	# /chat + /commit are the actual server endpoints). ---
	var http = HTTPRequest.new()
	root.add_child(http)
	# Player 0 /chat with empty press draft
	http.request(
		"%s/games/%s/chat" % [SERVER, GAME_ID],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		'{"player":0,"draft":{"stance":{},"intents":[]}}'
	)
	await http.request_completed
	# /advance to let AIs do their /chat
	http.queue_free(); http = HTTPRequest.new(); root.add_child(http)
	for i in 3:
		http.request(
			"%s/games/%s/advance" % [SERVER, GAME_ID],
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			'{"auto":false}'
		)
		await http.request_completed
		await create_timer(0.3).timeout

	# --- Capture 2: ORDERS ---
	game.refresh_view()
	await create_timer(2.0).timeout
	neg.queue_free()
	await create_timer(0.3).timeout
	var ord = Orders.instantiate()
	root.add_child(ord)
	await create_timer(0.4).timeout
	ord.attach_game(game)
	# Pre-queue an order against the human's first unit for visibility
	var my_uid: int = -1
	if not game.view_model.my_units().is_empty():
		my_uid = int(game.view_model.my_units()[0]["id"])
	if my_uid >= 0:
		ord.order_controller.propose_order(my_uid, {"type": "Hold"})
		ord._refresh_arrows()
	await create_timer(0.5).timeout
	print("[2] turn=%d phase=%s" % [game.view_model.turn(), game.view_model.phase()])
	root.get_viewport().get_texture().get_image().save_png("/tmp/run-2-orders.png")
	print("captured: /tmp/run-2-orders.png")

	# --- Drive commit + advance through resolution ---
	# Cache turn-0 view as 'prev' for the manual Resolution capture.
	var prev_view = game.view_model._raw.duplicate(true)
	var commit_body := '{"player":0,"press":{"stance":{},"intents":[]},"orders":{"%d":{"type":"Hold"}},"aid_spends":[]}' % my_uid
	http.queue_free(); http = HTTPRequest.new(); root.add_child(http)
	http.request(
		"%s/games/%s/commit" % [SERVER, GAME_ID],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		commit_body
	)
	await http.request_completed
	# Advance until turn ticks over.
	http.queue_free(); http = HTTPRequest.new(); root.add_child(http)
	for i in 3:
		http.request(
			"%s/games/%s/advance" % [SERVER, GAME_ID],
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			'{"auto":false}'
		)
		await http.request_completed
		await create_timer(0.3).timeout
	game.refresh_view()
	await create_timer(2.0).timeout
	var curr_view = game.view_model._raw.duplicate(true)
	print("[3] post-commit turn=%d" % game.view_model.turn())

	# --- Capture 3: RESOLUTION mid-playback ---
	ord.queue_free()
	await create_timer(0.3).timeout
	var resolution = Resolution.instantiate()
	root.add_child(resolution)
	await create_timer(0.4).timeout
	resolution.attach_game(game)
	resolution.play_between(prev_view, curr_view)
	# Capture mid-animation.
	await create_timer(1.0).timeout
	root.get_viewport().get_texture().get_image().save_png("/tmp/run-3-resolution.png")
	print("captured: /tmp/run-3-resolution.png")
	# Let it finish, then capture the next-turn negotiation.
	await create_timer(2.5).timeout
	resolution.queue_free()
	await create_timer(0.3).timeout
	var neg2 = Negotiation.instantiate()
	root.add_child(neg2)
	await create_timer(0.4).timeout
	neg2.attach_game(game)
	await create_timer(0.5).timeout
	print("[4] next-turn negotiation turn=%d" % game.view_model.turn())
	root.get_viewport().get_texture().get_image().save_png("/tmp/run-4-next-turn.png")
	print("captured: /tmp/run-4-next-turn.png")

	# --- Capture 5: Pairwise dossier ---
	neg2.queue_free()
	await create_timer(0.3).timeout
	var pair = Pairwise.instantiate()
	root.add_child(pair)
	await create_timer(0.4).timeout
	pair.attach_game(game)
	pair.set_focus_player(1)  # Cooperator
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png("/tmp/run-5-pairwise.png")
	print("captured: /tmp/run-5-pairwise.png")

	quit(0)
