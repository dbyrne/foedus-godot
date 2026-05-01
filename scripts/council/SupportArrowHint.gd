## SupportArrowHint — shared helper for resolving a Support order's arrow
## destination, used by CouncilNegotiation and CouncilOrders.
##
## Lookup precedence (matches fix spec):
##   1. require_dest on the order dict (pin variant — explicit destination).
##   2. Latest declared intent for the target unit in intent_revisions that
##      is a Move — use its dest.
##   3. legal_orders_for fallback (first Move found) — arrow is marked dim.
##
## Returns a dict:
##   { "dest": int, "dim": bool }
## where dest == -1 means no destination could be found (caller should
## render the dashed-ring fallback by collapsing from/to to the target's
## current tile position).


static func resolve(vm, ord: Dictionary) -> Dictionary:
	## vm    — ViewModel instance
	## ord   — the Support order dict (may contain require_dest, target)

	# 1. Explicit pinned destination.
	if ord.has("require_dest"):
		var rd := int(ord["require_dest"])
		if rd >= 0:
			return {"dest": rd, "dim": false}

	var target_id := int(ord.get("target", -1))
	if target_id < 0:
		return {"dest": -1, "dim": false}

	# 2. Walk intent_revisions in reverse to find the latest Move intent for
	#    the target unit. intent_revisions is ordered oldest-first by the
	#    engine, so we reverse-iterate to get the most recent entry.
	var revisions: Array = vm.intent_revisions()
	for i in range(revisions.size() - 1, -1, -1):
		var ev: Dictionary = revisions[i]
		var intent = ev.get("intent", null)
		if intent == null:
			continue
		if int(intent.get("unit_id", -1)) != target_id:
			continue
		var declared = intent.get("declared_order", {})
		var kind := String(declared.get("type", declared.get("kind", "")))
		if kind == "Move" and declared.has("dest"):
			return {"dest": int(declared["dest"]), "dim": false}
		# Found the latest intent for this unit but it's not a Move — stop.
		break

	# 3. Legal-orders fallback (first Move in geometrically valid set).
	#    Mark dim so the caller can render the arrow at reduced opacity.
	var legal: Array = vm.legal_orders_for(target_id)
	for lo in legal:
		if String(lo.get("type", "")) == "Move":
			return {"dest": int(lo.get("dest", -1)), "dim": true}

	# No destination found.
	return {"dest": -1, "dim": false}
