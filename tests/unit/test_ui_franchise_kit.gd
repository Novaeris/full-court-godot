extends FcTestCase
## The Franchise Experience components (M1 of D-077): charts, the shot chart, the calendar grid, the scoreboard, news cards, matchup and
## team headers, result badges, contract bars, the card grid, the sim progress panel and race tables; the navigator's route registry and
## back stack; the shot zones shared by the simulation and the chart; and the date helpers the calendar uses. Structure and behaviour
## only; the look is checked in the Component Gallery pictures.

var host: Control


func before_each() -> void:
	FcUiTheme.build(1)
	FcMotion.reduced = true
	host = Control.new()
	host.size = Vector2(1200, 800)
	Engine.get_main_loop().root.add_child(host)


func after_each() -> void:
	FcMotion.reduced = false
	Engine.get_main_loop().root.remove_child(host)
	host.free()


func _look(key: String, primary: String) -> Dictionary:
	return FcTeamLook.resolve(FcTeamLook.subject(key, key.capitalize(), key.substr(0, 3), primary, "#ffffff"))


# --- dates ------------------------------------------------------------------------------------------------------------------

func test_weekday_is_monday_based_and_matches_known_dates() -> void:
	assert_eq(FcDate.new(1970, 1, 1).weekday(), 3, "1970-01-01 was a Thursday")
	assert_eq(FcDate.new(2026, 11, 23).weekday(), 0, "2026-11-23 is a Monday")
	assert_eq(FcDate.new(2026, 11, 29).weekday(), 6, "and 2026-11-29 a Sunday")
	assert_eq(FcDate.new(1969, 12, 31).weekday(), 2, "dates before 1970 work too")
	assert_eq(FcDate.new(2026, 11, 19).month_start().to_iso(), "2026-11-01")


# --- shot zones ---------------------------------------------------------------------------------------------------------------

func test_shot_zones_cover_the_court_and_match_the_shot_kinds() -> void:
	assert_eq(FcShotZones.zone_of(FcShotZones.HOOP), FcShotZones.RIM)
	assert_eq(FcShotZones.zone_of(Vector2(7.5, 4.5)), FcShotZones.PAINT)
	assert_eq(FcShotZones.zone_of(Vector2(3.0, 3.0)), FcShotZones.MID_LEFT)
	assert_eq(FcShotZones.zone_of(Vector2(12.0, 3.0)), FcShotZones.MID_RIGHT)
	assert_eq(FcShotZones.zone_of(Vector2(7.5, 7.0)), FcShotZones.MID_CENTER)
	assert_eq(FcShotZones.zone_of(Vector2(0.4, 1.0)), FcShotZones.CORNER3_LEFT)
	assert_eq(FcShotZones.zone_of(Vector2(14.6, 1.0)), FcShotZones.CORNER3_RIGHT)
	assert_eq(FcShotZones.zone_of(Vector2(7.5, 9.5)), FcShotZones.TOP3)
	assert_eq(FcShotZones.zone_of(Vector2(2.5, 7.5)), FcShotZones.WING3_LEFT)
	assert_eq(FcShotZones.zone_of(Vector2(12.5, 7.5)), FcShotZones.WING3_RIGHT)
	assert_eq(FcShotZones.zone_of(Vector2(7.5, 40)), FcShotZones.TOP3, "spots off the court are clamped")
	for id in FcShotZones.ids():
		assert_true(FcShotZones.display_name(id) != id, "%s has a name" % id)
	assert_eq(FcShotZones.shot_type_of(FcShotZones.RIM), FcGameEventLog.SHOT_RIM)
	assert_eq(FcShotZones.shot_type_of(FcShotZones.MID_CENTER), FcGameEventLog.SHOT_MID)
	assert_eq(FcShotZones.shot_type_of(FcShotZones.TOP3), FcGameEventLog.SHOT_THREE)
	# every point of a fine grid gets a zone, and three-point spots are exactly the three-point zones
	var y := 0.1
	while y < FcShotZones.DEPTH:
		var x := 0.1
		while x < FcShotZones.WIDTH:
			var p := Vector2(x, y)
			var zone := FcShotZones.zone_of(p)
			assert_eq(FcShotZones.shot_type_of(zone) == FcGameEventLog.SHOT_THREE, FcShotZones.is_three(p), "%s at %s" % [zone, p])
			x += 0.7
		y += 0.7


# --- charts -----------------------------------------------------------------------------------------------------------------

