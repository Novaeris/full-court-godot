class_name FcApp
extends Control
## The game's screens: main menu, new league, team choice, and the dashboard
## (overview, standings, schedule, roster, finances, staff, league). Everything
## goes through FcGameController; no game rules live here.
## The screens are built in code. Public methods (show_*, on_*, build_tab) let
## automated tests drive the same paths a player's clicks do.

const AREA_CHOICES := [
	["North America", ["north_america"]], ["Europe", ["europe"]], ["South America", ["south_america"]],
	["Asia", ["asia"]], ["Middle East", ["middle_east"]], ["Oceania", ["oceania"]], ["Africa", ["africa"]],
	["North America + Europe", ["north_america", "europe"]], ["Anywhere in the world", []],
]
const CAP_CHOICES := [["Soft cap with hard limit (recommended)", "soft_cap_with_hard_limit"], ["Hard cap", "hard_cap"], ["No cap (luxury tax only)", "no_cap"]]
const ERA_CHOICES := [["Mid 2010s (default)", "mid_2010s"], ["Early 2010s: slower, mid-range", "early_2010s"], ["Late 2010s: fast, three-point heavy", "late_2010s"]]
const TAB_NAMES := ["Overview", "Standings", "Schedule", "Roster", "Finances", "Staff", "News", "League"]

var controller: FcGameController
var saves := FcSaveManager.new()

var _defs := FcDefinitionSet.load_default()
var _data := FcGenerationData.load_default()
var _root: VBoxContainer
var _content: Control
var _pending_state: FcGameState
var _tabs: TabContainer
var _last_tab := 0
var _form := {}
var _message: Label


func _ready() -> void:
	setup()


## Builds the window frame and shows the main menu. Called automatically when the
## node enters the scene; safe to call again (tests call it directly because
## nodes added during a test run may not receive _ready yet).
func setup() -> void:
	if _root != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	theme = Theme.new()
	theme.default_font_size = 15
	show_main_menu()


func _reset(title: String) -> VBoxContainer:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_root.add_child(FcUiTables.label(title, 28, true))
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_content = box
	_message = FcUiTables.label("")
	_root.add_child(_message)
	return box


func _say(text: String) -> void:
	if _message != null:
		_message.text = text


# --- main menu -----------------------------------------------------------------

func show_main_menu() -> void:
	var box := _reset("FULL COURT")
	box.add_child(FcUiTables.label("Basketball management simulation", 16))
	box.add_child(FcUiTables.button("New Game", show_new_league))
	var slots := saves.list_slots()
	if not slots.is_empty():
		box.add_child(FcUiTables.button("Continue (latest save)", on_continue))
		box.add_child(FcUiTables.label("Saved games", 18, true))
		var rows: Array = []
		for m in slots:
			rows.append([m.slot_id, m.label, m.team_name, "%d-%02d" % [m.season, (m.season + 1) % 100], m.mode, m.saved_at, "ok" if m.readable else "damaged"])
		box.add_child(FcUiTables.table(["Slot", "Name", "Team", "Season", "Mode", "Saved", ""], rows))
		var row := HBoxContainer.new()
		var picker := OptionButton.new()
		for m in slots:
			picker.add_item(m.slot_id)
		_form["slot"] = picker
		row.add_child(picker)
		row.add_child(FcUiTables.button("Load", on_load_selected))
		row.add_child(FcUiTables.button("Delete", on_delete_selected))
		box.add_child(row)
	box.add_child(FcUiTables.button("Quit", func(): get_tree().quit()))


func on_continue() -> void:
	var slots := saves.list_slots()
	if not slots.is_empty():
		_load_slot(slots[0].slot_id)


func on_load_selected() -> void:
	var picker: OptionButton = _form.get("slot")
	if picker != null and picker.item_count > 0:
		_load_slot(picker.get_item_text(picker.selected))


func on_delete_selected() -> void:
	var picker: OptionButton = _form.get("slot")
	if picker != null and picker.item_count > 0:
		saves.delete_slot(picker.get_item_text(picker.selected))
		show_main_menu()


