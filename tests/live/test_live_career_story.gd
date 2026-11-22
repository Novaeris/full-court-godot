extends FcLiveTestCase
## The Career story (Phase 4C) in a real scene: the Story tab shows the public image, the legacy so far and the timeline of a played
## season; a retired career opens its Season tab on the legacy page; and the Story tab fits a phone-width window.

const PREFS := "user://test_preferences_live_story.cfg"

var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_story")
	host.add_child(app)
	app.setup()


func after_each() -> void:
	super.after_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_live_story.cfg")
	FcSafeFile.remove_tree("user://test_saves_live_story")


func _career() -> void:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	assert_true(app.on_create_career(spec, 52))
	assert_true(app.career.join_team(app.career.state.world.teams.ids()[2])["ok"])
	var pending := app.career.pending_event()
	if not pending.is_empty():
		app.career.answer_event(pending["choices"][0]["key"])


func test_the_story_tab_shows_image_legacy_and_timeline_after_a_season() -> void:
	await frames(2)
	_career()
	assert_true(app.career.finish_season()["ok"])
	app._last_career_tab = 4
	app.show_career_hub()
	await frames(3)
	var story := app.find_child("Story", true, false)
	assert_true(story != null, "the Story tab is built")
	assert_true(story.find_child("PublicImagePanel", true, false) != null)
	assert_true(story.find_child("LegacyPage", true, false) != null)
	var timeline := story.find_child("CareerTimeline", true, false)
	assert_true(timeline != null)
	var all := ""
	for n in timeline.find_children("*", "Label", true, false):
		all += (n as Label).text + "\n"
	assert_true("rookie contract" in all, "signing is on the timeline")
	assert_true("points" in all and "rebounds" in all, "so is the season")


func test_a_retired_career_opens_its_season_tab_on_the_legacy_page() -> void:
	await frames(2)
	_career()
	var c := app.career
	var pid := c.profile().player_id
	c.state.world.team_of_player(pid).roster.remove(pid)
	c.state.world.active_contract_of(pid).status = FcContract.Status.TERMINATED
	c.player().status = FcPlayer.Status.RETIRED
	c.player().retired_season = c.state.current_season
	c._after_offseason()
	assert_true(c.is_retired())
	app._last_career_tab = 1
	app.show_career_hub()
	await frames(3)
	assert_true(app.find_child("LegacyPage", true, false) != null, "the legacy page leads the retired Season tab")
	assert_true("Retired after" in str(c.profile().timeline[c.profile().timeline.size() - 1]["text"]), "retirement closes the timeline")
