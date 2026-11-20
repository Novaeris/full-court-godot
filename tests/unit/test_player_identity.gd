extends FcTestCase
## Consistent Player Visual Identity (D-050, Phase 7). One player must look the same wherever he appears (roster, profile, card, post-game,
## trade, comparison, showcase). The resolver (FcPlayerVisual) must be deterministic and shared, must never use game RNG, and must never
## modify player data. Also: the tiers, the style summary, the presentation adapters and the profile view.

const PREFS := "user://test_preferences_identity.cfg"
const DYNASTY := "user://test_dynasty_identity"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_identity.cfg")
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_identity")
	FcDynastyFixture.wipe()


func _app() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_identity")
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func _dynasty() -> void:
	_app()
	FcSafeFile.remove_tree(DYNASTY)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Identity Kings", "IDK"))


func _owner() -> void:
	_app()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Identity League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(20)


func _subject(key: String = "owner_player:1", extra: Dictionary = {}) -> Dictionary:
	var s := FcPlayerPresentation.subject(key, "Maya Okoro", {"name": "Harbor Kings", "abbreviation": "HBK", "primary": "#1F3A5F", "secondary": "#C8A951"}, 11)
	s.merge(extra, true)
	return s


func _roster_ids(world: FcWorld) -> Array:
	return world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


# --- the hash and determinism --------------------------------------------------------------------------------------------------

func test_the_hash_is_pinned_so_a_look_never_changes_between_versions() -> void:
	assert_eq(FcPlayerVisual.fnv1a(""), 2166136261)
	assert_eq(FcPlayerVisual.fnv1a("a"), 3826002220)
	assert_eq(FcPlayerVisual.fnv1a("owner_player:1"), 1497126041)
	assert_eq(FcPlayerVisual.fnv1a("dynasty_player:test_alpha"), 4224576206)
	assert_eq(FcPlayerVisual.fnv1a("career_player:7"), 3484920258)


func test_the_same_subject_always_gives_the_same_visual() -> void:
	var first := FcPlayerVisual.resolve(_subject())
	for i in 20:
		assert_eq(FcPlayerVisual.resolve(_subject()), first, "call %d" % i)
	assert_eq(first["key"], "owner_player:1")
	assert_eq(first["monogram"], "MO")
	assert_eq(first["tier"], FcPlayerVisual.TIER_PROCEDURAL)


func test_the_look_is_pinned_for_a_known_player() -> void:
	# golden values: if these change, every existing player's face changed (a visible regression, or a deliberate redesign)
	var v := FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:1", "X"))
	var id: Dictionary = v["identity"]
	var again := FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:1", "Totally Different Name"))
	assert_eq(again["identity"], id, "the name does not affect the face; the key does")
	assert_true(id["skin"] in FcPlayerVisual.FALLBACK_OPTIONS["skin"] and id["hair"] in FcPlayerVisual.FALLBACK_OPTIONS["hair"])


func test_the_resolver_never_uses_game_random_numbers() -> void:
	seed(1234)
	var expected := randi()
	seed(1234)
	for i in 50:
		FcPlayerVisual.resolve(_subject("owner_player:%d" % i))
	assert_eq(randi(), expected, "the global random stream did not move")
	for path in ["res://src/ui/player/player_visual.gd", "res://src/ui/player/player_figure.gd", "res://src/ui/player/player_portrait.gd", "res://src/ui/player/showcase_stage.gd", "res://src/ui/player/uniform_preview.gd"]:
		var code := FileAccess.get_file_as_string(path)
		for banned in ["FcRng", "randi(", "randf(", "RandomNumberGenerator", "shuffle(", "pick_random"]:
			assert_true(not banned in code, "%s must not contain %s" % [path.get_file(), banned])


func test_resolving_never_modifies_what_it_reads() -> void:
	var subject := _subject("owner_player:3", {"appearance": {"skin": "tone_2", "hair": "fade"}})
	var before := subject.duplicate(true)
	FcPlayerVisual.resolve(subject)
	FcPlayerVisual.monogram_only(subject)
	assert_eq(subject, before, "the subject is untouched")


