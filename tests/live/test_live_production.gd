extends FcLiveTestCase
## Broadcast pass 2, M7 in a real scene: the replay screen's shows (pregame, halftime, postgame, championship) draw their segments over the stage, take
## the replay to the right moment and put it back exactly; the highlights segment runs the reel; the HUD hides the show; Full Court Tonight opens from
## the Owner's News tab and walks through its segments, and says so when there is nothing to talk about yet.

const PREFS := "user://test_preferences_live_production.cfg"

var game: Dictionary = {}
var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	var world := FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ratings := FcPlayerRatings.load_default()
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(12))
	game = {"box": box, "log": sim.recorder}


func after_each() -> void:
	DirAccess.remove_absolute(PREFS)
	FcSafeFile.remove_tree("user://test_saves_live_production")
	super.after_each()


func _screen() -> FcReplayScreen:
	host.size = Vector2(1400, 1000)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1400, 980)
	host.add_child(screen)
	return screen


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func test_the_show_buttons_belong_to_the_replay_mode() -> void:
	var screen := await _screen()
	await frames(2)
	for id in ["pregame", "halftime", "postgame"]:
		assert_true(screen.tools.show_buttons[id].is_visible_in_tree(), id)
	assert_true(not screen.tools.championship_button.is_visible_in_tree(), "only for the game that decided a title")
	screen.set_mode("broadcast")
	assert_true(not screen.tools.show_buttons["postgame"].is_visible_in_tree())
	screen.set_title_context({"series_label": "Finals: A 4, B 1"})
	screen.set_mode("replay")
	assert_true(screen.tools.championship_button.is_visible_in_tree())


func test_a_show_goes_to_its_moment_and_the_replay_comes_back_exactly() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 50, false)
	screen.set_speed(2.0)
	var before := screen.state.snapshot().slice(0, 3)
	screen.start_show("postgame")
	assert_true(screen.is_show() and screen.show_panel.visible and not screen.is_playing())
	assert_eq(screen.current_index(), screen.model.size() - 1, "postgame is at the final event")
	assert_true(screen.show_panel.summary().contains("Final"), screen.show_panel.summary())
	screen.start_show("halftime")
	assert_eq(screen.current_index(), FcProductionPlan.halftime_index(screen.timeline), "switching shows goes to the half")
	assert_true(screen.show_panel.summary().contains("Halftime"))
	screen.start_show("pregame")
	assert_eq(screen.current_index(), screen.model.start_index())
	screen.end_show()
	assert_true(not screen.is_show() and not screen.show_panel.visible)
	assert_eq(screen.state.snapshot().slice(0, 3), before, "position, play state and speed are back exactly, whichever shows ran")


func test_play_and_the_hud_close_or_hide_the_show() -> void:
	var screen := await _screen()
	await frames(2)
	screen.start_show("postgame")
	screen.set_hud("hidden")
	assert_true(not screen.show_panel.visible, "a hidden HUD hides the show")
	screen.set_hud("full")
	assert_true(screen.show_panel.visible)
	screen.toggle_play()
	assert_true(not screen.is_show() and not screen.is_playing(), "Play closes the show without starting the replay")
	screen.start_show("postgame")
	screen.show_panel.close()
	assert_true(not screen.is_show(), "the panel's Close ends the show")


func test_the_highlights_segment_runs_the_reel() -> void:
	var screen := await _screen()
	await frames(2)
	screen.seek(screen.model.start_index() + 30, false)
	screen.start_show("postgame")
	var refs: Array = []
	while screen.show_panel.current_segment()["type"] != "highlights":
		screen.show_panel.next()
	refs = screen.show_panel.current_segment()["facts"]["refs"]
	assert_true(not refs.is_empty())
	assert_true(_find_button(screen.show_panel, "Play the highlight reel") != null, "the segment offers the reel")
	screen.show_panel.reel_requested.emit(refs)
	assert_true(screen.is_reel() and not screen.is_show(), "the show hands over to the reel")
	screen.end_reel()


func test_the_championship_presentation_uses_the_series_label() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_title_context({"series_label": "Finals: Houston 4, Mexico City 2"})
	screen.start_show("championship")
	assert_true(screen.show_panel.summary().contains("champions") and screen.show_panel.summary().contains("Finals: Houston 4, Mexico City 2"), screen.show_panel.summary())
	screen.end_show()


func test_every_show_segment_renders_on_the_screen() -> void:
	var screen := await _screen()
	await frames(2)
	for id in ["pregame", "halftime", "postgame"]:
		screen.start_show(id)
		for k in screen.show_panel.segment_count():
			assert_true(screen.show_panel.summary() != "", "%s segment %d draws" % [id, k])
			await frames(1)
			screen.show_panel.next()
		screen.end_show()


func _owner_app() -> void:
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_production")
	host.add_child(app)
	app.setup()


func test_the_news_tab_opens_full_court_tonight_and_it_walks_its_segments() -> void:
	_owner_app()
	await frames(2)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Tonight"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	app.controller.advance_days(21)
	var tab: Control = app.build_tab("News")
	host.add_child(tab)
	var button := _find_button(tab, "Full Court Tonight")
	assert_true(button != null, "the News tab offers the show")
	button.pressed.emit()
	await frames(3)
	var panel := app.find_child("TonightPanel", true, false) as FcProductionPanel
	assert_true(panel != null and panel.visible)
	assert_eq(panel.segment_count(), FcProductionTemplate.segments(FcProductionTemplate.load_template("full_court_tonight")).size())
	assert_true(panel.summary().contains("headlines"), panel.summary())
	for k in panel.segment_count():
		assert_true(panel.summary() != "")
		panel.next()
	panel.close()
	await frames(2)
	assert_eq(app.host.modals.count(), 0, "closing the panel closes the dialog")


func test_full_court_tonight_before_any_game_says_so() -> void:
	_owner_app()
	await frames(2)
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "7", "name": "Fresh"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	await frames(2)
	assert_eq(FcTonight.plan_for(app.controller), {})
	FcTonight.open(app, app.controller)
	await frames(2)
	assert_eq(app.host.modals.count(), 1, "a notice, not a broken screen")
	assert_true(app.find_child("TonightPanel", true, false) == null)
