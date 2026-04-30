extends SceneTree
##
## Capture the CouncilOrders scene with a synthetic ViewModel + a
## couple of pre-queued orders so the OrderArrows render.
##
const OUT_PATH := "/tmp/phase2b-orders.png"


func _initialize() -> void:
	var Orders = load("res://scenes/council/CouncilOrders.tscn") as PackedScene
	var Game = load("res://scripts/council/CouncilGame.gd")
	var VM = load("res://scripts/council/ViewModel.gd")
	var Press = load("res://scripts/council/PressController.gd")
	var Ctrl = load("res://scripts/council/OrderController.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")

	var orders_scene = Orders.instantiate()
	root.add_child(orders_scene)
	await create_timer(0.4).timeout

	# Use the orders_view fixture (chat_phase_complete=true → ORDERS).
	var vm = VM.new(Fix.orders_view())
	var game = Game.new()
	game.view_model = vm
	game.press = Press.new()
	game.press.seed_from_view(vm)
	orders_scene.add_child(game)
	orders_scene.attach_game(game)

	# Pre-queue some orders so we can see arrows.
	orders_scene.order_controller.propose_order(0, {"type": "Hold"})
	orders_scene.order_controller.propose_order(2, {"type": "Move", "dest": 4})
	orders_scene._on_view_changed(vm)

	await create_timer(0.6).timeout

	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("Could not capture viewport"); quit(1); return
	img.save_png(OUT_PATH)
	print("captured: ", OUT_PATH)
	quit(0)
