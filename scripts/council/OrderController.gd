extends RefCounted
class_name OrderController
##
## Holds turn-local order state during the ORDERS phase.
##
## Parallel to PressController (which owns NEGOTIATION-phase state).
## Lifecycle:
##   1. Phase transitions to ORDERS → controller starts empty.
##   2. UI proposes orders via `propose_order(unit_id, order)` after
##      legality check against the ViewModel's `legal_orders_for(uid)`.
##   3. Right-click on a queued order → `remove_order(unit_id)`.
##   4. On Submit → controller serializes to_orders_payload(), caller
##      posts to /games/<id>/orders.
##   5. After server resolves, controller is discarded.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase2-screens.md
##

signal updated  # emits whenever orders change

# unit_id (int) → order dict (matches the wire's serialize_order shape)
var orders: Dictionary = {}


func clear() -> void:
	orders.clear()
	updated.emit()


func propose_order(unit_id: int, order: Dictionary) -> void:
	## Replace any existing order for this unit. Caller is responsible
	## for legality (ViewModel.legal_orders_for(uid) gives the set).
	orders[unit_id] = order
	updated.emit()


func remove_order(unit_id: int) -> void:
	if orders.has(unit_id):
		orders.erase(unit_id)
		updated.emit()


func has_order_for(unit_id: int) -> bool:
	return orders.has(unit_id)


func order_for(unit_id: int) -> Dictionary:
	return orders.get(unit_id, {})


func count() -> int:
	return orders.size()


# --- Drag-gesture interpretation ---------------------------------------

static func interpret_drag(view_model, from_unit_id: int,
		to_node_id: int, local_intents: Array = []) -> Dictionary:
	## Map a HexBoard drag-released gesture onto an Order dict by
	## comparing the source unit, target tile, and the legal-orders set
	## the server already published.
	##
	## Mapping:
	##   - source.location == to_node_id           → Hold(unit=src)
	##   - to has friendly unit + their declared/draft
	##     intent is Move(dest=X)                  → SupportMove(target=u, dest=X)
	##   - to has friendly unit + they're holding  → SupportHold(target=u)
	##   - else                                    → Move(dest=to_node_id)
	##
	## Returns {} if no legal order matches the gesture.
	if view_model == null:
		return {}
	var src: Dictionary = view_model.unit_by_id(from_unit_id)
	if src.is_empty():
		return {}
	var src_loc: int = int(src.get("location", -1))
	var legal: Array = view_model.legal_orders_for(from_unit_id)
	var to_tile: Dictionary = view_model.tile_for_node(to_node_id)
	var to_unit = to_tile.get("unit")

	# Hold: dropped on own tile.
	if src_loc == to_node_id:
		return _find_legal(legal, "Hold", {})

	# Drop on a friendly unit other than self.
	if to_unit != null and int(to_unit.get("player", -1)) == view_model.my_player_id() \
			and int(to_unit.get("id", -1)) != from_unit_id:
		var friend_uid := int(to_unit["id"])
		var support_ref := _support_reference_for_friend(
			view_model, friend_uid, local_intents
		)
		if not support_ref.is_empty():
			var ref_kind := String(support_ref.get("type", ""))
			if ref_kind == "Move":
				for dest in support_ref.get("dests", []):
					var support_move := _find_legal(legal, "SupportMove",
						{"target": friend_uid, "target_dest": int(dest)})
					if not support_move.is_empty():
						return support_move
				return {}
			if ref_kind == "Hold":
				return _find_legal(legal, "SupportHold", {"target": friend_uid})
			return {}
		# Default to SupportHold for friendly units with no declared Move.
		return _find_legal(legal, "SupportHold", {"target": friend_uid})

	# Default: Move to the target.
	return _find_legal(legal, "Move", {"dest": to_node_id})


static func _support_reference_for_friend(view_model, friend_uid: int,
		local_intents: Array) -> Dictionary:
	var local_ref := _reference_from_intents(view_model, friend_uid, local_intents)
	if not local_ref.is_empty():
		return local_ref
	return _reference_from_intents(
		view_model, friend_uid, view_model.declared_intents()
	)


static func _reference_from_intents(view_model, friend_uid: int,
		intents: Array) -> Dictionary:
	var move_dests: Array = []
	var saw_hold := false
	var saw_other := false
	for intent in intents:
		if not (intent is Dictionary):
			continue
		var item: Dictionary = intent
		var pid := int(item.get("player_id", view_model.my_player_id()))
		if pid != view_model.my_player_id():
			continue
		if int(item.get("unit_id", -1)) != friend_uid:
			continue
		var declared = item.get("declared_order", {})
		if not (declared is Dictionary):
			saw_other = true
			continue
		var kind := String(declared.get("type", declared.get("kind", "")))
		if kind == "Move":
			var dest := int(declared.get("dest", -1))
			if dest >= 0 and not move_dests.has(dest):
				move_dests.append(dest)
		elif kind == "Hold":
			saw_hold = true
		else:
			saw_other = true
	if not move_dests.is_empty():
		return {"type": "Move", "dests": move_dests}
	if saw_hold:
		return {"type": "Hold"}
	if saw_other:
		return {"type": "Other"}
	return {}


static func _find_legal(legal: Array, kind: String,
		fields: Dictionary) -> Dictionary:
	## Look up the matching legal order in `legal` and return the wire
	## dict if it's found. `fields` are the additional fields that must
	## match (e.g. {"dest": 5}). Returns {} if no match.
	for o in legal:
		if String(o.get("type", "")) != kind:
			continue
		var matches := true
		for k in fields.keys():
			if int(o.get(k, -999)) != int(fields[k]):
				matches = false
				break
		if matches:
			return o.duplicate()
	return {}


# --- Serialization for play-server --------------------------------------

func to_orders_payload() -> Dictionary:
	## Shape submitted to /games/<id>/orders. Mirrors
	## foedus.remote.wire.serialize_orders ({"<unit_id>": order_dict}).
	var out: Dictionary = {}
	for uid in orders.keys():
		out[str(uid)] = orders[uid]
	return out
