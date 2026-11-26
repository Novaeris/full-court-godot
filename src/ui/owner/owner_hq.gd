class_name FcOwnerHq
extends RefCounted
## The franchise headquarters (D-077 M3): the top of the Owner Overview, composed as a front office rather than a stack of panels.
##   Hero row:    the featured matchup (the next game as two teams facing each other; click to open the game) beside the team's standing
##                (record, ranks, games left, the last ten results as letters, the playoff position if the season ended today).
##   Spotlight:   team leaders with portraits, the last game with its player of the game, and the team's league ranks.
##   The office:  the latest headlines, the owner's objectives for the season with progress, and the business (payroll against the cap,
##                cash, debt, last season's profit, coach, general manager, staff chemistry).
## Every number comes from FcFranchiseSnapshot (the live game); nothing is invented, and a section with nothing real to show says so.

const NEWS_COUNT := 4


static func build(ctx: FcOwnerContext) -> Control:
	var snap := FcFranchiseSnapshot.build(ctx.controller)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	box.add_child(_hero_row(ctx, snap))
	box.add_child(_spotlight_row(ctx, snap))
	box.add_child(_office_row(ctx, snap))
	return box


static func _row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	return row


static func _panel(title: String, min_width: float, ratio: float = 1.0) -> FcPanel:
	var p := FcPanel.new(title, FcPanel.Variant.SURFACE)
	p.custom_minimum_size.x = min_width
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	return p


static func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "CaptionLabel"
	return l


