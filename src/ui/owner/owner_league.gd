class_name FcOwnerLeague
extends RefCounted
## The League tab: stat leaders, champions and all-time leaders.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var box := VBoxContainer.new()
	var w := controller.state.world
	var s := controller.season()
	var stats := s.stats
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["Points", "points"], ["Rebounds", "rebounds"], ["Assists", "ast"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("%s per game" % entry[0], FcUiTokens.TYPE_H3, true))
		var rows: Array = []
		var min_games := maxi(1, floori(controller.season().next_day / 4.0)) if s.status == FcSeason.Status.REGULAR else 20
		for pid in stats.leaders(entry[1], mini(min_games, 20), 10):
			var l: Dictionary = stats.lines[pid]
			var t: FcTeam = w.teams.get_by_id(l["team"])
			rows.append([l["name"], t.identity.abbreviation if t != null else "", "%.1f" % stats.per_game(pid, entry[1])])
		col.add_child(FcTable.from_strings(["Player", "Team", entry[0]], rows, [0, 50, 60]))
		row.add_child(col)
	box.add_child(row)
	var history: Array = []
	for season in w.seasons.all():
		if season.status == FcSeason.Status.COMPLETE:
			history.append(["%d-%02d" % [season.year, (season.year + 1) % 100], ctx.team_name(season.champion_id), ctx.team_name(season.runner_up_id),
				ctx.player_name(season.awards.get("mvp", 0))])
	history.reverse()
	box.add_child(FcUiTables.label("Champions", FcUiTokens.TYPE_H3, true))
	box.add_child(FcTable.from_strings(["Season", "Champion", "Runner-up", "MVP"], history))
	var all_time := HBoxContainer.new()
	all_time.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("All-time %s" % entry[1].to_lower(), FcUiTokens.TYPE_H3, true))
		var leader_rows: Array = []
		for pid in w.career_leaders(entry[0], 8):
			var totals := w.career_totals(pid)
			var p: FcPlayer = w.players.get_by_id(pid)
			leader_rows.append([p.identity.full_name() + ("" if p.status == FcPlayer.Status.RETIRED else " *"), totals["seasons"], totals[entry[0]]])
		col.add_child(FcTable.from_strings(["Player (* active)", "Seasons", entry[1]], leader_rows, [0, 70, 80]))
		all_time.add_child(col)
	box.add_child(all_time)
	return box
