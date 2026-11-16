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
const GAMES_CHOICES := [["Short: about 40 games", 40], ["Medium: about 60 games", 60], ["Standard: about 80 games (default)", 80], ["Long: about 100 games", 100]]
const TAB_NAMES := ["Overview", "Standings", "Schedule", "Roster", "Finances", "Staff", "Draft", "Market", "Trades", "History", "News", "League"]

var controller: FcGameController
var saves := FcSaveManager.new()

var _defs := FcDefinitionSet.load_default()
var _data := FcGenerationData.load_default()
var _root: VBoxContainer
var _content: Control
var _pending_state: FcGameState
var _tabs: TabContainer
## The team the user is talking to in the Trades tab (0 = first other team).
var _trade_partner: int = 0
## Set after the warning about expiring contracts; a second press starts the next season.
var _confirm_next_season: bool = false
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
	_form["games"] = _options(grid, "Season length (30-team league)", GAMES_CHOICES.map(func(a): return a[0]))
	_form["games"].selected = 2
	_form["lottery"] = _options(grid, "Draft lottery", ["On (worst teams are favoured but not guaranteed)", "Off (worst record picks first)"])
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
		cfg.target_games = GAMES_CHOICES[(_form["games"] as OptionButton).selected][1]
		cfg.draft_lottery = (_form["lottery"] as OptionButton).selected == 0
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
		{"regular_season": "Regular season", "playoffs": "Playoffs", "season_complete": "Season complete", "offseason": "Offseason: free agency is open to you first", "draft": "The draft"}[phase],
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
		FcGameController.PHASE_DRAFT:
			actions.add_child(FcUiTables.button("Let the staff finish the draft", on_draft_auto))
		FcGameController.PHASE_OFFSEASON:
			actions.add_child(FcUiTables.button("Finish Offseason and Start Next Season", on_next_season))
		_:
			if controller.state.mode == FcGameState.MODE_OWNER:
				actions.add_child(FcUiTables.button("Begin Offseason (draft, contracts, free agency)", on_next_season))
			else:
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


## One button, three jobs. Owner Mode: first press (season over) warns about players whose
## contracts end, then begins the offseason (draft and re-signing done, free agency open to
## you); the next press lets the AI teams sign players and starts the new season.
## Dynasty Mode: one press does everything.
func on_next_season() -> void:
	if controller.state.mode == FcGameState.MODE_OWNER and controller.state.offseason_stage == 0 and controller.phase() != FcGameController.PHASE_PLAYOFFS and controller.phase() != FcGameController.PHASE_REGULAR and not _confirm_next_season:
		var leaving := controller.expiring_players().filter(func(e): return not e["agreed"])
		if not leaving.is_empty():
			var names: Array[String] = []
			for e in leaving:
				names.append(e["player"].identity.full_name())
			_confirm_next_season = true
			_say("These players' contracts end and they will LEAVE unless you extend them (Roster tab): %s. Press Start Next Season again to let them go." % ", ".join(names))
			return
	_confirm_next_season = false
	if controller.state.mode == FcGameState.MODE_OWNER and controller.state.offseason_stage == 0:
		var first := controller.begin_offseason()
		controller.autosave(saves)
		_last_tab = FcApp.TAB_NAMES.find("Draft")
		show_dashboard()
		var gm_notes := " ".join(controller.gm_log())
		if controller.phase() == FcGameController.PHASE_DRAFT:
			_say("Offseason: %d players retired. The draft has begun: scout the board on the Draft tab and pick when it is your turn. %s" % [first["retired"], gm_notes])
		else:
			_last_tab = FcApp.TAB_NAMES.find("Market")
			show_dashboard()
			_say("Offseason: %d players retired. The draft is done and the free-agency window is open. %s" % [first["retired"], gm_notes])
		return
	var report := controller.start_next_season()
	controller.autosave(saves)
	show_dashboard()
	_say("New season. The AI teams signed %d free agents." % report["signed"] if not report.has("retired") else "New season. Offseason: %d retired, %d drafted, %d free agents signed, %d re-signed." % [report["retired"], report["drafted"], report["signed"], report["re_signed"]])


