class_name FcOwnerHistory
extends RefCounted
## The Owner History tab (Phase 3): the franchise's story and the league's. Pages: Franchise (records, season log, all-time leaders),
## Retired numbers, Rivalries, Storylines, and the existing Hall of Fame and records page (handed in by the app). Every number comes from
## FcFranchiseHistory, FcRivalries and FcStorylines, which read the history the world keeps forever; nothing is stored.
##
## The dashboard builds every tab each time it refreshes, so the Franchise and Records pages are built at once (cheap) and the others only
## when their sub-tab is opened (each reads the whole history once). A team picker on the franchise pages lets the owner read any club.

const PAGE_NAMES := ["Franchise", "Retired numbers", "Rivalries", "Storylines", "Hall of Fame and records"]

const KIND_NAMES := {"dynasty": "Dynasty", "drought": "Title at last", "worst_to_first": "Worst to first", "cinderella": "Cinderella",
	"collapse": "Collapse", "mvp": "MVP", "record": "Record", "legend": "Legend", "jersey": "Retired number", "rivalry": "Rivalry"}


## `records_page` builds the old Hall of Fame and records page (the app keeps that code).
static func build(ctx: FcOwnerContext, records_page: Callable) -> Control:
	var pages := FcTabPages.new()
	pages.name = "HistoryPages"
	var franchise := _picker_page(ctx, "franchise", _franchise)
	pages.add_page(franchise, PAGE_NAMES[0])
	var lazy: Array = []
	for entry in [["jerseys", _retired], ["rivalries", _rivalries]]:
		var page := _picker_page(ctx, str(entry[0]), entry[1], false)
		pages.add_page(page, PAGE_NAMES[1 + lazy.size()])
		lazy.append(page)
	var story := _storylines_page(ctx, false)
	pages.add_page(story, PAGE_NAMES[3])
	lazy.append(story)
	pages.add_page(records_page.call(), PAGE_NAMES[4])
	pages.tab_changed.connect(func(index: int) -> void:
		if index >= 1 and index <= 3:
			var target: Control = lazy[index - 1]
			if target.has_meta("fill"):
				(target.get_meta("fill") as Callable).call())
	return pages


## The team the owner is looking at by default: his own, or the first club when there is none (spectating).
static func default_team(ctx: FcOwnerContext) -> int:
	var id := ctx.user_team_id()
	if ctx.world().teams.has_id(id):
		return id
	var ids := ctx.world().teams.ids()
	return ids[0] if not ids.is_empty() else 0


# --- shared page shape -----------------------------------------------------------------------------------------------------------

## A page with a team picker above a body that is rebuilt for the chosen team. `eager` false waits for the page's "fill" call.
static func _picker_page(ctx: FcOwnerContext, key: String, body_builder: Callable, eager: bool = true) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var fill := func() -> void:
		if page.get_child_count() > 0:
			return
		var team_ids := ctx.world().teams.ids()
		var items: Array = []
		for id in team_ids:
			items.append([ctx.team_name(id), id])
		var picker := FcDropdown.make(items, default_team(ctx))
		picker.name = "TeamPicker"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		row.add_child(FcUiTables.label("Club", FcUiTokens.TYPE_SMALL))
		row.add_child(picker)
		page.add_child(row)
		var body := VBoxContainer.new()
		body.name = "Body"
		page.add_child(body)
		var show := func(team_id: int) -> void:
			for c in body.get_children():
				body.remove_child(c)
				c.queue_free()
			body.add_child(body_builder.call(ctx, team_id))
		picker.chosen.connect(func(value) -> void:
			show.call(int(value))
			FcTabPages.wrap_long_labels(page))
		show.call(default_team(ctx))
		FcTabPages.wrap_long_labels(page)   # the tab wrapped the page when it was added, before this was filled
	if eager:
		fill.call()
	else:
		page.set_meta("fill", fill)
	return page


static func _history(ctx: FcOwnerContext) -> FcFranchiseHistory:
	return FcFranchiseHistory.new(ctx.world(), ctx.controller.league_id)


static func _name(ctx: FcOwnerContext, player_id: int) -> String:
	return ctx.world().player_name(player_id)


static func _season_text(year: int) -> String:
	return "%d-%02d" % [year, (year + 1) % 100]


# --- Franchise ----------------------------------------------------------------------------------------------------------------------

