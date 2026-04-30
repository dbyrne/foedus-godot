extends SceneTree
##
## Captures Coronation + Pairwise dossier against fixtures.
## Replay needs a live server with /history, so it's captured separately.
##

func _initialize() -> void:
	var Cor = load("res://scenes/council/CouncilCoronation.tscn") as PackedScene
	var Pair = load("res://scenes/council/CouncilPairwise.tscn") as PackedScene
	var Game = load("res://scripts/council/CouncilGame.gd")
	var VM = load("res://scripts/council/ViewModel.gd")
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")

	# Coronation
	var cor = Cor.instantiate()
	root.add_child(cor)
	await create_timer(0.4).timeout
	var v = Fix.terminal_view()
	# Add a 2nd winner so we can render multi-winner détente.
	v.winners = [0, 2]
	v.detente_reached = true
	v.is_terminal = true
	v.scores = {"0": 28.0, "1": 22.0, "2": 28.0, "3": 18.0}
	v.state.scores = v.scores
	var vm = VM.new(v)
	var game = Game.new()
	game.view_model = vm
	cor.add_child(game)
	cor.attach_game(game)
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png("/tmp/phase2d-coronation.png")
	print("captured: /tmp/phase2d-coronation.png")
	cor.queue_free()
	await create_timer(0.3).timeout

	# Pairwise — focus on player 2 to show real leverage from fixture.
	var pair = Pair.instantiate()
	root.add_child(pair)
	await create_timer(0.4).timeout
	var pair_vm = VM.new(Fix.negotiation_view())
	var pair_game = Game.new()
	pair_game.view_model = pair_vm
	pair.add_child(pair_game)
	pair.attach_game(pair_game)
	pair.set_focus_player(2)
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png("/tmp/phase2d-pairwise.png")
	print("captured: /tmp/phase2d-pairwise.png")

	quit(0)