## The staff finishes the draft for the user; the free-agency window opens.
func on_draft_auto() -> void:
	controller.draft_auto_rest()
	controller.autosave(saves)
	_last_tab = FcApp.TAB_NAMES.find("Market")
	show_dashboard()
	_say("The draft is over. Sign free agents on the Market tab before the AI teams do, then finish the offseason.")


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
		"Draft": return _tab_draft()
		"Market": return _tab_market()
		"Trades": return _tab_trades()
		"History": return _tab_history()
		"News": return _tab_news()
	return _tab_league()


# --- tabs ----------------------------------------------------------------------------------

## The Hall of Fame and single-season records.
func _tab_history() -> Control:
	var w := controller.state.world
	var records := FcRecords.new(w, controller.league_id)
	var box := HBoxContainer.new()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(FcUiTables.label("Hall of Fame", 18, true))
	var hof_rows: Array = []
	for entry in records.hall_of_fame(controller.state.current_season):
		var h := records.honours_of(entry[1])
		var t := w.career_totals(entry[1])
		hof_rows.append([w.player_name(entry[1]), entry[2], t["seasons"], t["points"], h["mvp"], h["titles"], roundi(entry[0])])
	if hof_rows.is_empty():
		left.add_child(FcUiTables.label("Nobody has been inducted yet. Retired stars are eligible %d seasons after their last game." % FcRecords.EXPERIENCE_WAIT))
	left.add_child(FcUiTables.table(["Player", "Inducted", "Seasons", "Points", "MVPs", "Titles", "Score"], hof_rows, [0, 70, 70, 70, 50, 50, 50]))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		right.add_child(FcUiTables.label("Best single seasons: %s" % entry[1].to_lower(), 16, true))
		var rows: Array = []
		for rec in records.single_season_records(entry[0], 5):
			rows.append([w.player_name(rec[1]), "%d-%02d" % [rec[2], (rec[2] + 1) % 100], rec[0]])
		right.add_child(FcUiTables.table(["Player", "Season", entry[1]], rows, [0, 80, 80]))
	box.add_child(right)
	return box


## Propose a trade: pick a partner, select players on both sides, check or propose.
func _tab_trades() -> Control:
	var w := controller.state.world
	var user_id := controller.state.user_team_id
	var box := VBoxContainer.new()
	var others: Array[int] = []
	for t in w.teams.all():
		if t.id != user_id and w.leagues.get_by_id(controller.league_id).contains_team(t.id):
			others.append(t.id)
	if others.is_empty():
		box.add_child(FcUiTables.label("There is nobody to trade with."))
		return box
	if not _trade_partner in others:
		_trade_partner = others[0]
	var picker := OptionButton.new()
	for tid in others:
		picker.add_item(_team_name(tid))
	picker.selected = others.find(_trade_partner)
	picker.item_selected.connect(func(i):
		_trade_partner = others[i]
		show_dashboard())
	box.add_child(FcUiTables.label("Trade with:", 18, true))
	box.add_child(picker)
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var lists: Array = []
	var ids_by_list: Array = []
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [[user_id, "You give"], [_trade_partner, "You get"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label(side[1], 16, true))
		var list := ItemList.new()
		list.select_mode = ItemList.SELECT_MULTI
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var ids: Array[int] = []
		for pid in w.teams.get_by_id(side[0]).roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			var c := w.active_contract_of(pid)
			list.add_item("%s  %s  age %d  ovr %d  %s%s" % [p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(year, 7, 1)), roundi(ratings.overall(p)), FcUiTables.money(c.cap_hit_for(year)) if c != null else "-", "  (no-trade)" if c != null and c.no_trade else ""])
			ids.append(pid)
		col.add_child(list)
		columns.add_child(col)
		lists.append(list)
		ids_by_list.append(ids)
	box.add_child(columns)
	var pick_lists: Array = []
	var picks_by_list: Array = []
	var pick_columns := HBoxContainer.new()
	for side in [[user_id, "Draft picks you give"], [_trade_partner, "Draft picks you get"]]:
		var col2 := VBoxContainer.new()
		col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col2.add_child(FcUiTables.label(side[1], 16, true))
		var plist := ItemList.new()
		plist.select_mode = ItemList.SELECT_MULTI
		plist.custom_minimum_size = Vector2(0, 110)
		var refs: Array = []
		for entry in controller.tradable_picks(side[0]):
			plist.add_item(entry["label"])
			refs.append([entry["year"], entry["round"], entry["original"]])
		col2.add_child(plist)
		pick_columns.add_child(col2)
		pick_lists.append(plist)
		picks_by_list.append(refs)
	box.add_child(pick_columns)
	var pick_refs := func(index: int) -> Array:
		var out2: Array = []
		for i in pick_lists[index].get_selected_items():
			out2.append(picks_by_list[index][i])
		return out2
	var pick := func(index: int) -> Array:
		var out: Array = []
		for i in lists[index].get_selected_items():
			out.append(ids_by_list[index][i])
		return out
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Check the offer", func():
		_say(controller.propose_trade(_trade_partner, pick.call(0), pick.call(1), true, pick_refs.call(0), pick_refs.call(1))["reason"])))
	row.add_child(FcUiTables.button("Propose trade", func():
		var r := controller.propose_trade(_trade_partner, pick.call(0), pick.call(1), false, pick_refs.call(0), pick_refs.call(1))
		if r["accepted"]:
			show_dashboard()
		_say(r["reason"])))
	box.add_child(row)
	return box