func test_different_players_look_different() -> void:
	var seen := {}
	for i in 300:
		var id: Dictionary = FcPlayerVisual.resolve(_subject("owner_player:%d" % i))["identity"]
		seen["%s|%s|%s|%s|%s|%s" % [id["skin"], id["hair"], id["face"], id["facial_hair"], id["build"], id["hair_color"].to_html()]] = true
	assert_true(seen.size() >= 250, "300 players gave %d distinct looks" % seen.size())


func test_the_look_uses_the_whole_vocabulary() -> void:
	var skins := {}
	var hairs := {}
	for i in 200:
		var id: Dictionary = FcPlayerVisual.resolve(_subject("k%d" % i))["identity"]
		skins[id["skin"]] = true
		hairs[id["hair"]] = true
	assert_eq(skins.size(), 6, "every skin tone appears")
	assert_eq(hairs.size(), 8, "every hair style appears")


# --- identity versus context ------------------------------------------------------------------------------------------------

func test_changing_team_changes_the_uniform_but_never_the_face() -> void:
	var home := FcPlayerVisual.resolve(_subject())
	var moved := FcPlayerVisual.resolve(_subject("owner_player:1", {"team": {"name": "Sky City", "abbreviation": "SKY", "primary": "#7A1F2B", "secondary": "#FFFFFF"}}))
	assert_eq(moved["identity"], home["identity"], "the same face on a new team")
	assert_true(moved["uniform"]["primary"] != home["uniform"]["primary"], "a new uniform")
	assert_eq(moved["uniform"]["abbreviation"], "SKY")
	var free_agent := FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:1", "Maya Okoro"))
	assert_eq(free_agent["identity"], home["identity"], "and the same face with no team at all")
	assert_true(FcChecks.is_hex_color("#" + free_agent["uniform"]["primary"].to_html(false)), "a palette uniform when there is no branding")


func test_unrelated_game_state_never_changes_the_visual() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var id: int = _roster_ids(world)[0]
	var before: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_player(world, id))["identity"]
	var p: FcPlayer = world.players.get_by_id(id)
	p.attributes.set_value("speed", 31)   # a rating change
	p.injury = "Sprained ankle"
	p.games_out = 5
	app.on_advance(10)   # time passes
	assert_eq(FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_player(world, id))["identity"], before, "ratings, injuries and time do not change a face")


func test_stored_appearance_wins_and_bad_values_fall_back() -> void:
	var stored: Dictionary = FcPlayerVisual.resolve(_subject("career_player:7", {"appearance": {"skin": "tone_6", "hair": "afro", "face": "face_3", "facial_hair": "beard"}}))["identity"]
	assert_eq([stored["skin"], stored["hair"], stored["face"], stored["facial_hair"]], ["tone_6", "afro", "face_3", "beard"], "a Career player keeps the look he built")
	assert_eq(stored["skin_color"], Color(FcPlayerVisual.SKIN_TONES["tone_6"]))
	var bad: Dictionary = FcPlayerVisual.resolve(_subject("career_player:7", {"appearance": {"skin": "purple", "hair": "mohawk"}}))["identity"]
	var derived: Dictionary = FcPlayerVisual.resolve(_subject("career_player:7"))["identity"]
	assert_eq(bad["skin"], derived["skin"], "an unknown stored value falls back to the key's own look")
	assert_eq(bad["hair"], derived["hair"])


# --- one resolver for every screen --------------------------------------------------------------------------------------------------

