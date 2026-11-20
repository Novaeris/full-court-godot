extends FcTestCase
## Smoke tests for the Dynasty screens: they build with real data and the whole loop can be clicked through the controller the
## way the buttons do. (They prove screens build and behave; how they LOOK needs human eyes in the Godot editor.)

const SAVE_DIR := "user://test_dynasty_ui"

var app: FcApp


func before_each() -> void:
	FcSafeFile.remove_tree(SAVE_DIR)
	FcDynastyFixture.wipe()
	app = FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences.cfg")
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_dynasty_ui")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(SAVE_DIR))
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)


func after_each() -> void:
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
	FcSafeFile.remove_tree(SAVE_DIR)
	FcSafeFile.remove_tree("user://test_saves_dynasty_ui")
	FcDynastyFixture.wipe()


func _text(node: Node) -> String:
	var text := ""
	if node is FcCardFace:
		text += (node as FcCardFace).accessible_text().to_upper() + "
"   # cards are drawn, so their words come from their description
	if node is Label:
		text += (node as Label).text + "\n"
	if node is Button:
		text += "[" + (node as Button).text + "]\n"
	for c in node.get_children():
		text += _text(c)
	return text


func _use_fixture() -> void:
	app.dynasty.catalog = FcDynastyFixture.catalog()


func test_empty_content_shows_onboarding_not_a_crash() -> void:
	app.show_dynasty_home()
	var t := _text(app)
	assert_true("Dynasty needs content first" in t, "explains what to do")
	assert_true("Create team" not in t, "no team can be created without enough content")


func test_every_tab_builds_for_a_new_team() -> void:
	_use_fixture()
	app.dynasty_ui.show_entry()
	assert_true("Start a new Dynasty team" in _text(app), "creation form offered")
	assert_true(app.dynasty_ui.on_create("Harbor Kings", "HBK"), "team created")
	assert_true("Recommended next" in _text(app), "hub shows what to do next")
	for entry in FcDynastyUi.TABS:
		app.dynasty_ui.show_tab(str(entry[0]))
		assert_true(_text(app).length() > 40, "tab %s builds with content" % entry[0])
	app.dynasty_ui.show_tab("collection")
	assert_true("Collection: 15 of 32 cards" in _text(app), "the starter collection is shown")
	app.dynasty_ui.show_tab("lineup")
	assert_true("Lineup is valid" in _text(app), "the automatic lineup is valid")
	app.dynasty_ui.show_tab("market")
	assert_true("Buy" in _text(app), "market lists purchasable cards")


func test_bad_team_details_are_refused_with_a_message() -> void:
	_use_fixture()
	assert_true(not app.dynasty_ui.on_create("", "HBK"), "empty name")
	assert_true("name" in app._message.text, "says why")
	assert_true(not app.dynasty_ui.on_create("Okay", "X"), "abbreviation too short")


func test_the_full_loop_through_the_screens_api() -> void:
	_use_fixture()
	app.dynasty_ui.on_create("Harbor Kings", "HBK")
	var ctl := app.dynasty
	# open a pack and reveal it through the real reveal screen
	var before := ctl.profile().unique_owned()
	var r := ctl.buy_pack("bronze_pack")
	assert_true(r.ok, "pack bought")
	app.dynasty_ui.show_tab("packs")
	FcDynastyScreensPacks.show_reveal(app.dynasty_ui, r.data["opening"])
	assert_true("Click the card" in _text(app), "reveal sequence starts face down")
	var skip := _find_button(app, "Skip animation")
	assert_true(skip != null, "skip is offered")
	skip.pressed.emit()
	assert_true("Pack opened" in _text(app), "results summary after the reveal")
	_find_button(app, "Done").pressed.emit()
	assert_true(ctl.pending_openings().is_empty(), "finishing acknowledges the opening")
	assert_true(ctl.profile().unique_owned() >= before, "cards kept")
	# direct acquisition, duplicates, lineup, game, challenge claim, tournament
	assert_true(ctl.acquire_card(FcDynastyFixture.card_id(25)).ok, "market purchase")
	assert_true(ctl.auto_fill_lineup().ok and ctl.lineup_problems().is_empty(), "lineup ready")
	var game := ctl.play_quick_game("easy")
	assert_true(game.ok, "game played")
	app.dynasty_ui.show_tab("play")
	assert_true("WIN" in _text(app) or "LOSS" in _text(app), "result screen")
	for i in 4:
		ctl.play_quick_game("easy")
	var claimable := ctl.challenge_listing().filter(func(c): return c["completed"] and not c["claimed"])
	if not claimable.is_empty():
		assert_true(ctl.claim_challenge(str(claimable[0]["id"])).ok, "claim a reward")
		assert_true(not ctl.claim_challenge(str(claimable[0]["id"])).ok, "but only once")
	app.dynasty_ui.show_tab("challenges")
	assert_true("Claim reward" in _text(app) or "Claimed" in _text(app), "challenge screen shows claim buttons")
	assert_true(ctl.enter_tournament("test_cup").ok, "tournament entered")
	app.dynasty_ui.show_tab("tournament")
	assert_true("Quarterfinals" in _text(app), "bracket shown")
	var finished := false
	for i in 3:
		if finished:
			break
		var m := ctl.play_tournament_match()
		assert_true(m.ok, "tournament match")
		finished = m.data["finished"]
	app.dynasty_ui.show_tab("season")
	assert_true("Season" in _text(app) and "Milestones" in _text(app), "season screen")
	# save, close, reopen: the progress is still there
	var slot := ctl.session.slot
	var snapshot := ctl.profile().to_dict()
	ctl.close_profile()
	assert_true(ctl.open_profile(slot).ok, "reopen")
	assert_true(ctl.profile().to_dict() == snapshot, "everything survived saving and reopening")


func test_card_detail_shows_real_attributes_and_badges() -> void:
	_use_fixture()
	app.dynasty_ui.on_create("Harbor Kings", "HBK")
	app.dynasty_ui.show_card_detail(FcDynastyFixture.card_id(0))
	assert_eq(app.host.modals.count(), 1, "the card inspector opened")
	var dialog: Node = app.host.modals.top()
	var t := _text(dialog)
	assert_true("Catch and Shoot" in t, "badges listed")
	assert_true("Three-Point Shooting" in t or "three" in t.to_lower(), "attributes listed")


func test_newer_content_release_keeps_owned_cards_visible() -> void:
	_use_fixture()
	app.dynasty_ui.on_create("Harbor Kings", "HBK")
	var ctl := app.dynasty
	var owned := ctl.profile().unique_owned()
	var gone := FcDynastyFixture.card_id(4)
	ctl.catalog._views.erase(gone)
	ctl.catalog.content.cards.erase(gone)
	app.dynasty_ui.show_tab("collection")
	assert_true("UNAVAILABLE" in _text(app), "an owned card the release dropped shows as unavailable")
	assert_eq(ctl.profile().unique_owned(), owned, "and is still owned")
	assert_true(not ctl.lineup_problems().is_empty(), "but cannot be used in a lineup")


func _find_button(node: Node, text: String) -> Button:
	if node is Button and text in (node as Button).text:
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null
