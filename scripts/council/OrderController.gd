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
	##   - to has friendly unit                     → Support(target=u) [reactive]
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
		# Unified reactive Support — engine adapts to what the target does.
		return _find_legal(legal, "Support", {"target": friend_uid})

	# Default: Move to the target.
	return _find_legal(legal, "Move", {"dest": to_node_id})



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
