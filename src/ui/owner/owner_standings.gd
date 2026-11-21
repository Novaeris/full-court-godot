class_name FcOwnerStandings
extends RefCounted
## The Owner Standings tab: one table per conference, each team with its crest, record, games behind, last ten and streak. Sorting any
## column works (the table opens in standings order). The user's team carries a "You" tag. Built from a FcOwnerContext.


static func build(ctx: FcOwnerContext) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	scroll.add_child(row)
	var league: FcLeague = ctx.world().leagues.get_by_id(ctx.controller.league_id)
	var standings := ctx.controller.standings()
	for conference in league.conferences:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size.x = 400
		column.add_child(FcUiTables.label("%s Conference" % conference.name, FcUiTokens.TYPE_H3, true))
		var order := standings.conference_ranking(conference)
		var rows: Array = []
		for t in order:
			var r: Dictionary = standings.records[t]
			var l10 := standings.last_ten(t)
			rows.append({"id": t, "team": ctx.team_name(t), "w": r["w"], "l": r["l"], "pct": standings.win_pct(t), "gb": standings.games_behind(order[0], t),
				"l10": "%d-%d" % [l10[0], l10[1]], "l10_wins": l10[0], "streak": standings.streak_text(t)})
		column.add_child(FcTable.build(columns(ctx), rows, {"max_rows": rows.size(), "empty_title": "No teams", "compact": false}))
		row.add_child(column)
	return scroll


## The columns (public so tests and other screens can reuse the team column).
static func columns(ctx: FcOwnerContext) -> Array:
	return [
		team_column(ctx),
		{"key": "w", "title": "W", "width": 44, "kind": "number"},
		{"key": "l", "title": "L", "width": 44, "kind": "number"},
		{"key": "pct", "title": "Pct", "width": 64, "kind": "number", "format": func(v) -> String: return "%.3f" % float(v)},
		{"key": "gb", "title": "GB", "width": 54, "kind": "number", "format": func(v) -> String: return "%.1f" % float(v)},
		{"key": "l10", "title": "L10", "width": 60, "kind": "number", "sort_value": func(r: Dictionary): return r["l10_wins"]},
		{"key": "streak", "title": "Strk", "width": 56, "kind": "number"},
	]


## A column showing a crest and the team name for rows that carry "id" = the team id (and "team" = the name, used for sorting).
static func team_column(ctx: FcOwnerContext, width: int = 0) -> Dictionary:
	return {"key": "team", "title": "Team", "width": width, "kind": "custom", "fill": true,
		"make": func() -> Control: return FcTeamChip.new(),
		"bind": func(cell: Control, row: Dictionary) -> void:
			var tid := int(row["id"])
			(cell as FcTeamChip).setup(ctx.team_look(tid), str(row["team"]), 24, tid == ctx.user_team_id()),
		"format": func(v) -> String: return str(v)}