## Free agents (best first) and the most recent draft. Read-only for now.
func _tab_draft() -> Control:
	var w := controller.state.world
	var box := VBoxContainer.new()
	var status := controller.draft_status()
	if status.is_empty():
		box.add_child(FcUiTables.label("The draft is held after the season, in the offseason. You will see your scouts' board here and pick for your team.", 16))
		var report := controller.latest_draft_report()
		var rows: Array = []
		if not report.is_empty():
			box.add_child(FcUiTables.label("The %d draft" % report["year"], 18, true))
			for entry in report["rows"]:
				var p: FcPlayer = w.players.get_by_id(entry["player"])
				if p != null:
					rows.append([entry["pick"], entry["round"], _team_name(entry["team"]), p.identity.full_name(), FcPosition.abbreviation(p.primary_position)])
		box.add_child(FcUiTables.table(["Pick", "Round", "Team", "Player", "Pos"], rows, [50, 60, 0, 0, 50]))
		return box
	var prefix := "Pick %d of %d (round %d): " % [status["pick"], status["total"], status["round"]]
	if status["complete"]:
		box.add_child(FcUiTables.label("The draft is complete.", 18, true))
	elif status["user_on_clock"]:
		box.add_child(FcUiTables.label(prefix + "YOU ARE ON THE CLOCK", 18, true))
	else:
		box.add_child(FcUiTables.label(prefix + _team_name(status["team"]), 18))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_child(FcUiTables.label("Draft board (your scouts' view; ranges hold the truth about 4 times in 5)", 16, true))
	var rows2: Array = []
	var ids: Array[int] = []
	var rank := 0
	for entry in controller.draft_board():
		rank += 1
		var p: FcPlayer = entry["player"]
		var r: Dictionary = entry["report"]
		rows2.append([rank, p.identity.full_name(), FcPosition.abbreviation(p.primary_position), entry["age"], "%d cm" % p.physical.height_cm, "%d-%d" % [r["ovr_low"], r["ovr_high"]], "%d-%d" % [r["pot_low"], r["pot_high"]], r["character"] if r["worked_out"] else "", p.identity.country])
		ids.append(p.id)
	var table := FcUiTables.table(["#", "Prospect", "Pos", "Age", "Height", "Overall", "Potential", "Worked out", "From"], rows2, [40, 0, 45, 45, 70, 70, 80, 130, 110])
	left.add_child(table)
	var buttons := HBoxContainer.new()
	buttons.add_child(FcUiTables.button("Draft selected prospect", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a prospect first.")
			return
		var r2 := controller.user_draft_pick(ids[item.get_index()])
		_say(r2["reason"])
		_after_draft_action()))
	buttons.add_child(FcUiTables.button("Invite selected to a workout (%d left)" % controller.draft_workouts_left(), func():
		var item := table.get_selected()
		if item == null:
			_say("Select a prospect first.")
			return
		var r4 := controller.invite_to_workout(ids[item.get_index()])
		show_dashboard()
		_say(r4["reason"])))
	buttons.add_child(FcUiTables.button("Let my staff pick", func():
		var r3 := controller.draft_staff_pick()
		_say(r3["reason"])
		_after_draft_action()))
	left.add_child(buttons)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Picks so far", 16, true))
	var log_rows: Array = []
	var results := controller.draft_results()
	for i in range(results.size() - 1, -1, -1):
		var pick: Array = results[i]
		var p2: FcPlayer = w.players.get_by_id(pick[3])
		log_rows.append([pick[1], _team_name(pick[2]), p2.identity.full_name(), FcPosition.abbreviation(p2.primary_position)])
	right.add_child(FcUiTables.table(["Pick", "Team", "Player", "Pos"], log_rows, [50, 0, 0, 50]))
	columns.add_child(right)
	box.add_child(columns)
	return box