func test_line_chart_draws_only_given_data() -> void:
	var chart := FcLineChart.new([{"name": "Revenue", "values": [100, 120, 150]}, {"name": "Profit", "values": [10, -5, 20]}], ["2026", "2027", "2028"],
		func(v) -> String: return "$%dM" % int(v))
	host.add_child(chart)
	assert_true(chart.has_lines())
	assert_eq(chart.point_count(), 3)
	assert_true(chart.summary().contains("Revenue: 2026 $100M"), chart.summary())
	assert_true(chart.summary().contains("Profit: 2026 $10M, 2027 $-5M"), chart.summary())
	chart.set_data([{"name": "One", "values": [5]}])
	assert_true(not (chart.has_lines()), "a single point is not a trend")
	assert_eq(chart.summary(), "")


func test_heat_zones_shade_by_comparison_and_summarise() -> void:
	var chart := FcHeatZones.new().set_data({FcShotZones.RIM: {"made": 12, "att": 18}, FcShotZones.TOP3: {"made": 2, "att": 10}},
		{FcShotZones.RIM: 0.58, FcShotZones.TOP3: 0.36})
	host.add_child(chart)
	assert_eq(chart.total_attempts(), 28)
	assert_true(chart.summary().contains("At the rim 12/18 (67%, league 58%)"), chart.summary())
	assert_true(chart.zone_color(FcShotZones.RIM).is_equal_approx(Color(FcUiTokens.PRIMARY, chart.zone_color(FcShotZones.RIM).a)), "above the league is hot")
	assert_true(chart.zone_color(FcShotZones.TOP3).is_equal_approx(Color(FcUiTokens.INFO, chart.zone_color(FcShotZones.TOP3).a)), "below is cold")
	assert_eq(chart.zone_color(FcShotZones.PAINT).a, 0.0, "a zone without attempts stays unshaded")
	assert_eq(FcHeatZones.new().set_data({}).summary(), "")


# --- calendar -----------------------------------------------------------------------------------------------------------------

func test_calendar_grid_shows_whole_weeks_and_selects_days() -> void:
	var grid := FcCalendarGrid.new()
	host.add_child(grid)
	var cells := {"2026-11-19": {"user": {"look": _look("dallas", "#2255aa"), "home": false, "opponent": "DAL", "result": "W", "score": "102-99"}, "games": 7,
		"events": [{"text": "Trade deadline", "tone": "gold"}]}}
	grid.setup(2026, 11, cells, "2026-11-19", "2026-11-20")
	var dates := grid.shown_dates()
	assert_eq(dates.size() % 7, 0, "whole weeks")
	assert_eq(FcDate.from_iso(dates[0]).weekday(), 0, "weeks start on Monday")
	assert_true(dates.has("2026-11-01") and dates.has("2026-11-30"))
	assert_eq(dates[0], "2026-10-26", "November 2026 starts on a Sunday, so the grid starts the Monday before")
	assert_eq(FcCalendarGrid.month_title(2026, 11), "November 2026")
	var cell := grid.cell_for("2026-11-19")
	assert_true(cell != null)
	assert_true(cell.tooltip_text.contains("at DAL, won 102-99"), cell.tooltip_text)
	assert_true(cell.tooltip_text.contains("7 league games") and cell.tooltip_text.contains("Trade deadline"), cell.tooltip_text)
	var picked: Array = []
	grid.date_selected.connect(func(iso: String) -> void: picked.append(iso))
	grid.select("2026-11-21")
	assert_eq(picked, ["2026-11-21"])
	assert_eq(grid.selected_iso, "2026-11-21")
	grid._move("2026-11-21", 7)
	assert_eq(grid.selected_iso, "2026-11-28", "down a row is a week later")
	grid._move("2026-11-28", 30)
	assert_eq(grid.selected_iso, "2026-11-28", "moving past the shown weeks does nothing")


func test_scoreboard_strip_shows_scores_only_for_final_games() -> void:
	var strip := FcScoreboardStrip.new()
	host.add_child(strip)
	var got: Array = []
	strip.game_selected.connect(func(id: int) -> void: got.append(id))
	strip.set_games([
		{"id": 11, "away": {"abbr": "DAL", "score": 99, "look": _look("dallas", "#2255aa")}, "home": {"abbr": "HOU", "score": 102}, "final": true, "note": "OT"},
		{"id": 12, "away": {"abbr": "ATL"}, "home": {"abbr": "MEX"}, "final": false}])
	assert_eq(strip.box_count(), 2)
	assert_eq(FcScoreboardStrip.describe(strip.games[0]), "DAL 99 at HOU 102, final (OT)")
	assert_eq(FcScoreboardStrip.describe(strip.games[1]), "ATL at MEX, upcoming", "no score before the game")
	(strip._row.get_child(1) as Button).pressed.emit()
	assert_eq(got, [12])
	strip.set_games([], "Rest day")
	assert_eq(strip.box_count(), 0)


