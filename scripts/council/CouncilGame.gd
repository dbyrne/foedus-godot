extends Node
class_name CouncilGame
##
## Top-level controller for the Council mode UI.
##
## Owns:
##   - GameClient (HTTP wrapper, reused from v0)
##   - current ViewModel (refreshed from /view payloads)
##   - PressController (turn-local press state)
##
## Routes between Negotiation / Orders / Resolution scenes based on
## ViewModel.phase(). Each screen subscribes to `view_changed` to
## render itself; this controller doesn't know about screen internals.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

const ViewModelScript       = preload("res://scripts/council/ViewModel.gd")
const PressControllerScript = preload("res://scripts/council/PressController.gd")

signal view_changed(view_model)
signal phase_transition(from_phase: String, to_phase: String)
signal failure_occurred(endpoint: String, message: String)

var game_client: Node = null  # GameClient.gd instance, injected
var view_model = null          # ViewModel
var press = null  # PressController; loose typing avoids class_name ordering issues

var game_id: String = ""
var view_player: int = 0
var _last_phase: String = ""


func attach(client: Node, gid: String, player: int) -> void:
	## Wire the controller to a GameClient + game_id + perspective player.
	## The client must be added to the scene tree before calling.
	game_client = client
	game_id = gid
	view_player = player
	if game_client.has_signal("response"):
		game_client.response.connect(_on_response)
	if game_client.has_signal("failure"):
		game_client.failure.connect(_on_failure)
	press = PressControllerScript.new()


func refresh_view() -> void:
	if game_client == null or game_id == "":
		return
	game_client.view(game_id, view_player)


# --- HTTP routing -------------------------------------------------------

func _on_response(endpoint: String, data: Variant) -> void:
	if endpoint.begins_with("/games/") and endpoint.ends_with("/view/%d" % view_player):
		_apply_view(data)
	elif endpoint.begins_with("/games/") and (
			endpoint.ends_with("/chat")
			or endpoint.ends_with("/commit")
			or endpoint.ends_with("/orders")
			or endpoint.ends_with("/advance")):
		refresh_view()


func _on_failure(endpoint: String, message: String) -> void:
	failure_occurred.emit(endpoint, message)


# --- View application ---------------------------------------------------

func _apply_view(payload: Dictionary) -> void:
	view_model = ViewModelScript.new(payload)
	if press != null and view_model.phase() == ViewModelScript.PHASE_NEGOTIATION:
		# Re-seed press state from the freshly published stance/intents
		# only when we're entering NEGOTIATION (don't clobber draft mid-phase).
		if _last_phase != ViewModelScript.PHASE_NEGOTIATION:
			press.seed_from_view(view_model)
	var current_phase: String = view_model.phase()
	if current_phase != _last_phase:
		phase_transition.emit(_last_phase, current_phase)
		_last_phase = current_phase
	view_changed.emit(view_model)


# --- Press / orders submission -----------------------------------------

func seal_intent() -> void:
	## Close this player's chat window for the turn. The view model moves
	## to ORDERS once every surviving player has signaled chat-done.
	if game_client == null or press == null or view_model == null:
		return
	if not game_client.has_method("press_chat"):
		failure_occurred.emit(
			"/games/%s/chat" % game_id,
			"GameClient does not implement press_chat",
		)
		return
	var chat_text: String = String(press.chat_draft).strip_edges()
	var draft: Variant = null
	if not chat_text.is_empty():
		draft = {"recipients": null, "body": chat_text}
	game_client.press_chat(game_id, view_player, draft)


func _resolve_aid_payload() -> Array:
	## Convert PressController's per-player aid_targets into actual
	## AidSpend dicts by picking the first owned unit of each recipient.
	## Targeting is reactive — the engine assigns aid at resolution time.
	var out: Array = []
	if view_model == null or press == null:
		return out
	for spec in press.to_aid_payload():
		var pid: int = int(spec.get("_recipient_pid", -1))
		if pid < 0:
			continue
		var owned: Array = view_model.units_owned_by(pid)
		if owned.is_empty():
			continue
		var target_unit_id: int = int(owned[0].get("id", -1))
		if target_unit_id < 0:
			continue
		out.append({
			"target_unit": target_unit_id,
		})
	return out


func submit_orders(orders: Dictionary) -> void:
	if game_client == null or press == null:
		return
	if not game_client.has_method("press_commit"):
		failure_occurred.emit(
			"/games/%s/commit" % game_id,
			"GameClient does not implement press_commit",
		)
		return
	var press_payload: Dictionary = press.to_press_payload()
	var aid_payload: Array = _resolve_aid_payload()
	game_client.press_commit(
		game_id,
		view_player,
		press_payload,
		orders,
		aid_payload,
	)


# --- Convenience accessors ---------------------------------------------

func current_phase() -> String:
	if view_model == null:
		return ViewModelScript.PHASE_NEGOTIATION
	return view_model.phase()