## After a pick: back to the offseason window if the draft ended, otherwise refresh the board.
func _after_draft_action() -> void:
	var message := _message.text if _message != null else ""
	if controller.phase() == FcGameController.PHASE_OFFSEASON:
		controller.autosave(saves)
		_last_tab = FcApp.TAB_NAMES.find("Market")
		show_dashboard()
		_say(message + " The draft is over: sign free agents on the Market tab before the AI teams do, then finish the offseason.")
		return
	show_dashboard()
	_say(message)


func _tab_market() -> Control:
	var w := controller.state.world
	var box := HBoxContainer.new()
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_child(FcUiTables.label("Best free agents", 18, true))
	var agents := controller.free_agent_market(20)
	var rows: Array = []
	var agent_ids: Array[int] = []
	for entry in agents:
		var p: FcPlayer = entry["player"]
		rows.append([p.identity.full_name(), FcPosition.abbreviation(p.primary_position), entry["age"], roundi(ratings.overall(p)), p.development.potential, FcUiTables.money(entry["ask"]), entry["years"]])
		agent_ids.append(p.id)
	var fa_table := FcUiTables.table(["Player", "Pos", "Age", "Ovr", "Pot", "Asks", "Years"], rows, [0, 50, 50, 50, 50, 90, 50])
	left.add_child(fa_table)
	var offer_row := HBoxContainer.new()
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
	fa_table.item_selected.connect(func():
		var picked := fa_table.get_selected()
		if picked != null:
			offer_salary.value = agents[picked.get_index()]["ask"] / 1e6
			offer_years.value = agents[picked.get_index()]["years"])
	offer_row.add_child(FcUiTables.button("Sign selected free agent", func():
		var item := fa_table.get_selected()
		if item == null:
			_say("Select a free agent first.")
			return
		var r := controller.sign_free_agent(agent_ids[item.get_index()], roundi(offer_salary.value * 1e6), int(offer_years.value))
		if r["signed"]:
			show_dashboard()
		_say(r["reason"])))
	left.add_child(offer_row)
	left.add_child(FcUiTables.label("Players ask for the amount shown but accept a little less, especially for longer contracts. Change the offer and press the button; a refusal tells you the least he will take."))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Latest draft (first round)", 18, true))
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
				draft_rows.append([entry["pick"], _team_name(entry["team"]), "%+d" % moved if moved != 0 else "-", p.identity.full_name(), FcPosition.abbreviation(p.primary_position), roundi(ratings.overall(p)), p.development.potential])
		var note := FcUiTables.label("After the %d season. %s" % [report["year"], "Lottery on: 'Lot.' shows how many places the lottery moved a team up (+) or down (-)." if report["lottery"] else "No lottery: order follows the records."])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(100, 0)
		right.add_child(note)
		var winners: Array[String] = []
		for entry in report["rows"]:
			if entry["round"] == 1 and entry["moved"] > 0:
				winners.append("%s jumped %d place%s to pick %d" % [_team_name(entry["team"]), entry["moved"], "" if entry["moved"] == 1 else "s", entry["pick"]])
		if not winners.is_empty():
			var winners_label := FcUiTables.label("Lottery winners: " + "; ".join(winners))
			winners_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			winners_label.custom_minimum_size = Vector2(100, 0)
			right.add_child(winners_label)
	right.add_child(FcUiTables.table(["Pick", "Team", "Lot.", "Player", "Pos", "Ovr", "Pot"], draft_rows, [50, 0, 50, 0, 50, 50, 50]))
	box.add_child(right)
	return box


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
	var news: Array = controller.state.world.news
	if not news.is_empty():
		box.add_child(FcUiTables.label("Latest news", 18, true))
		for i in range(news.size() - 1, maxi(-1, news.size() - 7), -1):
			box.add_child(FcUiTables.label("  %s  %s" % [news[i]["date"], news[i]["text"]]))
	var rules := controller.state.world.rules_of_league(controller.league_id)
	box.add_child(FcUiTables.label("League rules", 18, true))
	for line in rules.playoffs.describe(controller.state.world.leagues.get_by_id(controller.league_id)):
		box.add_child(FcUiTables.label("  " + line))
	if rules.draft.lottery_teams > 0:
		box.add_child(FcUiTables.label("  Draft lottery: the worst %d non-playoff teams enter and the top %d picks are drawn" % [rules.draft.lottery_teams, rules.draft.lottery_picks]))
	else:
		box.add_child(FcUiTables.label("  No draft lottery: the worst record picks first"))
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
	var table := FcUiTables.table(["Date", "Round", "", "Opponent", "Result"], rows, [110, 80, 40, 0, 140])
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