func _load_slot(slot_id: String) -> void:
	var result := saves.load_slot(slot_id, _defs)
	if not result.is_ok():
		_say("Could not load: " + result.message)
		return
	controller = FcGameController.resume(result.state)
	show_dashboard()
	if result.recovered_from != "":
		_say("The save was damaged; an older copy (%s) was loaded." % result.recovered_from)


# --- new league -------------------------------------------------------------------

func show_new_league() -> void:
	var box := _reset("New League")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	_form["name"] = _line_edit(grid, "League name", "Full Court League")
	_form["areas"] = _options(grid, "Where the teams are from", AREA_CHOICES.map(func(a): return a[0]))
	var counts := FcLeagueStructure.valid_team_counts()
	var counts_text: Array = counts.map(func(c): return "%d teams" % c)
	_form["teams"] = _options(grid, "Number of teams", counts_text)
	_form["teams"].selected = counts.find(30)
	_form["structure"] = _options(grid, "Conferences and divisions", [])
	_form["cap"] = _options(grid, "Salary cap", CAP_CHOICES.map(func(a): return a[0]))
	_form["era"] = _options(grid, "Style of play", ERA_CHOICES.map(func(a): return a[0]))
	_form["mode"] = _options(grid, "Game mode", ["Owner Mode", "Dynasty Mode"])
	_form["seed"] = _line_edit(grid, "Random seed (same seed = same league)", str(randi() % 100000))
	(_form["teams"] as OptionButton).item_selected.connect(func(_i): _fill_structures())
	_fill_structures()
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Create League", on_create_league))
	row.add_child(FcUiTables.button("Back", show_main_menu))
	box.add_child(row)


func _line_edit(grid: GridContainer, title: String, value: String) -> LineEdit:
	grid.add_child(FcUiTables.label(title))
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(320, 0)
	grid.add_child(e)
	return e


func _options(grid: GridContainer, title: String, items: Array) -> OptionButton:
	grid.add_child(FcUiTables.label(title))
	var o := OptionButton.new()
	for i in items:
		o.add_item(str(i))
	grid.add_child(o)
	return o


func _fill_structures() -> void:
	var counts := FcLeagueStructure.valid_team_counts()
	var teams := counts[(_form["teams"] as OptionButton).selected]
	var o: OptionButton = _form["structure"]
	o.clear()
	for s in FcLeagueStructure.valid_structures(teams):
		o.add_item("%d conference%s x %d division%s of %d teams" % [
			s["conferences"], "" if s["conferences"] == 1 else "s",
			s["divisions_per_conference"], "" if s["divisions_per_conference"] == 1 else "s", s["teams_per_division"]])
		o.set_item_metadata(o.item_count - 1, s)
	o.selected = 0


## Builds the league from the form (or from `overrides`, used by tests) and moves to team choice.
func on_create_league(overrides: Dictionary = {}) -> bool:
	var cfg := FcGenerationConfig.load_default(_data)
	var counts := FcLeagueStructure.valid_team_counts()
	cfg.league_name = (_form["name"] as LineEdit).text if overrides.is_empty() else str(overrides.get("name", cfg.league_name))
	if overrides.is_empty():
		cfg.areas = _to_strings(AREA_CHOICES[(_form["areas"] as OptionButton).selected][1])
		cfg.team_count = counts[(_form["teams"] as OptionButton).selected]
		var structure: Dictionary = (_form["structure"] as OptionButton).get_item_metadata((_form["structure"] as OptionButton).selected)
		cfg.conference_count = structure["conferences"]
		cfg.divisions_per_conference = structure["divisions_per_conference"]
		cfg.cap_preset = CAP_CHOICES[(_form["cap"] as OptionButton).selected][1]
		cfg.sim_era = ERA_CHOICES[(_form["era"] as OptionButton).selected][1]
	else:
		cfg.areas = _to_strings(overrides.get("areas", cfg.areas))
		cfg.team_count = int(overrides.get("teams", cfg.team_count))
		cfg.conference_count = int(overrides.get("conferences", cfg.conference_count))
		cfg.divisions_per_conference = int(overrides.get("divisions", cfg.divisions_per_conference))
		cfg.free_agent_count = int(overrides.get("free_agents", cfg.free_agent_count))
	var generator := FcWorldGenerator.new(_data, _defs, cfg)
	var problems := generator.validate()
	if not problems.is_empty():
		_say("Cannot create this league: " + "; ".join(problems))
		return false
	var seed_text := (_form["seed"] as LineEdit).text if overrides.is_empty() else str(overrides.get("seed", "1"))
	var seed_value := int(seed_text) if seed_text.is_valid_int() else hash(seed_text)
	var mode := FcGameState.MODE_OWNER
	if overrides.is_empty() and (_form["mode"] as OptionButton).selected == 1:
		mode = FcGameState.MODE_DYNASTY
	elif not overrides.is_empty():
		mode = str(overrides.get("mode", mode))
	_pending_state = generator.new_game_state(seed_value, mode, 0)
	show_team_choice()
	return true


