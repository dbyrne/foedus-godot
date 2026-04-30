extends Node
##
## Synthetic view payload used by ViewModel tests.
##
## Shape mirrors `Session._build_view` in foedus/foedus/game_server/session.py
## as of 2026-04-29. Refresh by capturing a real /view/0 from a running
## play-server when the wire format changes.
##

static func negotiation_view() -> Dictionary:
	return {
		"game_id": "test-game",
		"you": 0,
		"turn": 3,
		"max_turns": 15,
		"state": {
			"turn": 3,
			"map": {
				"coords": {
					"0": [0, 0], "1": [1, 0], "2": [2, 0],
					"3": [0, 1], "4": [1, 1], "5": [2, 1],
				},
				"edges": {
					"0": [1, 3], "1": [0, 2, 3, 4], "2": [1, 4, 5],
					"3": [0, 1, 4], "4": [1, 2, 3, 5], "5": [2, 4],
				},
				"node_types": {
					"0": "HOME", "1": "PLAIN", "2": "SUPPLY",
					"3": "PLAIN", "4": "FOREST", "5": "HOME",
				},
				"home_assignments": {"0": 0, "5": 1},
				"supply_values": {"2": 2},  # this supply is high-value
			},
			"units": {
				"0": {"id": 0, "owner": 0, "location": 0},
				"1": {"id": 1, "owner": 1, "location": 5},
				"2": {"id": 2, "owner": 0, "location": 1},
			},
			"ownership": {
				"0": 0, "1": 0, "2": null, "3": null, "4": null, "5": 1,
			},
			"scores": {"0": 14.0, "1": 12.0, "2": 8.0, "3": 5.0},
			"eliminated": [],
			"next_unit_id": 3,
			"config": {
				"num_players": 4, "max_turns": 15, "fog_radius": 2,
				"build_period": 3, "detente_threshold": 5, "seed": 42,
				"high_value_supply_fraction": 0.20,
				"high_value_supply_yield": 2,
			},
			"mutual_ally_streak": 1,
			"chat_done": [2, 3],  # players 2 and 3 done; 0 and 1 still drafting
			"aid_tokens": {"0": 4, "1": 2, "2": 0, "3": 1},
			"aid_given": {
				# I (p0) have given Patron-style aid to p2; p2 hasn't
				# reciprocated → I have positive leverage on p2.
				"0,2": 3,
				"2,0": 1,
				"1,3": 2,
			},
			"round_aid_pending": {"0": []},
		},
		"your_aid_tokens": 4,
		"your_aid_pending": [],
		"your_betrayals": [
			{
				"turn": 2, "betrayer": 1,
				"intent": {
					"unit_id": 1,
					"declared_order": {"kind": "Hold", "unit_id": 1},
					"visible_to": null,
				},
				"actual_order": {"kind": "Move", "unit_id": 1, "dest": 4},
			},
		],
		"last_press": {
			"0": {"stance": {"1": "neutral", "2": "ally", "3": "neutral"}, "intents": []},
			"1": {"stance": {"0": "hostile", "2": "neutral", "3": "ally"}, "intents": []},
			"2": {"stance": {"0": "ally", "1": "neutral", "3": "neutral"}, "intents": []},
			"3": {"stance": {"0": "neutral", "1": "ally", "2": "neutral"}, "intents": []},
		},
		"your_units": [
			{"id": 0, "owner": 0, "location": 0},
			{"id": 2, "owner": 0, "location": 1},
		],
		# legal_orders uses the wire format from foedus.remote.wire.serialize_order:
		# {"type": "Hold"} / {"type": "Move", "dest": N} / etc. The dict key
		# is the unit_id; serialized orders don't carry a unit_id field.
		"legal_orders": {
			"0": [{"type": "Hold"}],
			"2": [
				{"type": "Hold"},
				{"type": "Move", "dest": 4},
				{"type": "Move", "dest": 2},
			],
		},
		"awaiting_humans": [0],
		"submitted": false,
		# Players 2 and 3 have signaled chat-done; 0 (me) and 1 haven't.
		# So chat_phase_complete = false (need ALL alive players done).
		"chat_phase_complete": false,
		"is_terminal": false,
		"detente_reached": false,
		"winner": null,
		"winners": [],
		"scores": {"0": 14.0, "1": 12.0, "2": 8.0, "3": 5.0},
		"eliminated": [],
		"seats": {
			"0": {"type": "human", "name": "You", "kind": "human", "url": null},
			"1": {"type": "agent", "name": "Cooperator", "kind": "in-process", "url": null},
			"2": {"type": "agent", "name": "DishonestCooperator", "kind": "in-process", "url": null},
			"3": {"type": "agent", "name": "GreedyHold", "kind": "in-process", "url": null},
		},
		"is_replay": false,
		"current_turn": 3,
		"snapshot_count": 4,
	}


static func orders_view() -> Dictionary:
	# Press round complete for everyone — engine flips
	# `chat_phase_complete` to true. ViewModel should report phase=ORDERS.
	var v := negotiation_view()
	v["state"]["chat_done"] = [0, 1, 2, 3]
	v["chat_phase_complete"] = true
	return v


static func terminal_view() -> Dictionary:
	var v := negotiation_view()
	v["is_terminal"] = true
	v["detente_reached"] = false
	v["winner"] = 0
	v["winners"] = [0]
	return v
