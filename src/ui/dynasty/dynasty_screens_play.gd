class_name FcDynastyScreensPlay
extends RefCounted
## Playing games and seeing results, the challenge hub, the tournament bracket and the season screen.


# --- play ---------------------------------------------------------------------------------------------------------

static func build_play(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_child(ui.heading("Play"))
	if not ctl.last_game.is_empty():
		root.add_child(_result_panel(ui, ctl.last_game))
	var problems := ctl.lineup_problems()
	if not problems.is_empty():
		var l := FcDynastyUi.wl("Your lineup is not ready: %s" % problems[0])
		l.add_theme_color_override("font_color", FcUiTheme.BAD)
		root.add_child(l)
		root.add_child(FcDynastyUi.btn("Fix it in Lineup", func() -> void: ui.show_tab("lineup")))
	root.add_child(ui.note("Games are simulated by the Full Court basketball engine from your roster. Pick an opponent strength relative to your team overall (%d). Harder opponents pay more credits." % ctl.team_overall(), 640))
	var row := HFlowContainer.new()   # the opponent buttons wrap on a phone
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for lv in ctl.opponent_levels():
		var b := FcDynastyUi.btn("%s opponent (%d%% credits)" % [lv["name"], int(lv["reward_percent"])], func() -> void: _play(ui, str(lv["id"])))
		b.disabled = not problems.is_empty()
		row.add_child(b)
	root.add_child(row)
	root.add_child(ui.heading("Recent games"))
	var history: Array = ctl.profile().game_history
	if history.is_empty():
		root.add_child(ui.note("No games yet."))
	else:
		var rows: Array = []
		for i in range(history.size() - 1, -1, -1):
			var g: Dictionary = history[i]
			rows.append([g["n"], "W" if g["won"] else "L", "%d-%d" % [g["score_for"], g["score_against"]], g["opponent"], g["kind"].capitalize()])
		root.add_child(FcDataTable.build(["#", "Result", "Score", "Opponent", "Type"], rows, [50, 70, 100, 0, 110], {"min_height": 220}))
	return root


static func _play(ui: FcDynastyUi, level_id: String) -> void:
	var r := ui.ctl.play_quick_game(level_id)
	if not r.ok:
		ui.say(r.message)
		return
	ui.refresh()
	ui.say("Game complete. %s" % _after_text(r.data))


static func _after_text(data: Dictionary) -> String:
	var bits: Array[String] = []
	if int(data.get("reward", 0)) > 0:
		bits.append("+%d credits" % int(data["reward"]))
	for c in data.get("completed_challenges", []):
		bits.append("challenge complete: %s" % c)
	for o in data.get("completed_objectives", []):
		bits.append("season objective complete: %s" % o)
	return ", ".join(bits)


static func _result_panel(ui: FcDynastyUi, game: Dictionary) -> Control:
	if game.has("box"):
		return post_game(ui, game)
	return _summary_panel(ui, game)


## The shared post-game screen for a Dynasty game: the simulation's box score, the user's side, a face for every player (the same
## resolver as everywhere else) and what the game earned. Read-only: it changes nothing.
static func post_game(ui: FcDynastyUi, game: Dictionary) -> Control:
	var by_card := {}
	for row in FcCollectionQuery.rows(ui.ctl.profile(), ui.ctl.catalog, {}):
		by_card[str(row["card_id"])] = row
	var subjects := {}
	for pid in game["cards"]:
		var row: Dictionary = by_card.get(str(game["cards"][pid]), {})
		if not row.is_empty():
			subjects[int(pid)] = FcPlayerPresentation.subject_for_card(row)
	var rewards: Array = []
	var extra := _after_text(game)
	if extra != "":
		rewards.append(extra)
	var wins := 0
	var history: Array = ui.ctl.profile().game_history
	for g in history:
		if bool(g["won"]):
			wins += 1
	var implications: Array = ["Your Dynasty record: %d-%d over %d games." % [wins, history.size() - wins, history.size()]]
	var vm := FcPostGameModel.build(game["box"], {"user_side": int(game["user_side"]), "subjects": subjects, "implications": implications, "rewards": rewards})
	var screen := FcPostGameScreen.new().setup(vm)
	screen.name = "PostGame"
	return screen


static func _summary_panel(ui: FcDynastyUi, game: Dictionary) -> Control:
	var s: Dictionary = game["summary"]
	var v := VBoxContainer.new()
	var title := "%s  %d - %d  vs %s%s" % ["WIN" if s["won"] else "LOSS", s["score_for"], s["score_against"], s["opponent"], " (OT)" if int(s["overtimes"]) > 0 else ""]
	var t := FcDynastyUi.wl(title, 22, true)
	t.add_theme_color_override("font_color", FcUiTheme.GOOD if s["won"] else FcUiTheme.BAD)
	v.add_child(t)
	var extra := _after_text(game)
	if extra != "":
		v.add_child(FcDynastyUi.wl("Earned: %s" % extra, 14))
	var rows: Array = []
	var lines: Array = s["players"].duplicate()
	lines.sort_custom(func(a, b): return a["points"] > b["points"])
	for line in lines:
		rows.append([line["name"], "%d:%02d" % [int(line["seconds"]) / 60, int(line["seconds"]) % 60], line["points"], line["rebounds"], line["assists"], line["steals"], line["blocks"], line["threes"]])
	v.add_child(FcDataTable.build(["Player", "Min", "PTS", "REB", "AST", "STL", "BLK", "3PM"], rows, [0, 70, 55, 55, 55, 55, 55, 55], {"min_height": 260}))
	return ui.panel([v])


# --- challenges ---------------------------------------------------------------------------------------------------

static func build_challenges(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_child(ui.heading("Challenges"))
	root.add_child(ui.note("Progress comes only from real simulated games (and your collection for collection goals). Each reward can be claimed once.", 600))
	var listing := ctl.challenge_listing()
	if listing.is_empty():
		root.add_child(ui.note("The loaded release publishes no challenges yet."))
		return root
	var category := ""
	for c in listing:
		if c["category"] != category:
			category = c["category"]
			root.add_child(FcDynastyUi.wl(category.replace("_", " ").capitalize(), 17, true))
		var row := HFlowContainer.new()   # wraps on a phone: description, progress, then the claim button
		row.add_theme_constant_override("h_separation", 12)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(200, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(FcDynastyUi.wl(c["title"], 15))
		var detail := "%s  Reward: %s" % [c["description"], FcDynastyChallenges.rewards_text(c["rewards"])]
		var restr := FcDynastyChallenges.restrictions_text(c["restrictions"])
		if restr != "":
			detail += "  Roster: %s" % restr
		info.add_child(ui.note(detail, 380))
		row.add_child(info)
		var prog := VBoxContainer.new()
		prog.add_child(FcDynastyUi.wl("%d / %d" % [c["progress"], c["target"]], 13))
		prog.add_child(ui.progress_bar(c["progress"], c["target"]))
		row.add_child(prog)
		var claim := FcDynastyUi.btn("Claimed" if c["claimed"] else "Claim reward", func() -> void:
			var r := ctl.claim_challenge(str(c["id"]))
			ui.report(r, "Reward claimed: %s" % FcDynastyChallenges.rewards_text(c["rewards"]))
			ui.refresh())
		claim.disabled = not c["completed"] or c["claimed"]
		row.add_child(claim)
		root.add_child(row)
	return root


# --- tournament -----------------------------------------------------------------------------------------------------

static func build_tournament(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_child(ui.heading("Tournament"))
	var run := ctl.active_tournament()
	if run.is_empty():
		root.add_child(ui.note("Eight teams, single elimination: quarterfinals, semifinals, final. Every match is simulated with the same engine. Rewards depend on how far you go.", 640))
		var list := ctl.tournament_listing()
		if list.is_empty():
			root.add_child(ui.note("The loaded release's season has no tournament yet."))
		for t in list:
			var v := VBoxContainer.new()
			v.add_child(FcDynastyUi.wl(t["name"], 18, true))
			v.add_child(FcDynastyUi.wl("Entry: %s %s" % [FcDynastyStyle._n(t["fee_amount"]), t["fee_currency"]]))
			for place in FcDynastyContentRules.PLACEMENTS:
				if t["rewards"].has(place):
					v.add_child(FcDynastyUi.wl("%s: %s" % [place.capitalize(), FcDynastyChallenges.rewards_text(t["rewards"][place])], 13))
			var enter := FcDynastyUi.btn("Enter tournament", func() -> void:
				var r := ctl.enter_tournament(str(t["tournament_id"]))
				ui.report(r, "You are in. Good luck!")
				ui.refresh())
			enter.disabled = not ctl.lineup_problems().is_empty()
			v.add_child(enter)
			root.add_child(ui.panel([v]))
	else:
		root.add_child(FcDynastyUi.wl("%s: round %d of 3" % [run["name"], int(run["round"]) + 1], 18))
		root.add_child(_bracket(run))
		var play := FcDynastyUi.btn("Play next match (%s)" % FcDynastyTournament.ROUND_NAMES[int(run["round"])], func() -> void:
			var r := ctl.play_tournament_match()
			if not r.ok:
				ui.say(r.message)
				return
			ui.refresh()
			if r.data["finished"]:
				ui.say("Tournament over: you finished as %s. %s" % [str(r.data["run"]["placement"]), FcDynastyChallenges.rewards_text(r.data["rewards"])])
			else:
				ui.say("You won! On to the next round."))
		play.disabled = not ctl.lineup_problems().is_empty()
		root.add_child(play)
	if not ctl.last_game.is_empty() and not run.is_empty():
		root.add_child(_result_panel(ui, ctl.last_game))
	var hist := ctl.tournament_history()
	if not hist.is_empty():
		root.add_child(ui.heading("Past tournaments"))
		for h in hist:
			root.add_child(FcDynastyUi.wl("%s: %s (%s)" % [h["name"], str(h["placement"]).capitalize(), FcDynastyChallenges.rewards_text(h.get("rewards", {}))], 14))
	return root


static func _bracket(run: Dictionary) -> Control:
	var cols := HFlowContainer.new()   # the rounds sit side by side on a wide screen and stack on a phone
	cols.add_theme_constant_override("h_separation", 24)
	cols.add_theme_constant_override("v_separation", 12)
	for round_view in FcDynastyTournament.bracket_view(run):
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.add_child(FcDynastyUi.wl(round_view["round_name"], 16, true))
		for m in round_view["matches"]:
			var p := PanelContainer.new()
			if m["you"]:
				p.add_theme_stylebox_override("panel", FcDynastyStyle.box(FcUiTheme.ACCENT_SOFT, FcUiTheme.ACCENT, 2, 8, 6))
			var inner := VBoxContainer.new()
			var a := FcDynastyUi.wl(str(m["a"]), 14)
			var b := FcDynastyUi.wl(str(m["b"]), 14)
			if m["played"]:
				(a if m["winner"] == m["a"] else b).add_theme_color_override("font_color", FcUiTheme.GOOD)
			inner.add_child(a)
			inner.add_child(b)
			inner.add_child(FcDynastyUi.wl(str(m["score"]), 12))
			p.add_child(inner)
			v.add_child(p)
		cols.add_child(v)
	return cols


# --- season -------------------------------------------------------------------------------------------------------------

static func build_season(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	var s := ctl.season_overview()
	if s.is_empty():
		root.add_child(ui.heading("Season"))
		root.add_child(ui.note("The loaded release has no season yet."))
		return root
	root.add_child(ui.heading("Season: %s" % s["name"]))
	if str(s["description"]) != "":
		root.add_child(ui.note(str(s["description"]), 600))
	root.add_child(FcDynastyUi.wl("%d season points" % s["points"], 18))
	root.add_child(ui.progress_bar(s["points"], maxi(1, s["top_milestone"])))
	root.add_child(ui.note("Season points come from seasonal challenges and season objectives. A season never removes cards from your collection.", 600))
	root.add_child(ui.heading("Milestones"))
	for m in s["milestones"]:
		var row := HBoxContainer.new()
		var l := FcDynastyUi.wl("%d pts   %s   %s" % [m["points"], m["name"], FcDynastyChallenges.rewards_text(m["rewards"])], 14)
		l.custom_minimum_size = Vector2(160, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := FcDynastyUi.btn("Claimed" if m["claimed"] else "Claim", func() -> void:
			var r := ctl.claim_milestone(str(m["id"]))
			ui.report(r, "Milestone reward claimed.")
			ui.refresh())
		b.disabled = not m["reached"] or m["claimed"]
		row.add_child(b)
		root.add_child(row)
	root.add_child(ui.heading("Season objectives"))
	if s["objectives"].is_empty():
		root.add_child(ui.note("None this season."))
	for o in s["objectives"]:
		var line := HBoxContainer.new()
		var l2 := FcDynastyUi.wl("%s  (+%d pts)%s" % [o["title"], o["points"], "  done" if o["done"] else ""], 14)
		l2.custom_minimum_size = Vector2(160, 0)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l2)
		line.add_child(ui.progress_bar(o["progress"], o["target"]))
		root.add_child(line)
	root.add_child(ui.heading("Seasonal challenges"))
	var any := false
	for c in ctl.challenge_listing():
		if s["challenge_ids"].has(c["id"]):
			any = true
			root.add_child(FcDynastyUi.wl("%s   %d/%d   (+%d pts)%s" % [c["title"], c["progress"], c["target"], c["season_points"], "  done" if c["completed"] else ""], 14))
	if not any:
		root.add_child(ui.note("None this season."))
	if not s["tournament_ids"].is_empty():
		root.add_child(FcDynastyUi.btn("Go to the season tournament", func() -> void: ui.show_tab("tournament")))
	return root
