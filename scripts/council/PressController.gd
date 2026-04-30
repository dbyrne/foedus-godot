extends RefCounted
class_name PressController
##
## Holds turn-local press state (stances, intents, aid spends, chat
## draft) for the current human player. Pure data — no Godot scene
## dependency.
##
## Lifecycle:
##   1. ViewModel arrives → caller initializes PressController with
##      `seed_from_view(vm)` (copies the player's own stance from
##      last_press as a starting point).
##   2. UI mutations call set_stance / add_intent / etc.
##   3. On "Seal Intent", the caller serializes via to_press_payload()
##      and posts to /games/<id>/press.
##   4. On phase transition to ORDERS, this object is discarded.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

signal updated  # emitted on any state change

var stance: Dictionary = {}    # other_pid → "ally"|"neutral"|"hostile"
var intents: Array = []        # [{unit_id, declared_order, recipients}]
var aid_targets: Dictionary = {}  # other_pid → bool (will spend on them)
var chat_draft: String = ""


func seed_from_view(vm) -> void:
	## Copy my last-published stance as the starting point so the UI
	## reflects what I committed last turn.
	var me: int = int(vm.my_player_id())
	var n: int = int(vm.num_players())
	stance.clear()
	for other_pid in n:
		if other_pid == me:
			continue
		stance[other_pid] = String(vm.stance(me, other_pid))
	intents.clear()
	aid_targets.clear()
	chat_draft = ""
	updated.emit()


func set_stance(other_pid: int, value: String) -> void:
	stance[other_pid] = value
	updated.emit()


func add_intent(unit_id: int, declared_order: Dictionary,
				recipients: Variant = null) -> void:
	## `recipients` of null means broadcast (visible_to=null).
	# Replace any existing intent for the same unit (one declared
	# order per unit per turn).
	for i in intents.size():
		if int(intents[i].get("unit_id", -1)) == unit_id:
			intents.remove_at(i)
			break
	intents.append({
		"unit_id": unit_id,
		"declared_order": declared_order,
		"recipients": recipients,
	})
	updated.emit()


func remove_intent(unit_id: int) -> void:
	for i in intents.size():
		if int(intents[i].get("unit_id", -1)) == unit_id:
			intents.remove_at(i)
			updated.emit()
			return


func toggle_aid(other_pid: int, on: bool) -> void:
	if on:
		aid_targets[other_pid] = true
	else:
		aid_targets.erase(other_pid)
	updated.emit()


func set_chat(text: String) -> void:
	chat_draft = text
	updated.emit()


# --- Serialization for play-server --------------------------------------

func to_press_payload() -> Dictionary:
	## Shape submitted to /games/<id>/press for this player. Mirrors
	## foedus.press.Press serialization in foedus/foedus/remote/wire.py.
	var stance_serialized: Dictionary = {}
	for other_pid in stance.keys():
		stance_serialized[str(other_pid)] = stance[other_pid]
	return {
		"stance": stance_serialized,
		"intents": intents.duplicate(true),
	}


func to_aid_payload() -> Array:
	## List of AidSpend dicts. Phase 2a's per-player toggles each map
	## to a single AidSpend on the recipient's first unit; Phase 2b
	## will refine to explicit unit + order targeting.
	var spends: Array = []
	for other_pid in aid_targets.keys():
		spends.append({
			"target_unit": null,  # caller fills from ViewModel
			"target_order": null,
			"_recipient_pid": other_pid,  # carried for downstream
		})
	return spends
