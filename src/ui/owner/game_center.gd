class_name FcGameCenter
extends RefCounted
## The Game Center (D-077 M5): one full screen for one game, reached from the HQ, the schedule, the calendar and the scoreboard.
##   Hero:     the matchup banner (records before the game, the final score after it) and the game's date, round and status.
##   Actions:  exactly what FcGameAvailability allows for this game: play it (the user's next game), play it and watch the broadcast, follow
##             it (another teams' game, so it is recorded), watch the replay, open the full summary. Nothing the data cannot do is offered.
##   Before:   the preview of both teams (projected starting fives by the game's own rule, injuries, records, ranks; FcGameDayScreen), the
##             season series, both teams' last five results and a comparison of points scored and allowed.
##   After:    the full post-game summary when the box score was kept (FcPostGameScreen: score, line score, player of the game, performers,
##             team comparison, implications, box score), otherwise the stored result line (periods, top scorers, player of the game); and
##             the news of that day about the two teams.
## Read-only apart from the actions, which go through the controller.


## `on`: {"play": Callable(game_id, watch: bool), "follow": Callable(game_id), "replay": Callable(entry), "summary": Callable(entry),
##        "profile": Callable(player_id)}.
static func build(ctx: FcOwnerContext, game_id: int, on: Dictionary) -> Control:
	var c := ctx.controller
	var season := c.season()
	var game := season.game_by_id(game_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	if game == null:
		box.add_child(FcEmptyState.new("Game not found", "This game is not part of the current season.", FcEmptyState.Kind.EMPTY))
		return box
	var standings := c.standings()
	var caps := FcGameAvailability.capabilities(season, game, ctx.user_team_id(), c.next_user_game())
	box.add_child(_hero(ctx, season, game, standings))
	box.add_child(_actions(ctx, game, caps, on))
	if game.played:
		box.add_child(_after(ctx, season, game, caps, on))
	else:
		box.add_child(_before(ctx, season, game, standings))
	box.set_meta("caps", caps)
	return box


static func _hero(ctx: FcOwnerContext, season: FcSeason, game: FcScheduledGame, standings: FcStandings) -> Control:
	var wrap := VBoxContainer.new()
	var side := func(team_id: int, score: int) -> Dictionary:
		var r: Dictionary = standings.records.get(team_id, {"w": 0, "l": 0})
		return {"look": ctx.team_look(team_id), "name": ctx.team_name(team_id), "record": "%d-%d" % [int(r["w"]), int(r["l"])], "score": score}
	var date := season.date_of_day(game.day).to_iso()
	var round := "Playoffs, series %d" % game.series if game.series > 0 else "Regular season"
	var status := ("Final" + (" (OT)" if game.overtimes == 1 else (" (%dOT)" % game.overtimes if game.overtimes > 1 else ""))) if game.played else "Upcoming"
	var banner := FcMatchupBanner.new().setup({"away": side.call(game.away_id, game.away_score), "home": side.call(game.home_id, game.home_score),
		"center": "AT", "final": game.played, "caption": "%s  ·  %s  ·  %s" % [date, round, status]})
	banner.custom_minimum_size = Vector2(0, 190)
	banner.name = "GameCenterBanner"
	wrap.add_child(banner)
	return wrap


static func _actions(ctx: FcOwnerContext, game: FcScheduledGame, caps: Dictionary, on: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	row.name = "GameActions"
	if caps["watch_live"]:
		row.add_child(FcButton.make("Play and watch the broadcast", FcButton.Variant.PRIMARY, func() -> void: on["play"].call(game.id, true)))
		row.add_child(FcButton.make("Simulate this game", FcButton.Variant.SECONDARY, func() -> void: on["play"].call(game.id, false)))
	if caps["follow"]:
		row.add_child(FcButton.make("Follow this game (record it)", FcButton.Variant.SECONDARY, func() -> void: on["follow"].call(game.id)))
	elif caps["followed"] and not game.played:
		row.add_child(FcStatusChip.make("FOLLOWING: it will be recorded", FcStatusChip.Tone.INFO))
	if caps["replay"]:
		row.add_child(FcButton.make("Watch the replay", FcButton.Variant.PRIMARY, func() -> void: on["replay"].call(FcGameAvailability.stored_box(ctx.controller.season(), game))))
	if game.played and not caps["box_score"]:
		var note := Label.new()
		note.text = "Only the result is kept for this game: full box scores and replays are kept for your team's last %d games and for games you follow." % FcSeason.RECENT_BOX_LIMIT
		note.theme_type_variation = "MutedLabel"
		row.add_child(note)
	if not game.played and not caps["watch_live"] and caps["user_game"]:
		var wait := Label.new()
		wait.text = "Your earlier games come first: this game can be played when it is your next one."
		wait.theme_type_variation = "MutedLabel"
		row.add_child(wait)
	return row


# --- before the game ----------------------------------------------------------------------------------------------------------

static func _before(ctx: FcOwnerContext, season: FcSeason, game: FcScheduledGame, standings: FcStandings) -> Control:
	var c := ctx.controller
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var model := FcGameDay.build(c.state.world, c.engine, standings, game, ctx.user_team_id(), season.date_of_day(game.day).to_iso())
	var preview := FcGameDayScreen.new().setup(model, FcGameDay._looks(c.state.world, model))
	preview.name = "GameDayScreen"
	box.add_child(preview)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	var series := FcPanel.new("Season series and form", FcPanel.Variant.SURFACE)
	series.custom_minimum_size.x = 380
	series.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h2h: Array = standings.records[game.home_id]["h2h"].get(game.away_id, [0, 0])
	series.add(FcStatLine.make("Season series", "%s %d, %s %d" % [ctx.team_name(game.home_id), int(h2h[0]), ctx.team_name(game.away_id), int(h2h[1])]))
	for team_id in [game.away_id, game.home_id]:
		var form := HBoxContainer.new()
		form.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
		form.add_child(ctx.team_chip(team_id, 20, ctx.world().teams.get_by_id(team_id).identity.abbreviation))
		var results: Array = standings.records[team_id]["results"]
		for won in results.slice(maxi(0, results.size() - 5)):
			form.add_child(FcResultBadge.new(FcResultBadge.Kind.WIN if won else FcResultBadge.Kind.LOSS))
		if results.is_empty():
			var none := Label.new()
			none.text = "no games yet"
			none.theme_type_variation = "MutedLabel"
			form.add_child(none)
		series.add(form)
	row.add_child(series)
	var compare := FcPanel.new("Team comparison (per game)", FcPanel.Variant.SURFACE)
	compare.custom_minimum_size.x = 380
	compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var per := func(t: int, key: String) -> float: return float(standings.records[t][key]) / float(maxi(1, standings.games_played(t)))
	if standings.games_played(game.away_id) > 0 and standings.games_played(game.home_id) > 0:
		for spec in [["Points scored", "pf", false], ["Points allowed", "pa", true]]:
			var a: float = per.call(game.away_id, spec[1])
			var h: float = per.call(game.home_id, spec[1])
			compare.add(FcStatBar.new("%s: %s / %s" % [spec[0], ctx.world().teams.get_by_id(game.away_id).identity.abbreviation, ctx.world().teams.get_by_id(game.home_id).identity.abbreviation],
				a, h, "%.1f" % a, "%.1f" % h, bool(spec[2])))
	else:
		compare.add(FcStatLine.make("Comparison", "after both teams have played"))
	row.add_child(compare)
	box.add_child(row)
	return box


# --- after the game -------------------------------------------------------------------------------------------------------------

static func _after(ctx: FcOwnerContext, season: FcSeason, game: FcScheduledGame, caps: Dictionary, on: Dictionary) -> Control:
	var c := ctx.controller
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	if caps["box_score"]:
		var entry := FcGameAvailability.stored_box(season, game)
		var built := FcPostGame.for_owner(c, entry["box"], entry.get("events", {}))
		var screen := FcPostGameScreen.new().setup(built["vm"], built["colors"])
		screen.name = "Summary"
		screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(screen)
	else:
		box.add_child(_line_panel(ctx, game))
	var news := _news_of_the_day(ctx, season, game)
	if not news.is_empty():
		var panel := FcPanel.new("News of the day", FcPanel.Variant.SURFACE)
		for item in news:
			panel.add(FcNewsCard.new().setup({"headline": str(item["text"]), "kind": FcOwnerHq.kind_label(str(item["kind"])), "date": str(item["date"]),
				"tier": FcNewsCard.TIER_BRIEF, "team_look": ctx.team_look(int(item["team"])) if int(item.get("team", 0)) > 0 else {}}))
		box.add_child(panel)
	return box


## The stored compact result: periods, the three top scorers of each team, the player of the game.
static func _line_panel(ctx: FcOwnerContext, game: FcScheduledGame) -> Control:
	var panel := FcPanel.new("Result", FcPanel.Variant.SURFACE)
	panel.name = "ResultLine"
	var q: Array = game.line.get("q", [])
	if q.size() == 2:
		var head: Array = ["Team"]
		for i in (q[0] as Array).size():
			head.append(str(i + 1) if i < 4 else "OT%d" % (i - 3))
		head.append("T")
		var rows: Array = []
		for side in 2:
			var team_id := game.home_id if side == 0 else game.away_id
			var r: Array = [ctx.world().teams.get_by_id(team_id).identity.abbreviation]
			for v in q[side]:
				r.append(str(v))
			r.append(str(game.home_score if side == 0 else game.away_score))
			rows.append(r)
		panel.add(FcTable.from_strings(head, rows))
	var top: Array = game.line.get("top", [])
	if not top.is_empty():
		var rows2: Array = []
		for r in top:
			rows2.append([ctx.player_name(int(r[0])), ctx.world().teams.get_by_id(int(r[4])).identity.abbreviation, str(r[1]), str(r[2]), str(r[3])])
		panel.add(FcTable.from_strings(["Top scorers", "Team", "PTS", "REB", "AST"], rows2, [0, 60, 50, 50, 50]))
	var pog := int(game.line.get("pog", 0))
	if pog > 0:
		panel.add(FcStatLine.make("Player of the game", ctx.player_name(pog)))
	return panel


static func _news_of_the_day(ctx: FcOwnerContext, season: FcSeason, game: FcScheduledGame) -> Array:
	var iso := season.date_of_day(game.day).to_iso()
	var out: Array = []
	for item in ctx.world().news:
		if str(item["date"]) == iso and (int(item.get("team", 0)) == game.home_id or int(item.get("team", 0)) == game.away_id):
			out.append(item)
	return out
