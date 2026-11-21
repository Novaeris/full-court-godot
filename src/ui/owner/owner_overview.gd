class_name FcOwnerOverview
extends RefCounted
## The Owner Overview tab as a front-office dashboard. Every number and sentence the old tab had is kept; they are arranged as tiles:
##   the record strip and the next game as two crests facing each other; the owner report (profit, revenue, value, cash, debt), the approval meter
##   and a profit trend that is drawn only when there are at least two settled seasons; a standings snapshot and the latest news; the owner career
##   and job offers; the league rules. Built from a FcOwnerContext, read-only except for the "take the job" button (controller.transfer_to).


static func build(ctx: FcOwnerContext) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var controller := ctx.controller
	var season := controller.season()
	var record := controller.user_record()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var kpis := FcKpiStrip.new()
	kpis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kpis.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	kpis.set_items([{"label": "Record", "value": "%d-%d" % [record["wins"], record["losses"]], "delta": str(record["streak"])},
		{"label": "League rank", "value": str(record["rank"])}, {"label": "Games left", "value": str(record["games_left"])}])
	top.add_child(kpis)
	var next := controller.next_user_game()
	if next != null:
		top.add_child(_next_game_card(ctx, next, season))
	box.add_child(top)
	if season.status == FcSeason.Status.COMPLETE:
		var champs := FcPanel.new("", FcPanel.Variant.RAISED)
		champs.set_accent(FcUiTokens.GOLD)
		champs.add(ctx.team_chip(season.champion_id, 32, "Champions: %s" % ctx.team_name(season.champion_id)))
		champs.add(ctx.team_chip(season.runner_up_id, 24, "Runner-up: %s" % ctx.team_name(season.runner_up_id)))
		box.add_child(champs)
	var warning := controller.distress_warning()
	if warning != "":
		var alert := FcEmptyState.new("Warning", warning, FcEmptyState.Kind.ERROR)
		alert.custom_minimum_size.x = 300
		box.add_child(alert)
	var report := controller.owner_report()
	if not report.is_empty():
		box.add_child(_owner_report(ctx, report))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	grid.add_child(_standings_snapshot(ctx))
	var news: Array = ctx.world().news
	if not news.is_empty():
		grid.add_child(_news(news))
	box.add_child(grid)
	if controller.state.mode == FcGameState.MODE_OWNER:
		box.add_child(_owner_career(ctx))
	box.add_child(_league_rules(ctx))
	return box


static func _next_game_card(ctx: FcOwnerContext, next: FcScheduledGame, season: FcSeason) -> Control:
	var home: bool = next.home_id == ctx.user_team_id()
	var opponent: int = next.away_id if home else next.home_id
	var panel := FcPanel.new("Next game", FcPanel.Variant.SURFACE)
	panel.custom_minimum_size.x = 340
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	row.add_child(ctx.team_chip(ctx.user_team_id(), 36, ctx.controller.state.world.teams.get_by_id(ctx.user_team_id()).identity.nickname))
	row.add_child(FcUiTables.label("vs" if home else "at", FcUiTokens.TYPE_BODY))
	row.add_child(ctx.team_chip(opponent, 36, ctx.controller.state.world.teams.get_by_id(opponent).identity.nickname))
	panel.add(row)
	panel.add(FcUiTables.label("Next game: %s %s on %s" % ["vs" if home else "at", ctx.team_name(opponent), season.date_of_day(next.day).to_iso()], FcUiTokens.TYPE_SMALL))
	return panel


static func _owner_report(ctx: FcOwnerContext, report: Dictionary) -> Control:
	var panel := FcPanel.new("Owner report, %d-%02d season" % [report["year"], (report["year"] + 1) % 100], FcPanel.Variant.SURFACE)
	var money := FcKpiStrip.new()
	money.set_items([{"label": "Profit", "value": FcUiTables.money(report["profit"])}, {"label": "Revenue", "value": FcUiTables.money(report["revenue"])},
		{"label": "Franchise value", "value": FcUiTables.money(report["valuation"]), "delta": FcUiTables.money(report["valuation_change"]) + " this season"},
		{"label": "Cash", "value": FcUiTables.money(report["cash"])}, {"label": "Debt", "value": FcUiTables.money(report["debt"])}])
	panel.add(money)
	var approval := HBoxContainer.new()
	approval.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var text := FcUiTables.label("Wins %d (expected about %d)    Owner approval: %d / 100" % [report["wins"], report["expected_wins"], report["approval"]], FcUiTokens.TYPE_BODY)
	approval.add_child(text)
	var meter := FcProgress.new(FcProgress.Variant.SUCCESS if int(report["approval"]) >= 50 else FcProgress.Variant.DANGER)
	meter.custom_minimum_size.x = 160
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.set_progress(float(report["approval"]), 100.0)
	meter.tooltip_text = "Owner approval: %d / 100" % int(report["approval"])
	approval.add_child(meter)
	panel.add(approval)
	var series := ctx.controller.finance_series()
	if series.size() >= 2:   # a trend line only from real settled seasons, never invented
		var years: Array = []
		var profits: Array = []
		for s in series:
			years.append("%d-%02d" % [s["year"], (int(s["year"]) + 1) % 100])
			profits.append(s["profit"])
		var trend := FcSparkline.new(profits, FcUiTokens.INFO, years, func(v) -> String: return FcUiTables.money(int(v)))
		trend.custom_minimum_size = Vector2(260, 56)
		panel.add(FcUiTables.label("Profit by season", FcUiTokens.TYPE_SMALL))
		panel.add(trend)
	return panel


