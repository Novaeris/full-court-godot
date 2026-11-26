class_name FcOwnerRoster
extends RefCounted
## The Owner Roster tab: the user's players as a sortable table with each player's portrait, position, age, height, overall and potential as
## rating badges, salary, contract end with a bar of the contract used, per-game stats and health, and the actions that act on the selected
## player (extend the contract, release, open the profile). Every column and action of the old table is kept. Built from a FcOwnerContext.
## A Table / Cards switch (D-077 M4) shows the same roster as player cards (number, rating, potential, this season's line, injury); the actions
## act on the player selected in whichever view is showing, and the choice is remembered for the game.


static func build(ctx: FcOwnerContext) -> Control:
	var world := ctx.world()
	var team: FcTeam = world.teams.get_by_id(ctx.user_team_id())
	var ratings := FcPlayerRatings.load_default()
	var season_year := ctx.controller.state.current_season
	var stats := ctx.controller.season().stats
	var rows: Array = []
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		var c := world.active_contract_of(p.id)
		var overall := roundi(ratings.overall(p))
		var years_total: int = (c.end_season() - c.start_season() + 1) if c != null else 0
		var years_used: int = clampi(season_year - c.start_season() + 1, 0, years_total) if c != null else 0
		rows.append({"id": p.id, "name": p.identity.full_name(), "overall": overall, "pos": FcPosition.abbreviation(p.primary_position), "age": p.age_on(FcDate.new(season_year, 7, 1)),
			"height": p.physical.height_cm, "pot": p.development.potential, "salary": c.salary_for(season_year) if c != null else 0, "thru": c.end_season() if c != null else 0,
			"used": (float(years_used) / float(years_total) * 100.0) if years_total > 0 else 0.0, "ppg": stats.per_game(p.id, "points"), "rpg": stats.per_game(p.id, "rebounds"),
			"apg": stats.per_game(p.id, "ast"), "mpg": stats.per_game(p.id, "minutes"), "health": "" if p.games_out == 0 else "OUT %d games: %s" % [p.games_out, p.injury]})
	rows.sort_custom(func(a, b): return a["overall"] > b["overall"])
	var one_decimal := func(v) -> String: return "%.1f" % float(v)
	var columns := [
		{"key": "name", "title": "Player", "width": 0, "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"],
			"make": func() -> Control: return FcPlayerChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void:
				var subject := FcPlayerPresentation.subject_for_player(world, int(row["id"]))
				(cell as FcPlayerChip).setup({"subject": subject, "name": row["name"], "overall": row["overall"]}, "", false, 36, true)},
		{"key": "pos", "title": "Pos", "width": 52},
		{"key": "age", "title": "Age", "width": 50, "kind": "number"},
		{"key": "height", "title": "Height", "width": 74, "kind": "number", "format": func(v) -> String: return "%d cm" % int(v)},
		{"key": "overall", "title": "Ovr", "width": 62, "kind": "rating", "align": "center"},
		{"key": "pot", "title": "Pot", "width": 62, "kind": "rating", "align": "center"},
		{"key": "salary", "title": "Salary", "width": 90, "kind": "number", "format": func(v) -> String: return FcUiTables.money(int(v)) if int(v) > 0 else "-"},
		{"key": "thru", "title": "Thru", "width": 58, "kind": "number", "format": func(v) -> String: return str(int(v)) if int(v) > 0 else "-"},
		{"key": "used", "title": "Contract", "width": 92, "kind": "bar", "tooltip": "How much of the contract has been played"},
		{"key": "ppg", "title": "PPG", "width": 54, "kind": "number", "format": one_decimal},
		{"key": "rpg", "title": "RPG", "width": 54, "kind": "number", "format": one_decimal},
		{"key": "apg", "title": "APG", "width": 54, "kind": "number", "format": one_decimal},
		{"key": "mpg", "title": "MPG", "width": 54, "kind": "number", "format": one_decimal},
		{"key": "health", "title": "Health", "width": 150},
	]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var view: String = str(ctx.memory.get("roster_view", "table"))
	var switch := FcChoiceGroup.new()
	switch.set_options([["table", "Table"], ["cards", "Cards"]], view)
	switch.name = "RosterView"
	switch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(switch)
	var table := FcTable.new(columns, rows, {"row_height": 44, "max_rows": 12, "empty_title": "No players", "empty_text": "The roster is empty."})
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 44 * 8
	box.add_child(table)
	var cards: Array = []
	for r in rows:
		var p2: FcPlayer = world.players.get_by_id(int(r["id"]))
		var vm := {"subject": FcPlayerPresentation.subject_for_player(world, int(r["id"])), "name": r["name"], "position": r["pos"], "overall": r["overall"],
			"potential": r["pot"], "number": str(p2.jersey_number), "team": {"abbreviation": team.identity.abbreviation},
			"stat_line": "%.1f pts  %.1f reb  %.1f ast" % [r["ppg"], r["rpg"], r["apg"]] if stats.games_played(int(r["id"])) > 0 else "No games yet",
			"injury": ("Out %d: %s" % [p2.games_out, p2.injury]) if p2.games_out > 0 else ""}
		cards.append({"id": int(r["id"]), "vm": vm})
	var grid := FcPlayerCardGrid.new().set_cards(cards, Vector2(150, 236))
	grid.custom_minimum_size.y = 260
	grid.name = "RosterCards"
	box.add_child(grid)
	table.visible = view == "table"
	grid.visible = view == "cards"
	switch.selected.connect(func(id: String) -> void:
		ctx.memory["roster_view"] = id
		table.visible = id == "table"
		grid.visible = id == "cards")
	var selected_id := func() -> Variant:
		if grid.visible:
			return grid.selected_id if grid.selected_id > 0 else null
		return table.selected_id
	var hint := FcUiTables.label("Select a player, then extend his contract (only in the last year of the deal), release him, or open his profile.", FcUiTokens.TYPE_SMALL)
	hint.theme_type_variation = "MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var actions := HFlowContainer.new()   # wraps onto a second line in a small window instead of forcing the screen wider
	actions.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	actions.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	var expiring := {}
	for e in ctx.controller.expiring_players():
		expiring[e["player"].id] = e
	var ext_salary := SpinBox.new()
	ext_salary.tooltip_text = "The yearly salary you offer, in millions, to keep this player. He accepts a little less than he asks."
	ext_salary.min_value = 0.1
	ext_salary.max_value = 100
	ext_salary.step = 0.05
	var ext_years := SpinBox.new()
	ext_years.tooltip_text = "Length of the new contract in years. Players want long deals when young and short ones when older."
	ext_years.min_value = 1
	ext_years.max_value = 5
	var fill_offer := func(id) -> void:
		if expiring.has(id):
			ext_salary.value = expiring[id]["ask"] / 1e6
			ext_years.value = expiring[id]["years"]
	table.row_selected.connect(fill_offer)
	grid.player_selected.connect(fill_offer)
	actions.add_child(FcUiTables.label("Extension $M"))
	actions.add_child(ext_salary)
	actions.add_child(FcUiTables.label("years"))
	actions.add_child(ext_years)
	actions.add_child(FcButton.make("Extend contract of selected player", FcButton.Variant.SECONDARY, func() -> void:
		if selected_id.call() == null:
			ctx.tell("Select a player first.")
			return
		var r := ctx.controller.extend_contract(int(selected_id.call()), roundi(ext_salary.value * 1e6), int(ext_years.value))
		if r["ok"]:
			ctx.refresh.call()
		ctx.tell(r["reason"])))
	actions.add_child(FcButton.make("Release selected player (pay half his salary)", FcButton.Variant.DESTRUCTIVE, func() -> void:
		if selected_id.call() == null:
			ctx.tell("Select a player first.")
			return
		var r := ctx.controller.release_player(int(selected_id.call()))
		if r["released"]:
			ctx.refresh.call()
		ctx.tell(r["reason"])))
	var open_profile := func() -> void:
		if selected_id.call() == null:
			ctx.tell("Select a player first.")
			return
		ctx.open_profile.call(int(selected_id.call()))
	actions.add_child(FcButton.make("Player profile of selected player", FcButton.Variant.SECONDARY, open_profile))
	table.row_activated.connect(func(_id) -> void: open_profile.call())
	grid.player_activated.connect(func(_id: int) -> void: open_profile.call())
	box.add_child(actions)
	box.set_meta("table", table)
	box.set_meta("cards", grid)
	return box
