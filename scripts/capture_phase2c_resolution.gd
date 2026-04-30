extends SceneTree
##
## Capture the Resolution scene mid-playback, against two snapshots
## from the live play-server's /history endpoint.
##
## Falls back to a synthetic prev/curr if the server isn't reachable.
##
const OUT_PATH := "/tmp/phase2c-resolution.png"
const GAME_ID := "2dbb6162-5b92-4b14-a549-ece8e4a547c3"
const SERVER  := "http://127.0.0.1:8090"


func _initialize() -> void:
	var ResolutionScene = load("res://scenes/council/CouncilResolution.tscn") as PackedScene
	var Fix = load("res://tests/fixtures/view_payload_negotiation.gd")

	var resolution = ResolutionScene.instantiate()
	root.add_child(resolution)
	await create_timer(0.4).timeout

	# Try to fetch real history; fall back to fixtures.
	var prev_view: Dictionary = {}
	var curr_view: Dictionary = {}
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request("%s/games/%s/history/0/view/0" % [SERVER, GAME_ID])
	var r0 = await http.request_completed
	if int(r0[1]) == 200:
		prev_view = JSON.parse_string(r0[3].get_string_from_utf8())
		http.queue_free()
		http = HTTPRequest.new()
		root.add_child(http)
		http.request("%s/games/%s/history/1/view/0" % [SERVER, GAME_ID])
		var r1 = await http.request_completed
		if int(r1[1]) == 200:
			curr_view = JSON.parse_string(r1[3].get_string_from_utf8())

	if prev_view.is_empty() or curr_view.is_empty():
		print("(server unreachable; using synthetic fixtures)")
		prev_view = Fix.negotiation_view()
		curr_view = Fix.orders_view()

	print("playing back %d → %d" % [
		int(prev_view.get("turn", -1)),
		int(curr_view.get("turn", -1)),
	])
	resolution.play_between(prev_view, curr_view)

	# Capture mid-playback (~half of the timeline).
	await create_timer(1.5).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_PATH)
	print("captured: ", OUT_PATH)
	quit(0)