static func _franchise(ctx: FcOwnerContext, team_id: int) -> Control:
	var history := _history(ctx)
	var s := history.summary(team_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	if int(s["seasons"]) == 0:
		box.add_child(_muted("No finished seasons yet. The franchise's history fills in as seasons are completed."))
		return box
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	tiles.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	tiles.add_child(FcStatTile.make("Seasons", str(s["seasons"]), "%d-%d all-time" % [s["wins"], s["losses"]]))
	tiles.add_child(FcStatTile.make("Titles", str(s["titles"]), ", ".join((s["title_years"] as Array).map(func(y): return str(y))) if s["titles"] > 0 else "none yet"))
	tiles.add_child(FcStatTile.make("Finals", str(s["finals"]), "%d playoff trips" % s["playoffs"]))
	tiles.add_child(FcStatTile.make("Best season", "%d-%d" % [s["best"]["wins"], s["best"]["losses"]], _season_text(int(s["best"]["year"]))))
	tiles.add_child(FcStatTile.make("Worst season", "%d-%d" % [s["worst"]["wins"], s["worst"]["losses"]], _season_text(int(s["worst"]["year"]))))
	var drought := "reigning champions" if int(s["drought"]) == 0 and s["titles"] > 0 else ("%d seasons since a title" % s["drought"] if s["titles"] > 0 else "%d seasons, no title" % s["drought"])
	tiles.add_child(FcStatTile.make("Playoff run", "%d in a row" % s["playoff_streak"], drought))
	box.add_child(tiles)
	var columns := HFlowContainer.new()
	columns.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	columns.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	var left := VBoxContainer.new()
	left.add_child(FcUiTables.label("Season by season", FcUiTokens.TYPE_H3, true))
	var rows: Array = []
	var log := history.season_log(team_id)
	for i in range(log.size() - 1, -1, -1):
		var row: Dictionary = log[i]
		rows.append([_season_text(int(row["year"])), "%d-%d" % [row["wins"], row["losses"]], "%d of %d" % [row["rank"], row["teams"]], row["result"]])
	var table := FcTable.from_strings(["Season", "Record", "Rank", "Result"], rows, [90, 80, 80, 0])
	table.custom_minimum_size = Vector2(480, 260)
	left.add_child(table)
	columns.add_child(left)
	var right := VBoxContainer.new()
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		right.add_child(FcUiTables.label("All-time %s leaders" % entry[1].to_lower(), FcUiTokens.TYPE_H3, true))
		var leader_rows: Array = []
		for l in history.leaders(team_id, entry[0], 5):
			leader_rows.append([_name(ctx, int(l[1])), str(l[0]), str(l[2])])
		var leader_table := FcTable.from_strings(["Player", entry[1], "Seasons"], leader_rows, [0, 90, 90])
		leader_table.custom_minimum_size = Vector2(380, 210)
		right.add_child(leader_table)
	columns.add_child(right)
	box.add_child(columns)
	return box


# --- Retired numbers ----------------------------------------------------------------------------------------------------------------

static func _retired(ctx: FcOwnerContext, team_id: int) -> Control:
	var history := _history(ctx)
	var honoured := history.retired_numbers(team_id, ctx.controller.state.current_season)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	box.add_child(_muted("A club retires the number of a player who retired after at least %d seasons with it and a career worth %d points on the Hall of Fame score (induction needs %d). It happens the season after his last. Numbers are a stable display choice: league players have no shirt number in the data." % [FcFranchiseHistory.MIN_SEASONS, int(FcFranchiseHistory.NUMBER_SCORE), int(FcRecords.INDUCTION_SCORE)]))
	if honoured.is_empty():
		box.add_child(_muted("No numbers retired yet."))
		return box
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	flow.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	for h in honoured:
		var card := FcPanel.new("", FcPanel.Variant.RAISED)
		card.name = "Jersey_%d" % int(h["number"])
		card.custom_minimum_size.x = 170
		var number := FcUiTables.label("#%d" % int(h["number"]), FcUiTokens.TYPE_DISPLAY, true)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.body.add_child(number)
		var who := FcUiTables.label(_name(ctx, int(h["player_id"])), FcUiTokens.TYPE_BODY, true)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		who.custom_minimum_size.x = 140
		card.body.add_child(who)
		var years := FcUiTables.label("%d to %d, %d seasons" % [h["first"], h["last"], h["seasons"]], FcUiTokens.TYPE_SMALL)
		years.theme_type_variation = "MutedLabel"
		years.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.body.add_child(years)
		var ceremony := FcUiTables.label("Retired in %s" % _season_text(int(h["ceremony"])), FcUiTokens.TYPE_SMALL)
		ceremony.theme_type_variation = "MutedLabel"
		ceremony.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.body.add_child(ceremony)
		flow.add_child(card)
	box.add_child(flow)
	return box


# --- Rivalries ------------------------------------------------------------------------------------------------------------------------

static func _rivalries(ctx: FcOwnerContext, team_id: int) -> Control:
	var rivalries := FcRivalries.new(ctx.world(), ctx.controller.league_id)
	var list := rivalries.of_team(team_id, 6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	box.add_child(_muted("Teams become rivals by meeting in the playoffs: every series counts, game sevens and finals count more, and so does sharing a division. Budding from %d points, heated from %d, bitter from %d." % [FcRivalries.BUDDING, FcRivalries.HEATED, FcRivalries.BITTER]))
	if list.is_empty():
		box.add_child(_muted("No rivalries yet."))
		return box
	for r in list:
		var other: int = int(r["b"]) if int(r["a"]) == team_id else int(r["a"])
		var panel := FcPanel.new("", FcPanel.Variant.SURFACE)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
		var chip := FcTeamChip.new().setup(ctx.team_look(other), ctx.team_name(other), 28, false)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(chip)
		var tone := FcStatusChip.Tone.INFO
		if r["level"] == "Heated":
			tone = FcStatusChip.Tone.WARNING
		elif r["level"] == "Bitter":
			tone = FcStatusChip.Tone.DANGER
		head.add_child(FcStatusChip.make(str(r["level"]), tone))
		panel.body.add_child(head)
		var mine_wins: int = int(r["wins_a"]) if int(r["a"]) == team_id else int(r["wins_b"])
		var their_wins: int = int(r["wins_b"]) if int(r["a"]) == team_id else int(r["wins_a"])
		var facts := _muted("Series %d-%d in %d playoff meeting%s (%d to the deciding game, %d in the final). Last met %s." % [mine_wins, their_wins, r["meetings"], "" if int(r["meetings"]) == 1 else "s", r["close"], r["finals"], _season_text(int(r["last_year"]))])
		panel.body.add_child(facts)
		var steps: Array = []
		var scores: Array = []
		var labels: Array = []
		var previous := ""
		for d in rivalries.development(int(r["a"]), int(r["b"])):
			scores.append(int(d["score"]))
			labels.append(_season_text(int(d["year"])))
			if str(d["level"]) != previous:
				steps.append("%s: %s" % [_season_text(int(d["year"])), d["level"]])
				previous = str(d["level"])
		if scores.size() >= 2:
			var line := FcSparkline.new(scores, FcUiTokens.WARNING, labels)
			line.custom_minimum_size = Vector2(160, 36)
			panel.body.add_child(line)
		panel.body.add_child(_muted("How it grew: %s" % " > ".join(steps)))
		box.add_child(panel)
	return box


# --- Storylines ----------------------------------------------------------------------------------------------------------------------

static func _storylines_page(ctx: FcOwnerContext, eager: bool) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var fill := func() -> void:
		if page.get_child_count() > 0:
			return
		var stories := FcStorylines.new(ctx.world(), ctx.controller.league_id, ctx.controller.state.current_season)
		var scope := FcChoiceGroup.new()
		scope.name = "StoryScope"
		scope.set_options([["league", "Whole league"], ["team", "My club"]], "league")
		page.add_child(scope)
		var body := VBoxContainer.new()
		body.name = "Body"
		body.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		page.add_child(body)
		var show := func(which: String) -> void:
			for c in body.get_children():
				body.remove_child(c)
				c.queue_free()
			var items: Array[Dictionary] = stories.recent(14) if which == "league" else stories.for_team(default_team(ctx), 14)
			if items.is_empty():
				body.add_child(_muted("No storylines yet. They appear as seasons are completed: dynasties, droughts that end, upsets, record seasons, retirements and rivalries."))
			for item in items:
				body.add_child(_story_row(item))
		scope.selected.connect(func(id: String) -> void:
			show.call(id)
			FcTabPages.wrap_long_labels(page))
		show.call("league")
		FcTabPages.wrap_long_labels(page)
	if eager:
		fill.call()
	else:
		page.set_meta("fill", fill)
	return page


static func _story_row(item: Dictionary) -> Control:
	var row := FcPanel.new("", FcPanel.Variant.SURFACE)
	row.name = "Story_%s_%d" % [item["kind"], item["year"]]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	head.add_child(FcStatusChip.make(_season_text(int(item["year"])), FcStatusChip.Tone.NEUTRAL))
	head.add_child(FcStatusChip.make(str(KIND_NAMES.get(item["kind"], item["kind"])), FcStatusChip.Tone.INFO))
	row.body.add_child(head)
	var headline := FcUiTables.label(str(item["headline"]), FcUiTokens.TYPE_BODY, true)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.custom_minimum_size.x = 160
	row.body.add_child(headline)
	row.body.add_child(_muted(str(item["text"])))
	return row


static func _muted(text: String) -> Label:
	var l := FcUiTables.label(text, FcUiTokens.TYPE_SMALL)
	l.theme_type_variation = "MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 160
	return l