# --- cards and headers -----------------------------------------------------------------------------------------------------------

func test_news_card_sizes_by_tier() -> void:
	var lead := FcNewsCard.new().setup({"headline": "Champions!", "deck": "Houston win the title.", "kind": "Finals", "tier": FcNewsCard.TIER_LEAD, "team_look": _look("houston", "#552288")})
	var brief := FcNewsCard.new().setup({"headline": "Minor signing", "deck": "hidden for briefs", "tier": FcNewsCard.TIER_BRIEF})
	host.add_child(lead)
	host.add_child(brief)
	assert_eq(lead.tooltip_text, "Champions!")
	assert_true(_has_label_text(lead, "Houston win the title."), "a lead story shows its deck")
	assert_true(not (_has_label_text(brief, "hidden for briefs")), "a brief shows the headline only")
	var fired := [false]
	lead.activated.connect(func() -> void: fired[0] = true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	lead._gui_input(click)
	assert_true(fired[0])


func test_matchup_banner_and_team_header_describe_themselves() -> void:
	var m := FcMatchupBanner.new().setup({"away": {"name": "Dallas Ramparts", "record": "8-7", "look": _look("dallas", "#2255aa")},
		"home": {"name": "Houston Sentinels", "record": "9-6", "look": _look("houston", "#552288")}, "caption": "2026-11-19"})
	host.add_child(m)
	assert_eq(m.tooltip_text, "Dallas Ramparts (8-7) at Houston Sentinels (9-6). 2026-11-19")
	m.setup({"away": {"name": "A", "score": 99}, "home": {"name": "B", "score": 102}, "final": true, "caption": "Final"})
	assert_eq(m.tooltip_text, "A 99 at B 102. Final")
	var h := FcTeamHeader.new().setup({"look": _look("houston", "#552288"), "name": "Houston Sentinels", "subtitle": "Season 2026-27",
		"pills": [{"label": "Record", "value": "9-6"}, {"label": "Rank", "value": "4th"}]})
	host.add_child(h)
	assert_true(h.tooltip_text.contains("Record 9-6") and h.tooltip_text.contains("Rank 4th"), h.tooltip_text)


func test_result_badge_text_carries_the_meaning() -> void:
	var b := FcResultBadge.new(FcResultBadge.Kind.WIN, "102-99")
	host.add_child(b)
	assert_eq(b.text(), "W 102-99")
	b.set_result(FcResultBadge.Kind.LOSS, "95-101")
	assert_eq(b.text(), "L 95-101")
	assert_eq(b.set_result(FcResultBadge.Kind.UPCOMING).text(), "UPCOMING")
	assert_eq(FcResultBadge.text_of(FcResultBadge.Kind.FINAL), "FINAL")


func test_contract_bar_reads_a_contract_with_options() -> void:
	var c := FcContract.new(1)
	for i in 3:
		var y := FcContractYear.new()
		y.season = 2026 + i
		y.salary = 10_000_000 + i * 500_000
		y.guaranteed = y.salary
		if i == 2:
			y.option_type = FcContractYear.OptionType.TEAM
			y.guaranteed = 0
		c.years.append(y)
	var years := FcContractBar.years_of(c)
	assert_eq(years.size(), 3)
	assert_eq(years[2]["option"], "TO")
	var bar := FcContractBar.new().setup(years, 2027)
	host.add_child(bar)
	assert_true(bar.summary().contains("2028-29 $11.0M (team option)"), bar.summary())
	assert_eq(FcContractBar.years_of(null), [])
	assert_eq(FcContractBar.new().setup([], 2026).summary(), "No contract")


func test_player_card_grid_selects_and_opens() -> void:
	var cards: Array = []
	for i in 3:
		cards.append({"id": 100 + i, "vm": {"subject": {"key": "p%d" % i, "seed": i}, "name": "Player %d" % i, "position": "SF", "overall": 60 + i,
			"number": str(10 + i), "potential": 70, "stat_line": "12.0 PPG", "injury": "Ankle, 3 games" if i == 1 else ""}})
	var grid := FcPlayerCardGrid.new().set_cards(cards)
	host.add_child(grid)
	assert_eq(grid.card_count(), 3)
	var selected: Array = []
	var opened: Array = []
	grid.player_selected.connect(func(id: int) -> void: selected.append(id))
	grid.player_activated.connect(func(id: int) -> void: opened.append(id))
	grid.tile_of(101).activated.emit()
	assert_eq(selected, [101])
	assert_true(grid.tile_of(101).selected and not grid.tile_of(100).selected)
	grid.tile_of(102).opened.emit()
	assert_eq(opened, [102])


func test_sim_progress_reports_days_ticker_and_stop() -> void:
	var p := FcSimProgress.new()
	host.add_child(p)
	p.start("Simulating to 2027-01-15", 10)
	p.advance(3, "2026-11-22", ["DAL 99 at HOU 102"])
	assert_eq(p.count_text(), "Day 3 of 10   ·   2026-11-22")
	assert_between(p.progress(), 0.299, 0.301)
	for i in 6:
		p.advance(4 + i, "x", ["line %d" % i])
	assert_eq(p.ticker().size(), FcSimProgress.TICKER_LINES, "the ticker keeps only the latest lines")
	assert_eq(p.ticker()[0], "line 5", "newest first")
	var stops := [0]
	p.stop_requested.connect(func() -> void: stops[0] += 1)
	p._stop.pressed.emit()
	assert_eq(stops[0], 1)
	p.finish("Your game against Dallas")
	assert_true(p._stop.disabled)


func test_race_table_ranks_with_movement() -> void:
	var t := FcRaceTable.new().set_entries([{"id": 1, "name": "A", "value": "31.2", "move": 2}, {"id": 2, "name": "B", "value": "29.0", "move": -1, "gap": "-2.2"}, {"id": 3, "name": "C", "value": "28"}])
	host.add_child(t)
	assert_eq(t.get_child_count(), 3)
	assert_eq(FcRaceTable.move_text(2), "▲ 2")
	assert_eq(FcRaceTable.move_text(-1), "▼ 1")
	assert_eq(FcRaceTable.move_text(0), "–")
	assert_true((t.get_child(1) as Control).tooltip_text.begins_with("2. B 29.0"))
	t.set_entries([], "Nobody yet")
	assert_eq(t.get_child_count(), 1)


# --- navigator -------------------------------------------------------------------------------------------------------------------

func test_navigator_back_stack_rebuilds_previous_screens_with_their_arguments() -> void:
	var nav := FcNavigator.new()
	var built: Array = []
	for id in ["home", "calendar", "game"]:
		var screen_id: String = id
		nav.register(screen_id, func(args: Dictionary) -> void: built.append([screen_id, args.get("n", 0)]))
	assert_true(not (nav.open("nowhere")), "an unknown screen opens nothing")
	nav.set_root("home")
	assert_true(nav.open("calendar", {"n": 1}))
	assert_eq(nav.take_motion(), "push")
	assert_eq(nav.take_motion(), "replace", "taking the motion resets it")
	nav.open("game", {"n": 7})
	assert_eq(nav.stack_ids(), ["home", "calendar", "game"])
	assert_eq(nav.top_args(), {"n": 7})
	nav.open("game", {"n": 7})
	assert_eq(nav.stack_depth(), 3, "opening the top screen again only rebuilds it")
	assert_true(nav.back_in_stack())
	assert_eq(built[-1], ["calendar", 1], "back rebuilds the calendar with its own arguments")
	assert_eq(nav.take_motion(), "pop")
	nav.replace("game", {"n": 2})
	assert_eq(nav.stack_ids(), ["home", "game"])
	nav.stack_back().call()
	assert_eq(built[-1], ["home", 0])
	assert_true(not (nav.back_in_stack()), "nothing below the root")
	nav.set_root("home")
	for i in FcNavigator.STACK_LIMIT + 5:
		nav.open("calendar" if i % 2 == 0 else "game", {"n": i})
	assert_eq(nav.stack_depth(), FcNavigator.STACK_LIMIT, "the stack is bounded")


func test_owner_dashboard_is_the_root_of_the_owner_stack() -> void:
	var nav := FcNavigator.new()
	nav.register("dashboard", func(_a: Dictionary) -> void: pass)
	nav.set_root("dashboard")
	assert_eq(nav.stack_ids(), ["dashboard"])
	assert_true(nav.has_route("dashboard"))


func _has_label_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for c in node.get_children():
		if _has_label_text(c, text):
			return true
	return false