## A muted line. `wrap` only for labels in a VBox: a wrapping label inside a flow container has no width to wrap to and collapses.
static func _muted(text: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MutedLabel"
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# --- hero: featured matchup and standing --------------------------------------------------------------------------------

static func _hero_row(ctx: FcOwnerContext, snap: Dictionary) -> Control:
	var row := _row()
	var c := ctx.controller
	var next := c.next_user_game()
	var game_panel := _panel("Next game", 460, 1.6)
	if next != null:
		var season := c.season()
		var user := ctx.user_team_id()
		var home := next.home_id == user
		var opponent := next.away_id if home else next.home_id
		var standings := c.standings()
		var banner := FcMatchupBanner.new().setup({
			"away": _side(ctx, next.away_id, standings), "home": _side(ctx, next.home_id, standings), "center": "AT",
			"caption": season.date_of_day(next.day).to_iso()})
		banner.custom_minimum_size = Vector2(420, 168)
		banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner.name = "FeaturedMatchup"
		banner.activated.connect(func() -> void:
			if ctx.open_game.is_valid():
				ctx.open_game.call(next.id))
		game_panel.add(banner)
		var facts := HFlowContainer.new()
		facts.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
		facts.add_child(_muted("Next game: %s %s on %s" % ["vs" if home else "at", ctx.team_name(opponent), season.date_of_day(next.day).to_iso()], false))
		var h2h: Array = standings.records[user]["h2h"].get(opponent, [0, 0])
		facts.add_child(_muted("Season series %d-%d" % [int(h2h[0]), int(h2h[1])], false))
		var out_mine := _injured_count(ctx, user)
		var out_theirs := _injured_count(ctx, opponent)
		facts.add_child(_muted("Injured: you %d, them %d" % [out_mine, out_theirs], false))
		game_panel.add(facts)
		var open := FcButton.make("Preview the game", FcButton.Variant.SECONDARY, func() -> void:
			if ctx.open_game.is_valid():
				ctx.open_game.call(next.id))
		open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		game_panel.add(open)
	else:
		game_panel.add(_muted("No regular-season game left on the schedule."))
	row.add_child(game_panel)
	row.add_child(_standing_panel(ctx, snap))
	return row


static func _side(ctx: FcOwnerContext, team_id: int, standings: FcStandings) -> Dictionary:
	var r: Dictionary = standings.records.get(team_id, {"w": 0, "l": 0})
	return {"look": ctx.team_look(team_id), "name": ctx.team_name(team_id), "record": "%d-%d" % [int(r["w"]), int(r["l"])]}


static func _injured_count(ctx: FcOwnerContext, team_id: int) -> int:
	var n := 0
	for pid in ctx.world().teams.get_by_id(team_id).roster.player_ids:
		var p: FcPlayer = ctx.world().players.get_by_id(pid)
		if p != null and p.games_out > 0:
			n += 1
	return n


static func _standing_panel(ctx: FcOwnerContext, snap: Dictionary) -> Control:
	var panel := _panel("Standing", 340, 1.0)
	var record: Dictionary = snap["record"]
	var kpis := FcKpiStrip.new()
	var items: Array = [{"label": "Record", "value": "%d-%d" % [record["wins"], record["losses"]], "delta": str(record["streak"])},
		{"label": "League rank", "value": str(record["rank"])}]
	if snap.has("conference"):
		items.append({"label": "Conference", "value": "%d of %d" % [snap["conference"]["rank"], snap["conference"]["size"]]})
	items.append({"label": "Games left", "value": str(record["games_left"])})
	kpis.set_items(items)
	panel.add(kpis)
	var form: Array = snap["form"]
	var form_row := HBoxContainer.new()
	form_row.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	form_row.add_child(_caption("LAST %d" % form.size() if not form.is_empty() else "NO GAMES YET"))
	for won in form:
		form_row.add_child(FcResultBadge.new(FcResultBadge.Kind.WIN if won else FcResultBadge.Kind.LOSS))
	panel.add(form_row)
	var po: Dictionary = snap["playoff"]
	var po_text := "No games played yet."
	if int(record["wins"]) + int(record["losses"]) > 0:
		var gap := float(po["games_back"])
		if bool(po.get("qualifies", false)):
			po_text = "Playoff position: in, seed %d (%s)" % [int(po["seed"]), "level with the first team out" if gap <= 0.0 else "%s clear of the first team out" % _games(gap)]
		else:
			po_text = "Playoff position: out, %s" % ("level with the last team in, behind on the tie-break" if gap <= 0.0 else "%s behind the last team in" % _games(gap))
	var po_label := Label.new()
	po_label.text = po_text
	po_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	po_label.add_theme_color_override("font_color", FcUiTokens.SUCCESS if bool(po.get("qualifies", false)) else FcUiTokens.TEXT_MUTED)
	panel.add(po_label)
	return panel


# --- spotlight: leaders, last game, ranks --------------------------------------------------------------------------------

static func _spotlight_row(ctx: FcOwnerContext, snap: Dictionary) -> Control:
	var row := _row()
	var leaders_panel := _panel("Team leaders", 340, 1.2)
	var leaders: Array = snap["leaders"]
	if leaders.is_empty():
		leaders_panel.add(_muted("Leaders appear once the season has started."))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	for l in leaders:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_caption(str(l["label"]).to_upper()))
		var chip := FcPlayerChip.new()
		chip.setup({"subject": FcPlayerPresentation.subject_for_player(ctx.world(), int(l["player"])), "name": ctx.player_name(int(l["player"])), "overall": 0}, "", false, 40, true)
		col.add_child(chip)
		var value := Label.new()
		value.text = "%.1f a game" % float(l["value"])
		value.theme_type_variation = "NumericLabel"
		col.add_child(value)
		cards.add_child(col)
	leaders_panel.add(cards)
	row.add_child(leaders_panel)
	var last_panel := _panel("Last game", 280, 0.9)
	var last: Dictionary = snap.get("last_game", {})
	if last.is_empty():
		last_panel.add(_muted("No game played yet."))
	else:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		line.add_child(FcResultBadge.new(FcResultBadge.Kind.WIN if last["won"] else FcResultBadge.Kind.LOSS, str(last["score"])))
		line.add_child(ctx.team_chip(int(last["opponent"]), 24, ("vs " if last["home"] else "at ") + ctx.team_name(int(last["opponent"]))))
		last_panel.add(line)
		if last.has("pog"):
			last_panel.add(_caption("PLAYER OF THE GAME"))
			var pog := FcPlayerChip.new()
			pog.setup({"subject": FcPlayerPresentation.subject_for_player(ctx.world(), int(last["pog"])), "name": ctx.player_name(int(last["pog"])), "overall": 0}, str(last.get("pog_line", "")), false, 40, false)
			last_panel.add(pog)
	row.add_child(last_panel)
	var ranks_panel := _panel("League ranks", 260, 0.8)
	var ranks: Dictionary = snap["ranks"]
	for spec in [["offense", "Points scored", "%.1f a game"], ["defense", "Points allowed", "%.1f a game"], ["net", "Margin", "%+.1f a game"]]:
		var r: Dictionary = ranks[spec[0]]
		var rank_row := HBoxContainer.new()
		var name := Label.new()
		name.text = spec[1]
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rank_row.add_child(name)
		var value := Label.new()
		value.text = (spec[2] % float(r["value"])) + "   #%d of %d" % [int(r["rank"]), int(r["of"])]
		value.theme_type_variation = "NumericLabel"
		rank_row.add_child(value)
		ranks_panel.add(rank_row)
	row.add_child(ranks_panel)
	return row