static func _standings_snapshot(ctx: FcOwnerContext) -> Control:
	var panel := FcPanel.new("Your conference", FcPanel.Variant.SURFACE)
	panel.custom_minimum_size.x = 380
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var league: FcLeague = ctx.world().leagues.get_by_id(ctx.controller.league_id)
	var standings := ctx.controller.standings()
	for conference in league.conferences:
		var order := standings.conference_ranking(conference)
		if not order.has(ctx.user_team_id()):
			continue
		var rows: Array = []
		for t in order.slice(0, 6):
			var r: Dictionary = standings.records[t]
			rows.append({"id": t, "team": ctx.team_name(t), "w": r["w"], "l": r["l"]})
		var columns := [FcOwnerStandings.team_column(ctx), {"key": "w", "title": "W", "width": 44, "kind": "number"}, {"key": "l", "title": "L", "width": 44, "kind": "number"}]
		panel.add(FcTable.build(columns, rows, {"max_rows": 6, "compact": false}))
		break
	return panel


static func _news(news: Array) -> Control:
	var panel := FcPanel.new("Latest news", FcPanel.Variant.SURFACE)
	panel.custom_minimum_size.x = 380
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(news.size() - 1, maxi(-1, news.size() - 7), -1):
		var line := FcUiTables.label("%s  %s" % [news[i]["date"], news[i]["text"]], FcUiTokens.TYPE_SMALL + 1)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add(line)
	return panel


static func _owner_career(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var panel := FcPanel.new("Your owner career", FcPanel.Variant.SURFACE)
	var stints: Array[String] = []
	for row in controller.owner_history():
		var label := ctx.team_name(row[1])
		if stints.is_empty() or not stints[stints.size() - 1].begins_with(label):
			stints.append("%s (1)" % label)
		else:
			var n := int(stints[stints.size() - 1].rsplit("(")[1].trim_suffix(")")) + 1
			stints[stints.size() - 1] = "%s (%d)" % [label, n]
	var reputation := FcUiTables.label("Owner reputation: %d / 100.%s" % [controller.owner_reputation(), "  Your career, seasons per team: " + ", ".join(stints) if not stints.is_empty() else ""], FcUiTokens.TYPE_BODY)
	reputation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add(reputation)
	var offers := controller.job_offers()
	if offers.is_empty():
		return panel
	var intro := FcUiTables.label("Job offers: other franchises would like you as their owner (you can change teams once a season, before the offseason starts)", FcUiTokens.TYPE_BODY)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add(intro)
	var rows: Array = []
	for o in offers:
		rows.append({"id": o["team"], "name": o["name"], "value": o["valuation"], "wins": o["wins"], "payroll": o["payroll"], "fans": o["fan_interest"], "cash": o["cash"], "debt": o["debt"], "seats": o["seats"]})
	var money := func(v) -> String: return FcUiTables.money(int(v))
	var table := FcTable.new([
		{"key": "name", "title": "Team"}, {"key": "value", "title": "Value", "width": 92, "kind": "number", "format": money}, {"key": "wins", "title": "Wins", "width": 54, "kind": "number"},
		{"key": "payroll", "title": "Payroll", "width": 92, "kind": "number", "format": money}, {"key": "fans", "title": "Fans", "width": 54, "kind": "number"},
		{"key": "cash", "title": "Cash", "width": 92, "kind": "number", "format": money}, {"key": "debt", "title": "Debt", "width": 92, "kind": "number", "format": money},
		{"key": "seats", "title": "Seats", "width": 64, "kind": "number"}], rows, {"max_rows": 5})
	table.custom_minimum_size.y = 40 * 6
	panel.add(table)
	panel.add(FcButton.make("Take the job with the selected team", FcButton.Variant.PRIMARY, func() -> void:
		if table.selected_id == null:
			ctx.tell("Select a team first.")
			return
		var result := controller.transfer_to(int(table.selected_id))
		if result["ok"]:
			ctx.refresh.call()
		ctx.tell(result["reason"])))
	panel.set_meta("table", table)
	return panel


static func _league_rules(ctx: FcOwnerContext) -> Control:
	var panel := FcPanel.new("League rules", FcPanel.Variant.SURFACE)
	var rules := ctx.world().rules_of_league(ctx.controller.league_id)
	var lines: Array = rules.playoffs.describe(ctx.world().leagues.get_by_id(ctx.controller.league_id))
	if rules.draft.lottery_teams > 0:
		lines.append("Draft lottery: the worst %d non-playoff teams enter and the top %d picks are drawn" % [rules.draft.lottery_teams, rules.draft.lottery_picks])
	else:
		lines.append("No draft lottery: the worst record picks first")
	lines.append("Salary cap %s, tax line %s, hard limit %s" % [FcUiTables.money(rules.cap.salary_cap), FcUiTables.money(rules.cap.luxury_tax_line), FcUiTables.money(rules.cap.effective_limit())])
	for line in lines:
		var label := FcUiTables.label(str(line), FcUiTokens.TYPE_SMALL + 1)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add(label)
	return panel