func test_a_dynasty_player_looks_the_same_on_every_surface() -> void:
	_dynasty()
	var row := app.dynasty.card_detail(FcDynastyFixture.card_id(3))
	var vm := FcPlayerPresentation.from_card(row, app.dynasty)
	var subject: Dictionary = FcPlayerPresentation.subject_for_card(row)
	var expected := FcPlayerVisual.resolve(subject)
	var card := FcCardView.build(row)
	var roster_row := FcPlayerPortrait.new().setup(subject, 36)
	var post_game := FcPlayerPortrait.new().setup(vm["subject"], 56)
	var trade := FcPlayerPortrait.new().setup(subject, 48)
	var comparison := FcPlayerPortrait.new().setup(subject, 72)
	var stage := FcShowcaseStage.new().setup(vm["subject"])
	var profile := FcPlayerProfile.new().setup(vm)
	assert_eq(card.visual, expected, "the card")
	assert_eq(roster_row.visual, expected, "a roster row")
	assert_eq(post_game.visual, expected, "a post-game line")
	assert_eq(trade.visual, expected, "a trade proposal")
	assert_eq(comparison.visual, expected, "a comparison")
	assert_eq(stage.visual, expected, "the showcase stage")
	assert_eq(profile.stage.visual, expected, "the profile")


func test_two_editions_of_one_dynasty_player_share_a_face() -> void:
	_dynasty()
	var base := app.dynasty.card_detail(FcDynastyFixture.card_id(3))
	var allstar := app.dynasty.card_detail(FcDynastyFixture.card_id(3, "allstar"))
	assert_true(not allstar.is_empty() and allstar["card_id"] != base["card_id"], "a second edition exists")
	assert_eq(FcCardView.build(allstar).visual["identity"], FcCardView.build(base).visual["identity"], "same real player, same face")
	var other := app.dynasty.card_detail(FcDynastyFixture.card_id(4))
	assert_true(FcCardView.build(other).visual["identity"] != FcCardView.build(base).visual["identity"], "a different player, a different face")


func test_an_owner_player_looks_the_same_in_the_list_the_profile_and_the_comparison() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var id: int = _roster_ids(world)[1]
	var subject := FcPlayerPresentation.subject_for_player(world, id)
	var vm := FcPlayerPresentation.from_player(world, id, app.controller.state.current_season, app.controller.league_id)
	var expected := FcPlayerVisual.resolve(subject)
	assert_eq(FcPlayerPortrait.new().setup(subject).visual, expected, "the roster list")
	assert_eq(FcPlayerPortrait.new().setup(vm["subject"]).visual, expected, "a comparison built from the view-model")
	assert_eq(FcPlayerProfile.new().setup(vm).stage.visual, expected, "the profile")
	var team: FcTeam = world.team_of_player(id)
	assert_eq(expected["uniform"]["primary"], Color(team.branding.primary_color), "in his team's colours")


func test_building_the_view_models_never_changes_the_game() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var id: int = _roster_ids(world)[0]
	var before := (world.players.get_by_id(id) as FcPlayer).to_dict()
	var counters: Dictionary = app.controller.state.rng.get_state()
	var vm := FcPlayerPresentation.from_player(world, id, app.controller.state.current_season, app.controller.league_id)
	FcPlayerProfile.new().setup(vm)
	FcPlayerVisual.resolve(vm["subject"])
	assert_eq((world.players.get_by_id(id) as FcPlayer).to_dict(), before, "the player is exactly as before")
	assert_eq(app.controller.state.rng.get_state(), counters, "the game's random stream did not move")


# --- tiers, poses ----------------------------------------------------------------------------------------------------------------------

func test_tiers_zero_to_two_exist_and_three_and_four_are_reserved() -> void:
	assert_eq(FcPlayerVisual.IMPLEMENTED_TIERS, [0, 1, 2])
	for i in 100:
		var tier: int = FcPlayerVisual.resolve(_subject("k%d" % i))["tier"]
		assert_true(tier in FcPlayerVisual.IMPLEMENTED_TIERS, "resolve never returns the reserved tiers")
	assert_eq(FcPlayerVisual.monogram_only(_subject())["tier"], FcPlayerVisual.TIER_MONOGRAM)
	assert_true(FcPlayerVisual.TIER_POSE == 3 and FcPlayerVisual.TIER_RENDER == 4, "the slots are named")