## A full profile of one player as text: bio, body, ratings, personality, tendencies,
## contract and career statistics.
func player_profile_text(player_id: int) -> String:
	var w := controller.state.world
	var p: FcPlayer = w.players.get_by_id(player_id)
	if p == null:
		return ""
	var year := controller.state.current_season
	var lines: Array[String] = []
	lines.append("%s    %s    age %d    %d cm, %d kg    %s" % [p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(year, 7, 1)), p.physical.height_cm, p.physical.weight_kg, p.identity.country])
	var team := w.team_of_player(player_id)
	lines.append("Team: %s    Overall %d    Potential %d    Peak age %d" % [w.team_display_name(team.id) if team != null else "free agent", roundi(FcPlayerRatings.load_default().overall(p)), p.development.potential, p.development.peak_age])
	if p.games_out > 0:
		lines.append("OUT %d games: %s" % [p.games_out, p.injury])
	var c := w.active_contract_of(player_id)
	if c != null:
		lines.append("Contract: %s a year through %d (%d years left)" % [FcUiTables.money(c.salary_for(year)), c.end_season(), maxi(0, c.end_season() - year + 1)])
	for catalog_pair in [["Basketball ratings", w.definitions.attributes, p.attributes], ["Personality", w.definitions.personality, p.personality], ["Tendencies", w.definitions.tendencies, p.tendencies]]:
		lines.append("")
		lines.append(catalog_pair[0])
		var catalog: FcAttributeCatalog = catalog_pair[1]
		var values: FcAttributeSet = catalog_pair[2]
		var line := ""
		var count := 0
		for key in catalog.keys():
			line += "%-24s %3d    " % [catalog.get_def(key).display_name, values.get_value(key)]
			count += 1
			if count % 3 == 0:
				lines.append("  " + line)
				line = ""
		if line != "":
			lines.append("  " + line)
	lines.append("")
	lines.append("Career")
	lines.append("  %-8s %-6s %4s %5s %5s %5s %5s" % ["Season", "Team", "GP", "MPG", "PPG", "RPG", "APG"])
	for row in w.careers.get(player_id, []):
		var t: FcTeam = w.teams.get_by_id(row[1])
		var gp: int = maxi(1, row[2])
		lines.append("  %-8s %-6s %4d %5.1f %5.1f %5.1f %5.1f" % ["%d-%02d" % [row[0], (row[0] + 1) % 100], t.identity.abbreviation if t != null else "?", row[2], row[3] / 60.0 / gp, float(row[4]) / gp, float(row[11] + row[12]) / gp, float(row[13]) / gp])
	var totals := w.career_totals(player_id)
	if totals["seasons"] > 0:
		lines.append("  Career: %d games, %d points, %d rebounds, %d assists" % [totals["gp"], totals["points"], totals["rebounds"], totals["ast"]])
	return "\n".join(lines)


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
	var table := FcUiTables.table(["Player", "Pos", "Age", "Height", "Ovr", "Pot", "Salary", "Thru", "PPG", "RPG", "APG", "MPG", "Health"], rows, [0, 50, 50, 70, 50, 50, 90, 60, 55, 55, 55, 55, 220])
	var ids: Array[int] = []
	for p in players:
		ids.append(p.id)
	var box := VBoxContainer.new()
	box.add_child(table)
	var row := HBoxContainer.new()
	var expiring := {}
	for e in controller.expiring_players():
		expiring[e["player"].id] = e
	var ext_salary := SpinBox.new()
	ext_salary.min_value = 0.1
	ext_salary.max_value = 100
	ext_salary.step = 0.05
	var ext_years := SpinBox.new()
	ext_years.min_value = 1
	ext_years.max_value = 5
	table.item_selected.connect(func():
		var picked := table.get_selected()
		if picked != null and expiring.has(ids[picked.get_index()]):
			ext_salary.value = expiring[ids[picked.get_index()]]["ask"] / 1e6
			ext_years.value = expiring[ids[picked.get_index()]]["years"])
	row.add_child(FcUiTables.label("Extension $M"))
	row.add_child(ext_salary)
	row.add_child(FcUiTables.label("years"))
	row.add_child(ext_years)
	row.add_child(FcUiTables.button("Extend contract of selected player", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		var r := controller.extend_contract(ids[item.get_index()], roundi(ext_salary.value * 1e6), int(ext_years.value))
		if r["ok"]:
			show_dashboard()
		_say(r["reason"])))
	row.add_child(FcUiTables.button("Release selected player (pay half his salary)", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		var r := controller.release_player(ids[item.get_index()])
		if r["released"]:
			show_dashboard()
		_say(r["reason"])))
	row.add_child(FcUiTables.button("Player profile of selected player", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		_show_text_popup("Player profile", player_profile_text(ids[item.get_index()]))))
	box.add_child(row)
	return box


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
	var finance_engine := FcFinanceEngine.new(w)
	var executive := w.staff_in_role(b.id, FcStaffRole.Id.BUSINESS_EXECUTIVE)
	if executive == null:
		box.add_child(FcUiTables.label("No business executive: sponsorships, marketing and overhead all suffer. Hire one on the Staff tab."))
	else:
		box.add_child(FcUiTables.label("Business executive %s: marketing %d (sponsorships and brand), financial acumen %d (overhead), community relations %d (fan interest)." % [executive.identity.full_name(), executive.skills.get_value("marketing"), executive.skills.get_value("financial_acumen"), executive.skills.get_value("community_relations")]))
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
		row.add_child(FcUiTables.label("   Suggested $%d" % controller.suggested_ticket_price()))
		row.add_child(FcUiTables.button("Use suggestion", func():
			price.value = controller.suggested_ticket_price()
			var ok2 := controller.set_ticket_price(int(price.value))
			_say("Ticket price set to the suggestion." if ok2 else "That price is not allowed.")))
		box.add_child(row)
		box.add_child(FcUiTables.label("  The suggestion is the price that just fills your arena today. Fan interest and brand change as you win or lose, so check it each season; AI teams reprice every year."))
		var loans := HBoxContainer.new()
		loans.add_child(FcUiTables.label("Sponsorship deal:"))
		var plan := OptionButton.new()
		for name in FcTeamBusiness.SPONSOR_PLANS:
			plan.add_item(name)
		plan.selected = b.sponsor_plan
		plan.item_selected.connect(func(i):
			controller.set_sponsor_plan(i)
			_say("Sponsorship: %s. Steady pays less but guaranteed; Performance pays more only if you win." % FcTeamBusiness.SPONSOR_PLANS[i]))
		loans.add_child(plan)
		loans.add_child(FcUiTables.label("   Loan $M"))
		var amount := SpinBox.new()
		amount.min_value = 1
		amount.max_value = 500
		amount.value = 10
		loans.add_child(amount)
		loans.add_child(FcUiTables.button("Borrow", func():
			var r := controller.borrow(roundi(amount.value * 1e6))
			_say(r["reason"])
			if r["ok"]:
				show_dashboard()))
		loans.add_child(FcUiTables.button("Repay", func():
			var r := controller.repay_debt(roundi(amount.value * 1e6))
			_say(r["reason"])
			if r["ok"]:
				show_dashboard()))
		loans.add_child(FcUiTables.label("   Borrowing limit %s" % FcUiTables.money(controller.loan_limit())))
		box.add_child(loans)
		var shop := HBoxContainer.new()
		shop.add_child(FcUiTables.label("Concession prices %"))
		var concessions := SpinBox.new()
		concessions.min_value = 70
		concessions.max_value = 150
		concessions.step = 5
		concessions.value = b.concession_price_pct
		shop.add_child(concessions)
		shop.add_child(FcUiTables.label("   Merchandise range"))
		var merch := OptionButton.new()
		for name in FcTeamBusiness.MERCH_TIERS:
			merch.add_item(name)
		merch.selected = b.merch_tier
		shop.add_child(merch)
		shop.add_child(FcUiTables.button("Apply shop settings", func():
			controller.set_concession_price(int(concessions.value))
			controller.set_merch_tier(merch.selected)
			_say("Shop settings updated. Higher concession prices earn more per fan but cost fan interest; a premium range sells more but costs more stock.")))
		box.add_child(shop)
		var build := HBoxContainer.new()
		build.add_child(FcUiTables.label("Arena project:"))
		var options := controller.arena_project_options()
		var project_pick := OptionButton.new()
		for o in options:
			project_pick.add_item("%s (%s, %d season%s)%s" % [o["name"], FcUiTables.money(o["cost"]), o["seasons"], "" if o["seasons"] == 1 else "s", " - under way" if o["running"] else ""])
		build.add_child(project_pick)
		build.add_child(FcUiTables.button("Start project", func():
			var r := controller.start_arena_project(options[project_pick.selected]["key"])
			_say(r["reason"])
			if r["ok"]:
				show_dashboard()))
		box.add_child(build)
		var detail: Array[String] = []
		for o in options:
			detail.append("%s: %s" % [o["name"], o["description"]])
		box.add_child(FcUiTables.label("  " + "   |   ".join(detail)))
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
	var books := HBoxContainer.new()
	books.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.add_child(FcUiTables.label("Your seasons", 16, true))
	mine.add_child(FcUiTables.table(["Season", "Wins", "Revenue", "Expenses", "Profit", "Attendance", "Ticket", "Value"], rows))
	books.add_child(mine)
	var league_books := controller.league_finances()
	if not league_books.is_empty():
		var compare := VBoxContainer.new()
		compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compare.size_flags_stretch_ratio = 1.0
		compare.add_child(FcUiTables.label("How you compare (last season, * = you)", 16, true))
		var compare_rows: Array = []
		for entry in league_books:
			compare_rows.append(["%s%s" % ["* " if entry["team"] == b.id else "", entry["name"]], entry["wins"], FcUiTables.money(entry["revenue"]), FcUiTables.money(entry["profit"]), FcUiTables.money(entry["payroll"]), "$%d" % entry["price"], entry["attendance"]])
		compare.add_child(FcUiTables.table(["Team", "Wins", "Revenue", "Profit", "Payroll", "Ticket", "Fans"], compare_rows, [150, 40, 72, 72, 72, 52, 48]))
		books.add_child(compare)
	box.add_child(books)
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
	if controller.state.mode == FcGameState.MODE_OWNER:
		box.add_child(FcUiTables.label("Front office: what your general manager handles", 18, true))
		var gm := controller.gm_summary()
		if gm.is_empty():
			box.add_child(FcUiTables.label("You have no general manager, so you decide everything yourself. Hire one below."))
		else:
			box.add_child(FcUiTables.label("%s (talent evaluation %d, negotiation %d). A sharper eye means better re-signing, drafting and signings; leave an area unticked to decide it yourself." % [gm["name"], gm["talent_evaluation"], gm["negotiation"]]))
			var checks := HBoxContainer.new()
			for entry in [["contracts", "Re-sign my players"], ["draft", "Run the draft"], ["free_agency", "Sign free agents"], ["trades", "Make trades"], ["injuries", "Replace injured players"]]:
				var check := CheckBox.new()
				check.text = entry[1]
				check.button_pressed = controller.delegation_on(entry[0])
				check.toggled.connect(func(on): controller.set_delegation(entry[0], on))
				checks.add_child(check)
			box.add_child(checks)
			var direction_row := HBoxContainer.new()
			direction_row.add_child(FcUiTables.label("Philosophy:"))
			var philosophy_pick := OptionButton.new()
			for name in ["Win now (value today's ability, buy veterans)", "Balanced", "Rebuild (value youth and potential, sell veterans)"]:
				philosophy_pick.add_item(name)
			philosophy_pick.selected = FcGameState.PHILOSOPHIES.find(controller.philosophy())
			direction_row.add_child(philosophy_pick)
			direction_row.add_child(FcUiTables.label("   Budget:"))
			var budget_pick := OptionButton.new()
			for name in ["Frugal (92% of the cap)", "Normal (the cap)", "Aggressive (up to 115%, below the tax line)"]:
				budget_pick.add_item(name)
			budget_pick.selected = FcGameState.BUDGETS.find(controller.state.direction["budget"])
			direction_row.add_child(budget_pick)
			var apply_direction := func(_i):
				controller.set_direction(FcGameState.PHILOSOPHIES[philosophy_pick.selected], FcGameState.BUDGETS[budget_pick.selected])
				_say("Direction set. Your general manager follows it when he re-signs, drafts, trades and signs players (only in the areas ticked above).")
			philosophy_pick.item_selected.connect(apply_direction)
			budget_pick.item_selected.connect(apply_direction)
			box.add_child(direction_row)
			var card := controller.gm_report()
			if not card.is_empty():
				box.add_child(FcUiTables.label("Last season: %s. %d wins (about %d expected), payroll %s against a budget of %s." % [card["grade"], card["wins"], card["expected_wins"], FcUiTables.money(card["payroll"]), FcUiTables.money(card["limit"])]))
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
	var all_time := HBoxContainer.new()
	all_time.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("All-time %s" % entry[1].to_lower(), 18, true))
		var leader_rows: Array = []
		for pid in w.career_leaders(entry[0], 8):
			var totals := w.career_totals(pid)
			var p: FcPlayer = w.players.get_by_id(pid)
			leader_rows.append([p.identity.full_name() + ("" if p.status == FcPlayer.Status.RETIRED else " *"), totals["seasons"], totals[entry[0]]])
		col.add_child(FcUiTables.table(["Player (* active)", "Seasons", entry[1]], leader_rows, [0, 70, 80]))
		all_time.add_child(col)
	box.add_child(all_time)
	return box


func _player_name(player_id: int) -> String:
	var p: FcPlayer = controller.state.world.players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"
