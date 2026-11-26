class_name FcOwnerRecords
extends RefCounted
## The league's Hall of Fame and record book (and the owner's own career), the last page of the History tab.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var records := FcRecords.new(w, controller.league_id)
	var box := HBoxContainer.new()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if controller.state.mode == FcGameState.MODE_OWNER and not controller.owner_history().is_empty():
		left.add_child(FcUiTables.label("Your ownership career (reputation %d)" % controller.owner_reputation(), FcUiTokens.TYPE_H3, true))
		var career_rows: Array = []
		var history: Array = controller.owner_history()
		for i in range(history.size() - 1, -1, -1):
			var h: Array = history[i]
			career_rows.append(["%d-%02d" % [h[0], (h[0] + 1) % 100], ctx.team_name(h[1]), h[3], h[2], "Champions" if h[4] == 1 else ""])
		var career_table := FcTable.from_strings(["Season", "Team", "Wins", "Approval", ""], career_rows, [70, 0, 50, 70, 90])
		career_table.custom_minimum_size = Vector2(0, 150)
		career_table.size_flags_vertical = Control.SIZE_FILL
		left.add_child(career_table)
	left.add_child(FcUiTables.label("Hall of Fame", FcUiTokens.TYPE_H3, true))
	var hof_rows: Array = []
	for entry in records.hall_of_fame(controller.state.current_season):
		var h := records.honours_of(entry[1])
		var t := w.career_totals(entry[1])
		hof_rows.append([w.player_name(entry[1]), entry[2], t["seasons"], t["points"], h["mvp"], h["titles"], roundi(entry[0])])
	if hof_rows.is_empty():
		left.add_child(FcUiTables.label("Nobody has been inducted yet. Retired stars are eligible %d seasons after their last game." % FcRecords.EXPERIENCE_WAIT))
	left.add_child(FcTable.from_strings(["Player", "Inducted", "Seasons", "Points", "MVPs", "Titles", "Score"], hof_rows, [0, 70, 70, 70, 50, 50, 50]))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		right.add_child(FcUiTables.label("Best single seasons: %s" % entry[1].to_lower(), FcUiTokens.TYPE_H3, true))
		var rows: Array = []
		for rec in records.single_season_records(entry[0], 5):
			rows.append([w.player_name(rec[1]), "%d-%02d" % [rec[2], (rec[2] + 1) % 100], rec[0]])
		right.add_child(FcTable.from_strings(["Player", "Season", entry[1]], rows, [0, 80, 80]))
	box.add_child(right)
	return box