# --- the office: headlines, objectives, business ------------------------------------------------------------------------

static func _office_row(ctx: FcOwnerContext, snap: Dictionary) -> Control:
	var row := _row()
	var news_panel := _panel("Latest news", 380, 1.4)
	var news: Array = ctx.world().news
	if news.is_empty():
		news_panel.add(_muted("No news yet."))
	for i in range(news.size() - 1, maxi(-1, news.size() - 1 - NEWS_COUNT), -1):
		var item: Dictionary = news[i]
		var team_id := int(item.get("team", 0))
		var card := FcNewsCard.new().setup({"headline": str(item["text"]), "kind": FcOwnerHq.kind_label(str(item["kind"])), "date": str(item["date"]),
			"tier": FcNewsCard.TIER_NORMAL if team_id == ctx.user_team_id() or str(item["kind"]) == "champion" else FcNewsCard.TIER_BRIEF,
			"team_look": ctx.team_look(team_id) if team_id > 0 else {}})
		news_panel.add(card)
	row.add_child(news_panel)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 340
	right.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var goals := _panel("Owner objectives", 340)
	var objectives: Array = snap["objectives"]
	if objectives.is_empty():
		goals.add(_muted("Objectives are set when a season starts (Owner Mode)."))
	for o in objectives:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		var tone := FcStatusChip.Tone.INFO
		match str(o["status"]):
			FcOwnerObjectives.STATUS_MET: tone = FcStatusChip.Tone.SUCCESS
			FcOwnerObjectives.STATUS_MISSED: tone = FcStatusChip.Tone.DANGER
		line.add_child(FcStatusChip.make(str(o["status"]).to_upper(), tone))
		var text := Label.new()
		text.text = str(o["text"])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(text)
		goals.add(line)
		if str(o.get("progress", "")) != "":
			goals.add(_caption(str(o["progress"])))
	right.add_child(goals)
	right.add_child(_business_panel(ctx, snap))
	row.add_child(right)
	return row


static func _business_panel(ctx: FcOwnerContext, snap: Dictionary) -> Control:
	var panel := _panel("Business", 340)
	var m: Dictionary = snap["money"]
	var payroll_row := HBoxContainer.new()
	var payroll := Label.new()
	payroll.text = "Payroll %s of a %s cap" % [FcUiTables.money(int(m["payroll"])), FcUiTables.money(int(m["cap"]))]
	payroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	payroll_row.add_child(payroll)
	panel.add(payroll_row)
	var over_tax := int(m["payroll"]) > int(m["tax_line"])
	var meter := FcProgress.new(FcProgress.Variant.DANGER if over_tax else FcProgress.Variant.SUCCESS)
	meter.set_progress(float(m["payroll"]), float(maxi(1, int(m["tax_line"]))))
	meter.tooltip_text = "Payroll %s; tax line %s" % [FcUiTables.money(int(m["payroll"])), FcUiTables.money(int(m["tax_line"]))]
	panel.add(meter)
	var kpis := FcKpiStrip.new()
	var items: Array = [{"label": "Cash", "value": FcUiTables.money(int(m["cash"]))}, {"label": "Debt", "value": FcUiTables.money(int(m["debt"]))}]
	if bool(m["has_books"]):
		items.append({"label": "Last profit", "value": FcUiTables.money(int(m["last_profit"]))})
	kpis.set_items(items)
	panel.add(kpis)
	var staff: Dictionary = snap["staff"]
	var people: Array = []
	if str(staff["coach"]) != "":
		people.append("Coach %s" % staff["coach"])
	if str(staff["gm"]) != "":
		people.append("GM %s" % staff["gm"])
	if int(staff["chemistry"]) >= 0:
		people.append("staff chemistry %d" % int(staff["chemistry"]))
	if not people.is_empty():
		panel.add(_caption("  ·  ".join(people)))
	return panel


## The words shown for a news kind.
static func kind_label(kind: String) -> String:
	return {"injury": "Injury", "milestone": "Milestone", "champion": "Champions", "award": "Award", "signing": "Transaction", "retirement": "Retirement",
		"draft": "Draft", "staff": "Front office"}.get(kind, "News")


static func _games(n: float) -> String:
	return ("%d game%s" % [int(n), "" if int(n) == 1 else "s"]) if is_equal_approx(n, roundf(n)) else "%.1f games" % n