func test_readable_art_becomes_a_portrait_and_unreadable_art_falls_back_to_the_figure() -> void:
	var path := "user://test_identity_portrait.png"
	var img := Image.create(40, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(path)
	var with_art := FcPlayerVisual.resolve(_subject("dynasty_player:x", {"art_path": path}))
	assert_eq(with_art["tier"], FcPlayerVisual.TIER_PORTRAIT)
	assert_eq(with_art["art_path"], path)
	assert_true(not with_art["identity"].is_empty(), "the figure description is still there as a fallback")
	var missing := FcPlayerVisual.resolve(_subject("dynasty_player:x", {"art_path": "user://no_such_art.png"}))
	assert_eq(missing["tier"], FcPlayerVisual.TIER_PROCEDURAL, "unreadable art falls back to the figure, not to a blank")
	assert_eq(missing["art_path"], "")
	assert_eq(missing["identity"], with_art["identity"], "and the figure is the same one")
	DirAccess.remove_absolute(path)


func test_only_the_idle_pose_exists_and_others_fall_back() -> void:
	var stage := FcShowcaseStage.new().setup(_subject())
	assert_eq(stage.poses(), ["idle"])
	assert_eq(stage.set_pose("dunk"), "idle", "a pose that does not exist falls back")
	assert_eq(stage.set_pose("idle"), "idle")
	stage.free()


# --- style summary ----------------------------------------------------------------------------------------------------------------------

func test_the_style_summary_names_the_two_strongest_skills() -> void:
	var s := FcPlaystyle.summary({"three": 82.0, "playmaking": 74.0, "rebound": 40.0, "steal": 66.0})
	assert_eq(s["primary"], "Sharpshooter")
	assert_eq(s["secondary"], "Playmaker")
	assert_eq(s["label"], "Sharpshooter / Playmaker")
	assert_eq(FcPlaystyle.summary({"three": 82.0})["secondary"], "", "one standout skill")
	assert_eq(FcPlaystyle.summary({"three": 40.0, "rebound": 30.0})["label"], "Balanced", "nothing reaches the minimum")
	var tie := FcPlaystyle.summary({"three": 70.0, "mid": 70.0})
	assert_eq(tie["primary"], "Mid-range Scorer", "ties are broken by composite name (mid before three), so it is deterministic")


func test_every_style_label_names_a_real_composite_rating() -> void:
	var composites := FcPlayerRatings.load_default().composites
	for key in FcPlaystyle.known_composites():
		assert_true(composites.has(key), "'%s' is a composite the simulation computes" % key)


# --- the view-models and the profile --------------------------------------------------------------------------------------------------------

func test_a_dynasty_card_becomes_a_profile_without_inventing_history() -> void:
	_dynasty()
	var row := app.dynasty.card_detail(FcDynastyFixture.card_id(0))
	var vm := FcPlayerPresentation.from_card(row, app.dynasty)
	assert_eq(vm["mode"], "dynasty")
	assert_eq(vm["attributes"].size(), 28)
	assert_eq((vm["badges"] as Array)[0]["name"], "Catch and Shoot")
	assert_eq(vm["progression"]["kind"], "static", "ratings never change in Dynasty")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_eq(profile.tab_ids(), ["overview", "attributes", "badges"], "no stats, history or awards tab for a card nobody has played with")
	profile.free()


func test_an_owner_player_has_stats_history_and_a_development_outlook() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = _roster_ids(world)[0]
	var team_id: int = app.controller.state.user_team_id
	# one finished season for him: [season, team, games, seconds, points, ..., offensive rebounds (11), defensive (12), assists (13)]
	world.careers[pid] = [[2025, team_id, 60, 108000, 1200, 0, 0, 0, 0, 0, 0, 120, 300, 240]]
	var vm := FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	assert_eq(vm["mode"], "owner")
	assert_eq(vm["progression"]["kind"], "outlook")
	assert_true(vm["physical"]["height_cm"] > 150 and vm["physical"]["wingspan_cm"] > 150, "physical information")
	var stat_row: Array = vm["stats"]["rows"][0]
	assert_eq(stat_row[0], "2025-26")
	assert_eq(stat_row[2], 60, "games")
	assert_eq(stat_row[3], "30.0", "minutes per game")
	assert_eq(stat_row[4], "20.0", "points per game")
	assert_eq(stat_row[5], "7.0", "rebounds per game")
	assert_eq(stat_row[6], "4.0", "assists per game")
	assert_eq(vm["history"]["rows"][0][3], 1200, "career points that season")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("stats" in profile.tab_ids() and "history" in profile.tab_ids(), "tabs appear because the data exists")
	profile.free()
	var rookie := FcPlayerPresentation.from_player(world, _roster_ids(world)[1], app.controller.state.current_season, app.controller.league_id)
	rookie["stats"]["rows"] = []
	assert_true(not "stats" in FcPlayerProfile.new().setup(rookie).tab_ids(), "and disappear when there is none")


func test_the_career_player_has_level_progress_badges_and_the_built_look() -> void:
	_app()
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	spec["jersey_number"] = 11
	spec["appearance"] = {"skin": "tone_5", "hair": "locs", "face": "face_2", "facial_hair": "stubble"}
	assert_true(app.on_create_career(spec, 4))
	var vm := FcPlayerPresentation.from_career(app.career)
	assert_eq(vm["mode"], "career")
	assert_eq(vm["jersey"], 11)
	assert_eq(vm["progression"]["kind"], "career")
	assert_true(str(vm["archetype"]) != "")
	var look: Dictionary = FcPlayerVisual.resolve(vm["subject"])["identity"]
	assert_eq([look["skin"], look["hair"], look["facial_hair"]], ["tone_5", "locs", "stubble"], "the profile shows the look the player built")
	assert_eq(FcPlayerVisual.resolve(vm["subject"])["uniform"]["number"], 11, "and his jersey number")


func test_profile_tabs_switch_and_hide_what_has_no_data() -> void:
	_dynasty()
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	var profile := FcPlayerProfile.new().setup(vm)
	assert_eq(profile.tabs.current_id, "overview")
	var overview_rows := profile._body.get_child_count()
	profile.show_tab("attributes")
	assert_eq(profile.tabs.current_id, "attributes")
	assert_true(_find(profile._body, ProgressBar).size() >= 28, "a bar for every attribute")
	profile.show_tab("badges")
	assert_true(_find(profile._body, FcStatLine).size() >= 1)
	profile.show_tab("overview")
	assert_eq(profile._body.get_child_count(), overview_rows, "going back rebuilds the same overview")
	var top: Array = profile.top_attributes(3)
	assert_true(top[0]["value"] >= top[1]["value"] and top[1]["value"] >= top[2]["value"], "the strongest attributes, best first")
	profile.free()


func test_the_profile_builds_in_compact_layouts_and_opens_as_a_dialog() -> void:
	_dynasty()
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	var compact := FcPlayerProfile.new().setup(vm, true)
	assert_true(compact.get_child(0) is VBoxContainer, "stage above the text on a phone")
	var wide := FcPlayerProfile.new().setup(vm, false)
	assert_true(wide.get_child(0) is HBoxContainer, "stage beside the text on desktop")
	var modal := FcPlayerProfile.open_modal(app, vm)
	assert_eq(app.host.modals.count(), 1)
	assert_eq(_find(modal, FcShowcaseStage).size(), 1)
	assert_eq(_find(modal, FcUniformPreview).size(), 1)
	compact.free()
	wide.free()


func test_feet_and_inches_are_right() -> void:
	assert_eq(FcPlayerProfile._feet_inches(201), "6'7\"")
	assert_eq(FcPlayerProfile._feet_inches(183), "6'0\"")
	assert_eq(FcPlayerProfile._feet_inches(168), "5'6\"")