func _to_strings(source) -> Array[String]:
	var out: Array[String] = []
	for s in source:
		out.append(str(s))
	return out


# --- choosing a team -----------------------------------------------------------------

func show_team_choice() -> void:
	var box := _reset("Choose Your Team")
	var w := _pending_state.world
	var rows: Array = []
	var ids: Array[int] = []
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var b: FcTeamBusiness = w.businesses.get_by_id(t.id)
		var best := 0.0
		for pid in t.roster.player_ids:
			best = maxf(best, FcPlayerRatings.load_default().overall(w.players.get_by_id(pid)))
		rows.append([t.identity.display_name(city.name), city.country, "%.1fM" % (city.population / 1e6), FcUiTables.money(w.payroll_of_team(t.id, 2026)), "%d" % roundi(best), b.fan_interest])
		ids.append(t.id)
	box.add_child(FcUiTables.label("Pick the franchise you will own. Big markets earn more; small markets are harder but rewarding."))
	var table := FcUiTables.table(["Team", "Country", "Metro pop.", "Payroll", "Best player", "Fan interest"], rows, [0, 150, 90, 90, 90, 90])
	box.add_child(table)
	table.set_meta("team_ids", ids)
	_form["team_table"] = table
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Start Game With Selected Team", func(): on_start_game(_selected_team_id())))
	row.add_child(FcUiTables.button("Back", show_new_league))
	box.add_child(row)


func _selected_team_id() -> int:
	var table: Tree = _form.get("team_table")
	var ids: Array = table.get_meta("team_ids")
	var item := table.get_selected()
	if item == null:
		return ids[0]
	return ids[item.get_index()]


func on_start_game(team_id: int) -> void:
	_pending_state.user_team_id = team_id
	controller = FcGameController.resume(_pending_state)
	_pending_state = null
	show_dashboard()


# --- dashboard ---------------------------------------------------------------------------

