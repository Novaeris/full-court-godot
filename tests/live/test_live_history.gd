extends FcLiveTestCase
## The Owner History tab (Phase 3) in a real scene: the sub-pages, the team picker, the lazily filled pages (retired numbers, rivalries,
## storylines), a retired legend's number card, the storyline scope switch, a sensible build time, and the Career hub's storylines panel.

const PREFS := "user://test_preferences_live_history.cfg"

var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_history")
	host.add_child(app)
	app.setup()


func after_each() -> void:
	super.after_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_live_history.cfg")
	FcSafeFile.remove_tree("user://test_saves_live_history")


func _texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	if n is Button:
		out += "[%s]\n" % (n as Button).text
	for c in n.get_children():
		out += _texts(c)
	return out


## build_tab returns the pages control itself; find_child only looks below a node.
func _pages_of(tab: Control) -> FcTabPages:
	return tab as FcTabPages if tab is FcTabPages else tab.find_child("HistoryPages", true, false) as FcTabPages


func _owner_league_with_history() -> void:
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "History Owner"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	for i in 3:
		app.controller.sim_playoffs()
		app.controller.start_next_season()


func test_the_history_tab_has_its_pages_and_the_franchise_page_is_ready() -> void:
	_owner_league_with_history()
	await frames(2)
	var started := Time.get_ticks_msec()
	var tab := app.build_tab("History")
	var took := Time.get_ticks_msec() - started
	host.add_child(tab)
	await frames(2)
	assert_true(took < 2500, "the History tab built in %d ms" % took)
	var pages := _pages_of(tab)
	assert_true(pages != null)
	assert_eq(pages.get_tab_count(), 5)
	var titles: Array = []
	for i in 5:
		titles.append(pages.get_tab_title(i))
	assert_eq(titles, ["Franchise", "Retired numbers", "Rivalries", "Storylines", "Hall of Fame and records"])
	var franchise := tab.find_child("Franchise", true, false)
	assert_true(franchise != null and franchise.find_child("TeamPicker", true, false) != null, "the franchise page has a club picker")
	var text := _texts(franchise).to_lower()   # tile labels are drawn in capitals
	assert_true(text.contains("seasons") and text.contains("titles") and text.contains("finals") and text.contains("best season"), "the summary tiles: %s" % text.substr(0, 200))
	assert_true(text.contains("season by season") and text.contains("all-time points leaders"), "the season log and the leaders")
	assert_true(_texts(tab).contains("Hall of Fame"), "the old Hall of Fame page is still in the tab")
	assert_true(tab.find_child("Retired numbers", true, false).get_child_count() == 0, "the heavier pages are not built until opened")


func test_the_club_picker_rebuilds_the_page_for_another_team() -> void:
	_owner_league_with_history()
	var tab := app.build_tab("History")
	host.add_child(tab)
	await frames(2)
	var franchise := tab.find_child("Franchise", true, false)
	var picker := franchise.find_child("TeamPicker", true, false) as FcDropdown
	var teams := app.controller.state.world.teams.ids()
	var other: int = teams[3]
	var before := _texts(franchise.find_child("Body", true, false))
	picker.select_value(other)
	picker.chosen.emit(other)
	await frames(2)
	var after := _texts(franchise.find_child("Body", true, false))
	assert_true(after.to_lower().contains("seasons"), "another club's franchise page is built")
	assert_true(before != after, "and it is a different story")


func test_retired_numbers_rivalries_and_storylines_fill_when_opened() -> void:
	_owner_league_with_history()
	var world := app.controller.state.world
	var team_id := app.controller.state.user_team_id
	var year := app.controller.state.current_season
	FcHistoryFixture.retired_player(world, team_id, year - 12, 9, 2200, 910001)   # a franchise legend, retired three seasons ago
	var tab := app.build_tab("History")
	host.add_child(tab)
	await frames(2)
	var pages := _pages_of(tab)
	pages.open(1, true)
	await frames(2)
	var jerseys := tab.find_child("Retired numbers", true, false)
	assert_true(jerseys.find_child("TeamPicker", true, false) != null, "opening the page filled it")
	var number := FcFranchiseHistory.jersey_for(910001)
	assert_true(jerseys.find_child("Jersey_%d" % number, true, false) != null, "the legend's #%d card is there" % number)
	assert_true(_texts(jerseys).contains("Number910001") or _texts(jerseys).contains("Legend"), "with his name")
	pages.open(2, true)
	await frames(2)
	var rivalries := tab.find_child("Rivalries", true, false)
	assert_true(rivalries.find_child("TeamPicker", true, false) != null)
	var rtext := _texts(rivalries)
	assert_true(rtext.contains("Teams become rivals") and (rtext.contains("How it grew") or rtext.contains("No rivalries yet")), "rivalries or the reason there are none")
	pages.open(3, true)
	await frames(2)
	var stories := tab.find_child("Storylines", true, false)
	var scope := stories.find_child("StoryScope", true, false) as FcChoiceGroup
	assert_true(scope != null)
	assert_true(stories.find_child("Body", true, false).get_child_count() > 0, "storylines (or the explanation) are listed")
	scope.button_for("team").pressed.emit()
	await frames(2)
	assert_true(stories.find_child("Body", true, false).get_child_count() > 0, "the club scope also answers")
	var mine := FcStorylines.new(world, app.controller.league_id, year).for_team(team_id, 14)
	assert_eq(stories.find_child("Body", true, false).get_child_count(), maxi(1, mine.size()), "one row per story of the club (or the explanation)")


func test_the_dashboard_still_builds_every_tab() -> void:
	_owner_league_with_history()
	app.show_dashboard()
	await frames(3)
	assert_true(app._tabs != null and app._tabs.get_tab_count() == FcApp.TAB_NAMES.size())


func test_the_career_hub_shows_league_storylines() -> void:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var strong := ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]
	for key in spec["attributes"]:
		spec["attributes"][key] = 70 if strong.has(key) else 25
	assert_true(app.on_create_career(spec, 51))
	assert_true(app.career.join_team(app.career.state.world.teams.ids()[2])["ok"])
	var pending := app.career.pending_event()
	if not pending.is_empty():
		app.career.answer_event(pending["choices"][0]["key"])
	app.show_career_hub()
	await frames(2)
	var panel := app.find_child("LeagueStorylines", true, false)
	assert_true(panel != null, "the Career hub has a league storylines panel")
	assert_true(_texts(panel).contains("League storylines") and _texts(panel).contains("Nothing yet"), "a new league has none yet, and says so")
