class_name FcOwnerMeetingTab
extends RefCounted
## The Meeting tab: the owners' meeting proposals, votes and lobbying, relocation, expansion protection, and past meetings.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var box := VBoxContainer.new()
	var pending := controller.expansion_status()
	if not pending.is_empty():
		var info := FcUiTables.label("The owners approved an expansion to %d teams. The %d new teams will each pick %d players from the existing teams in an expansion draft. Protect up to %d of your players (select them below); no team loses more than one player. Then press Run the expansion draft." % [pending["size"], pending["new_teams"], pending["picks_per_team"], pending["limit"]], FcUiTokens.TYPE_H3)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(200, 0)
		box.add_child(info)
		var roster_ids: Array[int] = []
		var protect_rows: Array = []
		var ratings_now := FcPlayerRatings.load_default()
		var world_now := controller.state.world
		for pid in world_now.teams.get_by_id(controller.state.user_team_id).roster.player_ids:
			var p: FcPlayer = world_now.players.get_by_id(pid)
			protect_rows.append({"id": pid, "name": p.identity.full_name(), "pos": FcPosition.abbreviation(p.primary_position), "age": p.age_on(FcDate.new(controller.contract_year(), 7, 1)), "ovr": roundi(ratings_now.overall(p))})
			roster_ids.append(pid)
		var protect_list := FcTable.new([
			{"key": "name", "title": "Player", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"], "make": func() -> Control: return FcPlayerChip.new(),
				"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerChip).setup({"subject": FcPlayerPresentation.subject_for_player(world_now, int(row["id"])), "name": row["name"], "overall": row["ovr"]}, "", false, 32, true)},
			{"key": "pos", "title": "Pos", "width": 48}, {"key": "age", "title": "Age", "width": 46, "kind": "number"}, {"key": "ovr", "title": "Ovr", "width": 58, "kind": "rating", "align": "center"}],
			protect_rows, {"multi": true, "row_height": 40, "max_rows": 10})
		protect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		protect_list.custom_minimum_size.y = 40 * 6
		for pid in roster_ids:
			if pid in pending["protected"]:
				protect_list.select_id(pid, false)
		box.add_child(protect_list)
		box.add_child(FcButton.make("Confirm my protected players", FcButton.Variant.PRIMARY, func() -> void:
			var result := controller.set_protected_players(protect_list.selected_ids())
			ctx.tell(result["reason"] + (" Press Run the expansion draft when ready." if result["ok"] else ""))))
		return box
	var items := controller.meeting_items()
	if items.is_empty():
		box.add_child(FcUiTables.label("The league's owners meet once a year, after the season, to vote on rule changes. Press Begin Offseason when the season is over to open the meeting.", FcUiTokens.TYPE_H3))
	else:
		var intro := FcUiTables.label("The owners' meeting: vote on each proposal (each franchise has one vote). Cap changes need two thirds, an expansion three quarters, everything else a simple majority. Your influence: %d points (spend them to turn an owner's vote or to propose an item)." % controller.meeting_influence(), FcUiTokens.TYPE_H3)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.custom_minimum_size = Vector2(200, 0)
		box.add_child(intro)
		var summary: Array = []
		for entry in items:
			var vote = entry["user_vote"]
			summary.append([entry["item"]["title"], entry["tally"]["yes"], entry["tally"]["no"], entry["tally"]["needed"], "-" if vote == null else ("Yes" if vote else "No"), "PASSES" if entry["tally"]["passes"] else "fails"])
		var summary_table := FcTable.from_strings(["Proposal", "Yes", "No", "Needed", "Your vote", "Now"], summary, [0, 50, 50, 70, 80, 70], {"max_rows": 5})
		summary_table.size_flags_vertical = Control.SIZE_FILL
		box.add_child(summary_table)
		var detail_label := FcUiTables.label("Select a proposal to see what it does and how every owner leans.")
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.custom_minimum_size = Vector2(200, 0)
		box.add_child(detail_label)
		var vote_titles := ["Owner", "Vote", "Why", "To turn"]
		var vote_rows := FcTable.from_strings(vote_titles, [], [0, 60, 0, 70], {"max_rows": 8})
		vote_rows.custom_minimum_size.y = 34 * 9
		box.add_child(vote_rows)
		var vote_team_ids: Array[int] = []
		var show_item := func(index: int):
			var entry: Dictionary = items[index]
			detail_label.text = "%s: %s" % [entry["item"]["title"], entry["item"]["detail"]]
			vote_team_ids.clear()
			var vote_text: Array = []
			for v in entry["tally"]["votes"]:
				vote_text.append([v["name"], "Yes" if v["yes"] else "No", v["reason"], "-" if v["flipped"] else "%d pt%s" % [v["cost"], "" if v["cost"] == 1 else "s"]])
				vote_team_ids.append(v["team"])
			vote_rows.set_rows(FcTable.rows_from_strings(vote_titles, vote_text))
		summary_table.row_selected.connect(func(id) -> void: show_item.call(int(id)))
		if not summary.is_empty():
			var first_index := mini(ctx.memory["meeting_item"], summary.size() - 1)
			summary_table.select_id(first_index, false)
			show_item.call(first_index)
		var buttons := HFlowContainer.new()
		for choice in [["Vote yes", true], ["Vote no", false]]:
			buttons.add_child(FcUiTables.button(choice[0], func():
				if summary_table.selected_id == null:
					ctx.tell("Select a proposal first.")
					return
				controller.cast_meeting_vote(items[int(summary_table.selected_id)]["item"]["id"], choice[1])
				ctx.refresh_now()))
		buttons.add_child(FcUiTables.button("Lobby the selected owner (turn their vote)", func():
			if summary_table.selected_id == null or vote_rows.selected_id == null:
				ctx.tell("Select a proposal, then an owner in the lower list.")
				return
			var result := controller.lobby_owner(items[int(summary_table.selected_id)]["item"]["id"], vote_team_ids[int(vote_rows.selected_id)])
			ctx.tell(result["reason"])
			if result["ok"]:
				ctx.memory["meeting_item"] = int(summary_table.selected_id)
				ctx.refresh_now()))
		box.add_child(buttons)
		var proposable := controller.proposable_items()
		if not proposable.is_empty():
			var propose_row := HFlowContainer.new()
			propose_row.add_child(FcUiTables.label("Add a proposal of your own (%d points, once a meeting):" % FcOwnersMeeting.PROPOSE_COST))
			var proposal_pick := FcDropdown.new()
			for p in proposable:
				proposal_pick.add_item(p["title"])
			propose_row.add_child(proposal_pick)
			propose_row.add_child(FcUiTables.button("Propose it", func():
				var made := controller.propose_item(proposable[proposal_pick.selected]["id"])
				ctx.tell(made["reason"])
				if made["ok"]:
					ctx.refresh_now()))
			box.add_child(propose_row)
		var destinations := controller.relocation_options()
		if not destinations.is_empty() and not controller.state.meeting.get("proposed", false):
			box.add_child(FcUiTables.label("Move your franchise: you choose the city and may rename the team (needs two thirds of the owners, costs %d points)." % FcOwnersMeeting.PROPOSE_COST, FcUiTokens.TYPE_SMALL))
			var move_row := HFlowContainer.new()
			var city_pick := FcDropdown.new()
			for d in destinations:
				city_pick.add_item("%s (%s, %.1fM people)" % [d["name"], d["region"], d["population"] / 1e6])
			move_row.add_child(city_pick)
			move_row.add_child(FcUiTables.label("New team name (optional):"))
			var name_edit := LineEdit.new()
			name_edit.placeholder_text = "keep the current name"
			name_edit.custom_minimum_size = Vector2(200, 0)
			move_row.add_child(name_edit)
			move_row.add_child(FcUiTables.button("Propose the move", func():
				var moved := controller.propose_relocation(destinations[city_pick.selected]["name"], name_edit.text)
				ctx.tell(moved["reason"])
				if moved["ok"]:
					ctx.refresh_now()))
			box.add_child(move_row)
	var log_rows: Array = []
	var log: Array = controller.state.meeting_log
	for i in range(log.size() - 1, maxi(-1, log.size() - 13), -1):
		log_rows.append(["%d-%02d" % [log[i][0], (log[i][0] + 1) % 100], log[i][1], "Passed" if log[i][2] == 1 else "Failed", "%d-%d" % [log[i][3], log[i][4]]])
	box.add_child(FcUiTables.label("Past meetings", FcUiTokens.TYPE_H3, true))
	box.add_child(FcTable.from_strings(["Season", "Proposal", "Result", "Vote"], log_rows, [70, 0, 70, 70]))
	return box
