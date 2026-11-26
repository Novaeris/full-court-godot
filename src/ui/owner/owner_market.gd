class_name FcOwnerMarket
extends RefCounted
## The Market tab: the best free agents with an offer row, and the latest first round of the draft.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var box := HBoxContainer.new()
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_child(FcUiTables.label("Best free agents", FcUiTokens.TYPE_H3, true))
	var agents := controller.free_agent_market(20)
	var rows: Array = []
	for entry in agents:
		var p: FcPlayer = entry["player"]
		rows.append({"id": p.id, "name": p.identity.full_name(), "pos": FcPosition.abbreviation(p.primary_position), "age": entry["age"], "ovr": roundi(ratings.overall(p)), "pot": p.development.potential,
			"ask": entry["ask"], "years": entry["years"], "entry": entry})
	var fa_table := FcTable.new([
		{"key": "name", "title": "Player", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"], "make": func() -> Control: return FcPlayerChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerChip).setup({"subject": FcPlayerPresentation.subject_for_player(w, int(row["id"])), "name": row["name"], "overall": row["ovr"]}, "", false, 36, true)},
		{"key": "pos", "title": "Pos", "width": 50}, {"key": "age", "title": "Age", "width": 50, "kind": "number"},
		{"key": "ovr", "title": "Ovr", "width": 62, "kind": "rating", "align": "center"}, {"key": "pot", "title": "Pot", "width": 62, "kind": "rating", "align": "center"},
		{"key": "ask", "title": "Asks", "width": 90, "kind": "number", "format": func(v) -> String: return FcUiTables.money(int(v))}, {"key": "years", "title": "Years", "width": 54, "kind": "number"}],
		rows, {"row_height": 44, "max_rows": 9})
	fa_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fa_table.custom_minimum_size.y = 44 * 7
	left.add_child(fa_table)
	var offer_row := HFlowContainer.new()
	offer_row.add_child(FcUiTables.label("Offer $M a year"))
	var offer_salary := SpinBox.new()
	offer_salary.min_value = 0.1
	offer_salary.max_value = 100
	offer_salary.step = 0.05
	offer_row.add_child(offer_salary)
	offer_row.add_child(FcUiTables.label("  years"))
	var offer_years := SpinBox.new()
	offer_years.min_value = 1
	offer_years.max_value = 5
	offer_row.add_child(offer_years)
	fa_table.row_selected.connect(func(id) -> void:
		var row := fa_table.selected_row()
		if not row.is_empty():
			offer_salary.value = int(row["ask"]) / 1e6
			offer_years.value = int(row["years"]))
	offer_row.add_child(FcUiTables.button("Sign selected free agent", func():
		if fa_table.selected_id == null:
			ctx.tell("Select a free agent first.")
			return
		var r := controller.sign_free_agent(int(fa_table.selected_id), roundi(offer_salary.value * 1e6), int(offer_years.value))
		if r["signed"]:
			ctx.refresh_now()
		ctx.tell(r["reason"])))
	left.add_child(offer_row)
	left.add_child(FcUiTables.label("Players ask for the amount shown but accept a little less, especially for longer contracts. Change the offer and press the button; a refusal tells you the least he will take."))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Latest draft (first round)", FcUiTokens.TYPE_H3, true))
	var report := controller.latest_draft_report()
	var draft_rows: Array = []
	if report.is_empty():
		right.add_child(FcUiTables.label("No draft has been held yet. The first one takes place after the season."))
	if not report.is_empty():
		for entry in report["rows"]:
			if entry["round"] != 1:
				continue
			var p: FcPlayer = w.players.get_by_id(entry["player"])
			if p != null:
				var moved: int = entry["moved"]
				draft_rows.append([entry["pick"], ctx.team_name(entry["team"]), "%+d" % moved if moved != 0 else "-", p.identity.full_name(), FcPosition.abbreviation(p.primary_position), roundi(ratings.overall(p)), p.development.potential])
		var note := FcUiTables.label("After the %d season. %s" % [report["year"], "Lottery on: 'Lot.' shows how many places the lottery moved a team up (+) or down (-)." if report["lottery"] else "No lottery: order follows the records."])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(100, 0)
		right.add_child(note)
		var winners: Array[String] = []
		for entry in report["rows"]:
			if entry["round"] == 1 and entry["moved"] > 0:
				winners.append("%s jumped %d place%s to pick %d" % [ctx.team_name(entry["team"]), entry["moved"], "" if entry["moved"] == 1 else "s", entry["pick"]])
		if not winners.is_empty():
			var winners_label := FcUiTables.label("Lottery winners: " + "; ".join(winners))
			winners_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			winners_label.custom_minimum_size = Vector2(100, 0)
			right.add_child(winners_label)
	right.add_child(FcTable.from_strings(["Pick", "Team", "Lot.", "Player", "Pos", "Ovr", "Pot"], draft_rows, [50, 0, 50, 0, 50, 50, 50]))
	box.add_child(right)
	return box
