class_name FcOwnerSchedule
extends RefCounted
## The Owner Schedule tab: every game of the user's team (date, round, home or away, the opponent with its crest, the result as a W or L tag
## with the score) and the button that opens the box score of the selected game (kept for the last few games). The result always carries
## the letter and the score, never colour alone. Built from a FcOwnerContext.
## D-077 M5: a summary strip (home and away records, streak, the next three games) heads the list, and any game opens its Game Center
## (double-click a row or "Open in Game Center").


static func build(ctx: FcOwnerContext) -> Control:
	var season := ctx.controller.season()
	var team_id := ctx.user_team_id()
	var rows: Array = []
	var keys: Array = []
	for g in season.games:
		if not g.involves(team_id):
			continue
		var home: bool = g.home_id == team_id
		var opponent: int = g.away_id if home else g.home_id
		var result := ""
		var won := false
		if g.played:
			var mine: int = g.home_score if home else g.away_score
			var theirs: int = g.away_score if home else g.home_score
			won = mine > theirs
			result = "%s %d-%d%s" % ["W" if won else "L", mine, theirs, " (OT)" if g.overtimes > 0 else ""]
		keys.append([g.day, g.series, g.id])
		rows.append({"id": rows.size(), "date": season.date_of_day(g.day).to_iso(), "day": g.day, "round": "Playoffs" if g.series > 0 else "", "where": "vs" if home else "at",
			"team_id": opponent, "opponent": ctx.team_name(opponent), "result": result, "won": won})
	var columns := [
		{"key": "date", "title": "Date", "width": 112, "sort_value": func(r: Dictionary): return r["day"]},
		{"key": "round", "title": "Round", "width": 90},
		{"key": "where", "title": "", "width": 44, "sortable": false},
		{"key": "opponent", "title": "Opponent", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["opponent"],
			"make": func() -> Control: return FcTeamChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcTeamChip).setup(ctx.team_look(int(row["team_id"])), str(row["opponent"]), 24, false)},
		{"key": "result", "title": "Result", "width": 150, "kind": "custom", "sort_value": func(r: Dictionary): return r["result"],
			"make": func() -> Control: return FcStatusChip.make("", FcStatusChip.Tone.NEUTRAL),
			"bind": func(cell: Control, row: Dictionary) -> void: _bind_result(cell as FcStatusChip, row)},
	]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	box.add_child(_summary(ctx, season, team_id))
	var table := FcTable.new(columns, rows, {"max_rows": 14, "empty_title": "No games", "empty_text": "The schedule is empty."})
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 260
	box.add_child(table)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	row.add_child(FcButton.make("Open in Game Center", FcButton.Variant.PRIMARY, func() -> void: _open_center(ctx, table, keys)))
	row.add_child(FcButton.make("Box score of selected game", FcButton.Variant.SECONDARY, func() -> void: _open_box(ctx, table, keys)))
	var note := FcUiTables.label("Box scores are kept for your team's last %d games." % FcSeason.RECENT_BOX_LIMIT, FcUiTokens.TYPE_SMALL)
	note.theme_type_variation = "MutedLabel"
	row.add_child(note)
	box.add_child(row)
	table.row_activated.connect(func(_id) -> void: _open_center(ctx, table, keys))
	box.set_meta("table", table)
	return box


static func _bind_result(chip: FcStatusChip, row: Dictionary) -> void:
	var text := str(row["result"])
	chip.visible = text != ""
	chip.label_node.text = text
	chip.set_tone(FcStatusChip.Tone.SUCCESS if bool(row["won"]) else FcStatusChip.Tone.DANGER)


static func _open_box(ctx: FcOwnerContext, table: FcTable, keys: Array) -> void:
	if table.selected_id == null:
		ctx.tell("Select a game first.")
		return
	var key: Array = keys[int(table.selected_id)]
	for entry in ctx.controller.season().recent_boxes:
		if int(entry["day"]) == int(key[0]) and int(entry["series"]) == int(key[1]):
			ctx.open_post_game.call(entry)
			return
	ctx.tell("No box score is kept for that game (only your most recent games are stored).")


static func _open_center(ctx: FcOwnerContext, table: FcTable, keys: Array) -> void:
	if table.selected_id == null:
		ctx.tell("Select a game first.")
		return
	if ctx.open_game.is_valid():
		ctx.open_game.call(int(keys[int(table.selected_id)][2]))


## Home and away records, the streak, and the next three games as small matchup boxes (click one to open it).
static func _summary(ctx: FcOwnerContext, season: FcSeason, team_id: int) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	var st := ctx.controller.standings()
	var r: Dictionary = st.records[team_id]
	var kpis := FcKpiStrip.new()
	kpis.set_items([{"label": "Home", "value": "%d-%d" % [int(r["home_w"]), int(r["home_l"])]}, {"label": "Away", "value": "%d-%d" % [int(r["away_w"]), int(r["away_l"])]},
		{"label": "Streak", "value": st.streak_text(team_id)}])
	row.add_child(kpis)
	var upcoming: Array = []
	for g in season.games:
		if not g.played and g.involves(team_id):
			upcoming.append(g)
			if upcoming.size() == 3:
				break
	if not upcoming.is_empty():
		var strip := FcScoreboardStrip.new()
		var games: Array = []
		for g in upcoming:
			games.append({"id": g.id, "away": {"abbr": ctx.world().teams.get_by_id(g.away_id).identity.abbreviation, "look": ctx.team_look(g.away_id)},
				"home": {"abbr": ctx.world().teams.get_by_id(g.home_id).identity.abbreviation, "look": ctx.team_look(g.home_id)}, "final": false,
				"note": season.date_of_day(g.day).to_iso(), "user": true})
		strip.set_games(games)
		strip.custom_minimum_size.x = 560
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.name = "NextGames"
		strip.game_selected.connect(func(id: int) -> void:
			if ctx.open_game.is_valid():
				ctx.open_game.call(id))
		row.add_child(strip)
	return row
