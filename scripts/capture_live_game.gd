extends SceneTree
##
## Drive the Council UI against a LIVE play-server. Captures both the
## Negotiation and Orders screens with real game data.
##
## Prereq: play-server running on http://127.0.0.1:8090, game already
## created (set GAME_ID below).
##
## Run: DISPLAY=:0 godot --script res://scripts/capture_live_game.gd \
##                       --resolution 1280x900 --quit-after 1500
##

const GAME_ID := "9f8d5286-7cdc-4d47-b7fd-08f5a93fa15d"
const SERVER  := "http://127.0.0.1:8090"


func _initialize() -> void:
	var GameClient = load("res://scripts/GameClient.gd")
	var Game = load("res://scripts/council/CouncilGame.gd")
	var ViewModel = load("res://scripts/council/ViewModel.gd")
	var Negotiation = load("res://scenes/council/CouncilNegotiation.tscn")
	var Orders = load("res://scenes/council/CouncilOrders.tscn")

	var client = GameClient.new()
	client.base_url = SERVER
	root.add_child(client)
	await create_timer(0.3).timeout

	var game = Game.new()
	root.add_child(game)
	game.attach(client, GAME_ID, 0)

	# Mount Negotiation first.
	var neg = Negotiation.instantiate()
	root.add_child(neg)
	await create_timer(0.4).timeout
	neg.attach_game(game)

	# Fetch view from live server.
	game.refresh_view()
	# HTTPRequest is async — wait a beat for the response to land.
	await create_timer(2.0).timeout

	if game.view_model == null:
		push_error("No view received from server")
		quit(1)
		return
	var phase: String = game.view_model.phase()
	print("live view: turn=%d phase=%s units=%d" % [
		game.view_model.turn(),
		phase,
		game.view_model.my_units().size(),
	])

	# Capture Negotiation screen.
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/live-negotiation.png")
	print("captured: /tmp/live-negotiation.png")

	# Drive the press submission to flip to Orders. Use empty press
	# (no stances, no intents, no aid) — fastest path through.
	if phase == ViewModel.PHASE_NEGOTIATION:
		print("submitting press to advance to ORDERS...")
		game.seal_intent()
		# AI players auto-advance; wait for the round to flip.
		await create_timer(2.5).timeout
		game.refresh_view()
		await create_timer(2.0).timeout
		print("post-seal view: turn=%d phase=%s" % [
			game.view_model.turn(), game.view_model.phase()
		])

	# Tear down Negotiation, mount Orders.
	neg.queue_free()
	await create_timer(0.4).timeout
	var orders = Orders.instantiate()
	root.add_child(orders)
	await create_timer(0.4).timeout
	orders.attach_game(game)
	await create_timer(1.0).timeout

	var img2 := root.get_viewport().get_texture().get_image()
	img2.save_png("/tmp/live-orders.png")
	print("captured: /tmp/live-orders.png")

	quit(0)