func show_dashboard() -> void:
	var s := controller.season()
	var box := _reset(_team_name(controller.state.user_team_id))
	var phase := controller.phase()
	var info := FcUiTables.label("%s    Season %d-%02d    %s    Mode: %s" % [
		controller.state.current_date.to_iso(), s.year, (s.year + 1) % 100,
		{"regular_season": "Regular season", "playoffs": "Playoffs", "season_complete": "Season complete"}[phase],
		"Owner" if controller.state.mode == FcGameState.MODE_OWNER else "Dynasty"], 16)
	box.add_child(info)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	match phase:
		FcGameController.PHASE_REGULAR:
			actions.add_child(FcUiTables.button("Next Day", func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Next Week", func(): on_advance(7)))
			actions.add_child(FcUiTables.button("Next Month", func(): on_advance(30)))
			actions.add_child(FcUiTables.button("To End of Regular Season", func(): on_sim_regular()))
		FcGameController.PHASE_PLAYOFFS:
			actions.add_child(FcUiTables.button("Next Playoff Day", func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Play All Playoffs", func(): on_sim_playoffs()))
		_:
			actions.add_child(FcUiTables.button("Start Next Season (offseason)", on_next_season))
	actions.add_child(FcUiTables.button("Save", on_save))
	actions.add_child(FcUiTables.button("Main Menu", show_main_menu))
	box.add_child(actions)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for name in TAB_NAMES:
		var tab := build_tab(name)
		tab.name = name
		_tabs.add_child(tab)
	box.add_child(_tabs)
	_tabs.current_tab = clampi(_last_tab, 0, TAB_NAMES.size() - 1)
	_tabs.tab_changed.connect(func(i): _last_tab = i)


func on_advance(days: int) -> void:
	controller.advance_days(days)
	show_dashboard()


func on_sim_regular() -> void:
	controller.sim_regular_season()
	show_dashboard()


func on_sim_playoffs() -> void:
	controller.sim_playoffs()
	show_dashboard()
	var champion := controller.season().champion_id
	_say("Champions: %s" % _team_name(champion))


func on_next_season() -> void:
	var report := controller.start_next_season()
	controller.autosave(saves)
	show_dashboard()
	_say("New season. Offseason: %d retired, %d drafted, %d free agents signed, %d re-signed." % [report["retired"], report["drafted"], report["signed"], report["re_signed"]])


func on_save() -> void:
	var result := saves.save("slot_1", controller.state, _team_name(controller.state.user_team_id))
	_say("Saved to slot_1." if result.is_ok() else "Save failed: " + result.message)


func _team_name(team_id: int) -> String:
	var w := controller.state.world if controller != null else _pending_state.world
	var t: FcTeam = w.teams.get_by_id(team_id)
	if t == null:
		return "-"
	return t.identity.display_name(w.cities.get_by_id(t.city_id).name)


## Builds one tab's content. Public so tests can open every tab.
func build_tab(tab_name: String) -> Control:
	match tab_name:
		"Overview": return _tab_overview()
		"Standings": return _tab_standings()
		"Schedule": return _tab_schedule()
		"Roster": return _tab_roster()
		"Finances": return _tab_finances()
		"Staff": return _tab_staff()
		"News": return _tab_news()
	return _tab_league()


# --- tabs ----------------------------------------------------------------------------------

func _tab_overview() -> Control:
	var box := VBoxContainer.new()
	var s := controller.season()
	var rec := controller.user_record()
	box.add_child(FcUiTables.label("Record: %d-%d    League rank: %d    Games left: %d    Streak: %s" % [rec["wins"], rec["losses"], rec["rank"], rec["games_left"], rec["streak"]], 18))
	var next := controller.next_user_game()
	if next != null:
		var opp := next.away_id if next.home_id == controller.state.user_team_id else next.home_id
		box.add_child(FcUiTables.label("Next game: %s %s on %s" % ["vs" if next.home_id == controller.state.user_team_id else "at", _team_name(opp), s.date_of_day(next.day).to_iso()]))
	if s.status == FcSeason.Status.COMPLETE:
		box.add_child(FcUiTables.label("Champions: %s    Runner-up: %s" % [_team_name(s.champion_id), _team_name(s.runner_up_id)], 18, true))
	var report := controller.owner_report()
	if not report.is_empty():
		box.add_child(FcUiTables.label("Owner report, %d-%02d season" % [report["year"], (report["year"] + 1) % 100], 18, true))
		box.add_child(FcUiTables.label("Profit %s    Revenue %s    Franchise value %s (%s)    Cash %s    Debt %s" % [
			FcUiTables.money(report["profit"]), FcUiTables.money(report["revenue"]), FcUiTables.money(report["valuation"]),
			FcUiTables.money(report["valuation_change"]), FcUiTables.money(report["cash"]), FcUiTables.money(report["debt"])]))
		box.add_child(FcUiTables.label("Wins %d (expected about %d)    Owner approval: %d / 100" % [report["wins"], report["expected_wins"], report["approval"]]))
	var rules := controller.state.world.rules_of_league(controller.league_id)
	box.add_child(FcUiTables.label("League rules", 18, true))
	for line in rules.playoffs.describe(controller.state.world.leagues.get_by_id(controller.league_id)):
		box.add_child(FcUiTables.label("  " + line))
	box.add_child(FcUiTables.label("  Salary cap %s, tax line %s, hard limit %s" % [FcUiTables.money(rules.cap.salary_cap), FcUiTables.money(rules.cap.luxury_tax_line), FcUiTables.money(rules.cap.effective_limit())]))
	return box


func _tab_standings() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var league: FcLeague = controller.state.world.leagues.get_by_id(controller.league_id)
	var st := controller.standings()
	for conference in league.conferences:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("%s Conference" % conference.name, 18, true))
		var order := st.conference_ranking(conference)
		var rows: Array = []
		for t in order:
			var r: Dictionary = st.records[t]
			var l10 := st.last_ten(t)
			rows.append([("* " if t == controller.state.user_team_id else "") + _team_name(t), r["w"], r["l"], "%.3f" % st.win_pct(t), "%.1f" % st.games_behind(order[0], t), "%d-%d" % [l10[0], l10[1]], st.streak_text(t)])
		col.add_child(FcUiTables.table(["Team", "W", "L", "Pct", "GB", "L10", "Strk"], rows, [0, 40, 40, 60, 50, 50, 50]))
		row.add_child(col)
	return row


func _tab_schedule() -> Control:
	var s := controller.season()
	var tid := controller.state.user_team_id
	var rows: Array = []
	var keys: Array = []
	for g in s.games:
		if not g.involves(tid):
			continue
		keys.append([g.day, g.series])
		var home := g.home_id == tid
		var opp := g.away_id if home else g.home_id
		var result := ""
		if g.played:
			var mine := g.home_score if home else g.away_score
			var theirs := g.away_score if home else g.home_score
			result = "%s %d-%d%s" % ["W" if mine > theirs else "L", mine, theirs, " (OT)" if g.overtimes > 0 else ""]
		rows.append([s.date_of_day(g.day).to_iso(), "Playoffs" if g.series > 0 else "", "vs" if home else "at", _team_name(opp), result])
	var table := FcUiTables.table(["Date", "", "", "Opponent", "Result"], rows, [0, 70, 40, 260, 120])
	table.set_meta("keys", keys)
	var box := VBoxContainer.new()
	box.add_child(table)
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Box score of selected game", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a game first.")
			return
		var key: Array = keys[item.get_index()]
		var text := box_score_text(key[0], key[1])
		_say("No box score is kept for that game (only your most recent games are stored)." if text == "" else "")
		if text != "":
			_show_text_popup("Box score", text)))
	row.add_child(FcUiTables.label("Box scores are kept for your team's last %d games." % FcSeason.RECENT_BOX_LIMIT))
	box.add_child(row)
	return box


