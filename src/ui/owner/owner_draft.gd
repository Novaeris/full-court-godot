class_name FcOwnerDraft
extends RefCounted
## The Draft tab: the scouts' board, workouts and picks while the draft runs; the latest draft otherwise.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var box := VBoxContainer.new()
	var status := controller.draft_status()
	if status.is_empty():
		box.add_child(FcUiTables.label("The draft is held after the season, in the offseason. You will see your scouts' board here and pick for your team.", FcUiTokens.TYPE_H3))
		var report := controller.latest_draft_report()
		var rows: Array = []
		if not report.is_empty():
			box.add_child(FcUiTables.label("The %d draft" % report["year"], FcUiTokens.TYPE_H3, true))
			for entry in report["rows"]:
				var p: FcPlayer = w.players.get_by_id(entry["player"])
				if p != null:
					rows.append([entry["pick"], entry["round"], ctx.team_name(entry["team"]), p.identity.full_name(), FcPosition.abbreviation(p.primary_position)])
		box.add_child(FcTable.from_strings(["Pick", "Round", "Team", "Player", "Pos"], rows, [50, 60, 0, 0, 50]))
		return box
	var prefix := "Pick %d of %d (round %d): " % [status["pick"], status["total"], status["round"]]
	if status["complete"]:
		box.add_child(FcUiTables.label("The draft is complete.", FcUiTokens.TYPE_H3, true))
	elif status["user_on_clock"]:
		box.add_child(FcUiTables.label(prefix + "YOU ARE ON THE CLOCK", FcUiTokens.TYPE_H3, true))
	else:
		box.add_child(FcUiTables.label(prefix + ctx.team_name(status["team"]), FcUiTokens.TYPE_H3))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_child(FcUiTables.label("Draft board (your scouts' view; ranges hold the truth about 4 times in 5)", FcUiTokens.TYPE_H3, true))
	var rows2: Array = []
	var rank := 0
	for entry in controller.draft_board():
		rank += 1
		var p: FcPlayer = entry["player"]
		var r: Dictionary = entry["report"]
		rows2.append({"id": p.id, "rank": rank, "name": p.identity.full_name(), "pos": FcPosition.abbreviation(p.primary_position), "age": entry["age"], "height": p.physical.height_cm,
			"ovr": "%d-%d" % [r["ovr_low"], r["ovr_high"]], "ovr_mid": r["ovr_low"] + r["ovr_high"], "pot": "%d-%d" % [r["pot_low"], r["pot_high"]], "pot_mid": r["pot_low"] + r["pot_high"],
			"worked": r["character"] if r["worked_out"] else "", "from": p.identity.country})
	var table := FcTable.new([
		{"key": "rank", "title": "#", "width": 44, "kind": "number"},
		{"key": "name", "title": "Prospect", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"], "make": func() -> Control: return FcPlayerChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerChip).setup({"subject": FcPlayerPresentation.subject_for_player(w, int(row["id"])), "name": row["name"], "overall": 0}, "", false, 36, true)},
		{"key": "pos", "title": "Pos", "width": 48}, {"key": "age", "title": "Age", "width": 46, "kind": "number"},
		{"key": "height", "title": "Height", "width": 70, "kind": "number", "format": func(v) -> String: return "%d cm" % int(v)},
		{"key": "ovr", "title": "Overall", "width": 76, "kind": "number", "sort_value": func(r: Dictionary): return r["ovr_mid"]},
		{"key": "pot", "title": "Potential", "width": 84, "kind": "number", "sort_value": func(r: Dictionary): return r["pot_mid"]},
		{"key": "worked", "title": "Worked out", "width": 130}, {"key": "from", "title": "From", "width": 110}], rows2, {"row_height": 44, "max_rows": 9})
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 44 * 7
	left.add_child(table)
	var buttons := HFlowContainer.new()
	buttons.add_child(FcUiTables.button("Draft selected prospect", func():
		if table.selected_id == null:
			ctx.tell("Select a prospect first.")
			return
		var r2 := controller.user_draft_pick(int(table.selected_id))
		ctx.tell(r2["reason"])
		ctx.after_draft.call()))
	buttons.add_child(FcUiTables.button("Invite selected to a workout (%d left)" % controller.draft_workouts_left(), func():
		if table.selected_id == null:
			ctx.tell("Select a prospect first.")
			return
		var r4 := controller.invite_to_workout(int(table.selected_id))
		ctx.refresh_now()
		ctx.tell(r4["reason"])))
	buttons.add_child(FcUiTables.button("Let my staff pick", func():
		var r3 := controller.draft_staff_pick()
		ctx.tell(r3["reason"])
		ctx.after_draft.call()))
	left.add_child(buttons)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Picks so far", FcUiTokens.TYPE_H3, true))
	var log_rows: Array = []
	var results := controller.draft_results()
	for i in range(results.size() - 1, -1, -1):
		var pick: Array = results[i]
		var p2: FcPlayer = w.players.get_by_id(pick[3])
		log_rows.append([pick[1], ctx.team_name(pick[2]), p2.identity.full_name(), FcPosition.abbreviation(p2.primary_position)])
	right.add_child(FcTable.from_strings(["Pick", "Team", "Player", "Pos"], log_rows, [50, 0, 0, 50]))
	columns.add_child(right)
	box.add_child(columns)
	return box