## The box score of a recently played game of the owner's team as text, or "" if none is stored.
func box_score_text(day: int, series: int) -> String:
	for entry in controller.season().recent_boxes:
		if int(entry["day"]) == day and int(entry["series"]) == series:
			var box := FcBoxScore.from_dict(entry["box"])
			var by_period := ""
			for side in 2:
				var parts: Array = []
				for v in box.period_scores[side]:
					parts.append(str(v))
				by_period += "%s: %s\n" % [box.abbreviations[side], "  ".join(parts)]
			return "%s\n%s\n%s\n\n%s" % [box.summary(), by_period, box.table(0), box.table(1)]
	return ""


func _show_text_popup(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.min_size = Vector2i(900, 600)
	var scroll := ScrollContainer.new()
	var label := Label.new()
	label.text = text
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	label.add_theme_font_override("font", font)
	scroll.add_child(label)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()


func _tab_roster() -> Control:
	var w := controller.state.world
	var team: FcTeam = w.teams.get_by_id(controller.state.user_team_id)
	var ratings := FcPlayerRatings.load_default()
	var season_year := controller.state.current_season
	var stats := controller.season().stats
	var rows: Array = []
	var players: Array = []
	for pid in team.roster.player_ids:
		players.append(w.players.get_by_id(pid))
	players.sort_custom(func(a, b): return ratings.overall(a) > ratings.overall(b))
	for p in players:
		var c := w.active_contract_of(p.id)
		rows.append([p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(season_year, 7, 1)),
			"%d cm" % p.physical.height_cm, roundi(ratings.overall(p)), p.development.potential,
			FcUiTables.money(c.salary_for(season_year)) if c != null else "-", c.end_season() if c != null else "-",
			"%.1f" % stats.per_game(p.id, "points"), "%.1f" % stats.per_game(p.id, "rebounds"), "%.1f" % stats.per_game(p.id, "ast"), "%.1f" % stats.per_game(p.id, "minutes"),
			"" if p.games_out == 0 else "OUT %d games: %s" % [p.games_out, p.injury]])
	return FcUiTables.table(["Player", "Pos", "Age", "Height", "Ovr", "Pot", "Salary", "Thru", "PPG", "RPG", "APG", "MPG", "Health"], rows, [0, 50, 50, 70, 50, 50, 90, 60, 55, 55, 55, 55, 220])


func _tab_finances() -> Control:
	var box := VBoxContainer.new()
	var w := controller.state.world
	var b := controller.business()
	var cap := w.rules_of_league(controller.league_id).cap
	box.add_child(FcUiTables.label("Your franchise", 18, true))
	box.add_child(FcUiTables.label("Payroll %s of a %s cap (hard limit %s). Cash %s. Debt %s. Value %s." % [
		FcUiTables.money(w.payroll_of_team(b.id, controller.state.current_season)), FcUiTables.money(cap.salary_cap),
		FcUiTables.money(cap.effective_limit()), FcUiTables.money(b.cash), FcUiTables.money(b.debt), FcUiTables.money(b.valuation)]))
	box.add_child(FcUiTables.label("Fan interest %d, brand %d, arena quality %d." % [b.fan_interest, b.brand, b.facilities_level]))
	if controller.state.mode == FcGameState.MODE_OWNER:
		var row := HBoxContainer.new()
		row.add_child(FcUiTables.label("Ticket price $"))
		var price := SpinBox.new()
		price.min_value = 5
		price.max_value = 2000
		price.value = b.ticket_price
		row.add_child(price)
		row.add_child(FcUiTables.label("  Marketing $M"))
		var marketing := SpinBox.new()
		marketing.min_value = 0
		marketing.max_value = 100
		marketing.step = 0.5
		marketing.value = b.marketing_budget / 1e6
		row.add_child(marketing)
		row.add_child(FcUiTables.button("Apply", func():
			var ok := controller.set_ticket_price(int(price.value)) and controller.set_marketing_budget(roundi(marketing.value * 1e6))
			_say("Updated." if ok else "Those values are not allowed.")))
		row.add_child(FcUiTables.button("Invest in arena (+10)", func():
			_say("Arena improved." if controller.invest_in_facilities(10) else "Not enough cash for that.")
			show_dashboard()))
		box.add_child(row)
	var fin := FcFinanceEngine.new(w)
	var rows: Array = []
	var years: Array = []
	for r in w.finances.all():
		if r.team_id == b.id:
			years.append(r)
	years.reverse()
	for r in years:
		rows.append(["%d-%02d" % [r.year, (r.year + 1) % 100], r.wins, FcUiTables.money(r.total_revenue()), FcUiTables.money(r.total_expenses()), FcUiTables.money(r.profit()),
			r.average_attendance, "$%d" % r.ticket_price, FcUiTables.money(r.valuation_end)])
	box.add_child(FcUiTables.table(["Season", "Wins", "Revenue", "Expenses", "Profit", "Attendance", "Ticket", "Value"], rows))
	return box


func _tab_staff() -> Control:
	var box := VBoxContainer.new()
	var w := controller.state.world
	var tid := controller.state.user_team_id
	var rows: Array = []
	var ids: Array[int] = []
	for sc in w.staff_contracts_of_team(tid):
		var m: FcStaffMember = w.staff.get_by_id(sc.staff_id)
		rows.append([FcStaffRole.display_name(sc.role), m.identity.full_name(), m.reputation, m.experience_years, FcUiTables.money(sc.salary_for(controller.state.current_season)), sc.end_season()])
		ids.append(m.id)
	box.add_child(FcUiTables.label("Your staff", 18, true))
	var table := FcUiTables.table(["Role", "Name", "Reputation", "Experience", "Salary", "Through"], rows)
	box.add_child(table)
	if controller.state.mode == FcGameState.MODE_OWNER:
		var row := HBoxContainer.new()
		row.add_child(FcUiTables.button("Fire selected", func():
			var item := table.get_selected()
			if item != null and controller.fire_staff(ids[item.get_index()]):
				_say("Fired.")
			show_dashboard()))
		var role_picker := OptionButton.new()
		for role in [FcStaffRole.Id.GENERAL_MANAGER, FcStaffRole.Id.HEAD_COACH, FcStaffRole.Id.ASSISTANT_COACH, FcStaffRole.Id.SCOUT]:
			role_picker.add_item(FcStaffRole.display_name(role))
			role_picker.set_item_metadata(role_picker.item_count - 1, role)
		var person_picker := OptionButton.new()
		var fill := func():
			person_picker.clear()
			var role: int = role_picker.get_item_metadata(role_picker.selected)
			for m in controller.staff_pool(role).slice(0, 12):
				person_picker.add_item("%s (rep %d, %s)" % [m.identity.full_name(), m.reputation, FcUiTables.money(controller.asking_salary(m.id))])
				person_picker.set_item_metadata(person_picker.item_count - 1, m.id)
		role_picker.item_selected.connect(func(_i): fill.call())
		fill.call()
		row.add_child(role_picker)
		row.add_child(person_picker)
		row.add_child(FcUiTables.button("Hire (3 years)", func():
			if person_picker.item_count == 0:
				return
			var error := controller.hire_staff(person_picker.get_item_metadata(person_picker.selected), role_picker.get_item_metadata(role_picker.selected), 3)
			_say("Hired." if error == "" else error)
			show_dashboard()))
		box.add_child(row)
	return box


func _tab_news() -> Control:
	var w := controller.state.world
	var rows: Array = []
	var items: Array = w.news.duplicate()
	items.reverse()
	var mine := controller.state.user_team_id
	for item in items.slice(0, 80):
		var tag: String = {"injury": "Injury", "milestone": "Milestone", "champion": "Champions", "award": "Award", "signing": "Signing", "retirement": "Retirement", "draft": "Draft", "staff": "Staff"}.get(item["kind"], "News")
		rows.append([item["date"], tag, ("* " if item["team"] == mine else "") + item["text"]])
	return FcUiTables.table(["Date", "Type", "Headline"], rows, [100, 90, 0])


func _tab_league() -> Control:
	var box := VBoxContainer.new()
	var w := controller.state.world
	var s := controller.season()
	var stats := s.stats
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["Points", "points"], ["Rebounds", "rebounds"], ["Assists", "ast"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("%s per game" % entry[0], 18, true))
		var rows: Array = []
		var min_games := maxi(1, floori(controller.season().next_day / 4.0)) if s.status == FcSeason.Status.REGULAR else 20
		for pid in stats.leaders(entry[1], mini(min_games, 20), 10):
			var l: Dictionary = stats.lines[pid]
			var t: FcTeam = w.teams.get_by_id(l["team"])
			rows.append([l["name"], t.identity.abbreviation if t != null else "", "%.1f" % stats.per_game(pid, entry[1])])
		col.add_child(FcUiTables.table(["Player", "Team", entry[0]], rows, [0, 50, 60]))
		row.add_child(col)
	box.add_child(row)
	var history: Array = []
	for season in w.seasons.all():
		if season.status == FcSeason.Status.COMPLETE:
			history.append(["%d-%02d" % [season.year, (season.year + 1) % 100], _team_name(season.champion_id), _team_name(season.runner_up_id),
				_player_name(season.awards.get("mvp", 0))])
	history.reverse()
	box.add_child(FcUiTables.label("Champions", 18, true))
	box.add_child(FcUiTables.table(["Season", "Champion", "Runner-up", "MVP"], history))
	return box


func _player_name(player_id: int) -> String:
	var p: FcPlayer = controller.state.world.players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"
