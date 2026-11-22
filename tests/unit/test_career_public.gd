extends FcTestCase
## Career Mode phase 4A: the career timeline and the public image (data/career/media.json). Pure rules plus the controller hooks.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile() -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	return p


func _career(seed_value: int = 71) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("point_forward", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	return c


# --- timeline -----------------------------------------------------------------------------------------------------

func test_the_timeline_adds_in_order_and_ignores_repeats_and_bad_rows() -> void:
	var p := _profile()
	assert_true(FcCareerTimeline.add(p, 2026, "team", "Signed"))
	assert_true(not FcCareerTimeline.add(p, 2026, "team", "Signed"), "the same moment is not added twice")
	assert_true(not FcCareerTimeline.add(p, 2026, "nonsense", "x"), "unknown kinds are refused")
	assert_true(not FcCareerTimeline.add(p, 2026, "team", "   "), "empty text is refused")
	assert_true(FcCareerTimeline.add(p, 2027, "season", "A season"))
	assert_eq(FcCareerTimeline.entries(p).size(), 2)
	assert_eq(FcCareerTimeline.years(p), [2026, 2027])
	assert_eq(FcCareerTimeline.by_year(p)[2027].size(), 1)


func test_the_timeline_keeps_only_the_newest_rows() -> void:
	var p := _profile()
	for i in FcCareerTimeline.LIMIT + 20:
		FcCareerTimeline.add(p, 2000 + i, "season", "Season %d" % i)
	assert_eq(p.timeline.size(), FcCareerTimeline.LIMIT)
	assert_eq(str(p.timeline[0]["text"]), "Season 20", "the oldest were dropped")


func test_key_moments_prefer_weight_then_recency_and_keep_the_order_they_happened() -> void:
	var p := _profile()
	FcCareerTimeline.add(p, 2026, "season", "s1")
	FcCareerTimeline.add(p, 2026, "title", "won it")
	FcCareerTimeline.add(p, 2027, "season", "s2")
	FcCareerTimeline.add(p, 2027, "award", "mvp")
	FcCareerTimeline.add(p, 2028, "level", "lvl")
	var top := FcCareerTimeline.key_moments(p, 2)
	assert_eq(top.size(), 2)
	assert_eq(str(top[0]["text"]), "won it")
	assert_eq(str(top[1]["text"]), "mvp")
	assert_eq(FcCareerTimeline.key_moments(p, 99).size(), 5, "never more than exist")


# --- public image rules -------------------------------------------------------------------------------------------

func test_a_new_profile_starts_at_the_data_image_and_sponsors_pay_the_base() -> void:
	var p := _profile()
	FcCareerMedia.start(p)
	assert_eq([p.fan_favor, p.media_image, p.hype], [50, 50, 0])
	assert_eq(FcCareerMedia.sponsor_multiplier(p), 1.0)


func test_apply_clamps_to_0_100_and_reports_the_real_change() -> void:
	var p := _profile()
	var changes := FcCareerMedia.apply(p, {"fan_favor": 70, "hype": -5, "media_image": 0, "ignored": 9})
	assert_eq(p.fan_favor, 100)
	assert_eq(changes, {"fan_favor": 50}, "only what actually moved")
	assert_eq(p.hype, 0)


func test_notable_games_have_exact_thresholds() -> void:
	assert_eq(FcCareerMedia.notable_kind({"points": 34, "rebounds": 5, "assists": 5}), "")
	assert_eq(FcCareerMedia.notable_kind({"points": 35, "rebounds": 5, "assists": 5}), "notable_points")
	assert_eq(FcCareerMedia.notable_kind({"points": 12, "rebounds": 10, "assists": 10}), "triple_double")
	assert_eq(FcCareerMedia.notable_kind({"points": 12, "rebounds": 10, "assists": 9}), "")


func test_a_big_game_makes_hype_fans_and_a_headline_an_ordinary_one_does_nothing() -> void:
	var p := _profile()
	assert_true(FcCareerMedia.on_game(p, {"points": 20, "rebounds": 3, "assists": 3}, 2026, "Maya Okoro", "Hawks", "Owls").is_empty())
	var r := FcCareerMedia.on_game(p, {"points": 41, "rebounds": 3, "assists": 3}, 2026, "Maya Okoro", "Hawks", "Owls")
	assert_eq(r["kind"], "notable_points")
	assert_eq([p.hype, p.fan_favor], [4, 51])
	assert_true("Maya Okoro" in str(r["headline"]) and "{" not in str(r["headline"]), "the template was filled")
	assert_eq(p.headlines.size(), 1)
	FcCareerMedia.on_game(p, {"points": 41, "rebounds": 3, "assists": 3}, 2026, "Maya Okoro", "Hawks", "Owls")
	assert_eq(p.headlines.size(), 1, "the same headline is not kept twice")


func test_headlines_are_deterministic_and_capped() -> void:
	var facts := {"name": "A", "team": "T", "opponent": "O", "points": 40, "award": ""}
	assert_eq(FcCareerMedia.headline("notable_points", 2026, facts), FcCareerMedia.headline("notable_points", 2026, facts))
	var p := _profile()
	for i in 30:
		FcCareerMedia.add_headline(p, 2000 + i, "h%d" % i)
	assert_eq(p.headlines.size(), 12)
	assert_eq(str(p.headlines[11]["text"]), "h29", "newest last")


func test_a_winning_title_season_lifts_the_image_and_is_applied_once() -> void:
	var p := _profile()
	p.hype = 50
	var ctx := {"win_pct": 0.8, "points": 25.0, "champion": true}
	var r := FcCareerMedia.after_season(p, 2026, ctx)
	# fan: (0.8-0.5)*30 = 9, +6 title, +2 star, drift toward 50 is 0 at 50 -> 17; hype: 50 -> 35 after 30% fade, +8 +3 -> 46
	assert_eq(r["fan_favor"], 17)
	assert_eq(p.fan_favor, 67)
	assert_eq(p.hype, 46)
	assert_true(FcCareerMedia.after_season(p, 2026, ctx).is_empty(), "the same season never applies twice")
	assert_eq(p.fan_favor, 67)


func test_the_crowd_forgets_and_tags_keep_nudging() -> void:
	var p := _profile()
	p.fan_favor = 80
	p.tags = ["controversial"]
	var r := FcCareerMedia.after_season(p, 2026, {"win_pct": 0.5, "points": 10.0, "champion": false})
	assert_eq(p.fan_favor, 79, "drifts one step back toward 50")
	assert_eq(p.media_image, 48, "controversial costs press standing")
	assert_eq(p.hype, 2)
	assert_eq(r["media_image"], -2)


func test_sponsors_pay_more_for_fans_and_hype_within_the_limits() -> void:
	var p := _profile()
	p.fan_favor = 100
	p.hype = 100
	assert_eq(FcCareerMedia.sponsor_multiplier(p), 1.5, "capped")
	p.fan_favor = 0
	p.hype = 0
	assert_eq(FcCareerMedia.sponsor_multiplier(p), 0.75, "floored")
	p.fan_favor = 60
	p.hype = 10
	assert_true(absf(FcCareerMedia.sponsor_multiplier(p) - 1.1) < 0.0001)


func test_labels_come_from_the_data() -> void:
	assert_eq(FcCareerMedia.label("fan_favor", 0), "Despised")
	assert_eq(FcCareerMedia.label("fan_favor", 72), "Beloved")
	assert_eq(FcCareerMedia.label("hype", 90), "Phenomenon")
	assert_eq(FcCareerMedia.label("media_image", 50), "Neutral")


# --- saving -------------------------------------------------------------------------------------------------------

func test_the_public_image_and_timeline_survive_a_json_round_trip() -> void:
	var p := _profile()
	p.fan_favor = 63
	p.media_image = 41
	p.hype = 17
	p.public_year = 2027
	FcCareerMedia.add_headline(p, 2027, "Big night")
	FcCareerTimeline.add(p, 2027, "title", "Won it")
	var again := FcCareerProfile.from_dict(FcChecks.parse_json(JSON.stringify(p.to_dict())))
	assert_eq([again.fan_favor, again.media_image, again.hype, again.public_year], [63, 41, 17, 2027])
	assert_eq(again.headlines, p.headlines)
	assert_eq(again.timeline, p.timeline)
	assert_true(again.validate().is_empty(), str(again.validate()))
	p.hype = 101
	assert_true(not p.validate().is_empty(), "out-of-range image is invalid")


func test_a_version_three_career_migrates_with_a_timeline_built_from_its_history() -> void:
	var payload := {"career_profiles": [{"profile_id": "fcp_0123456789abcdef", "history": [{"year": 2026, "games": 70, "points": 18}],
		"decisions": [{"year": 2027, "key": "mentor", "choice": "yes"}]}, {"profile_id": "fcp_1", "timeline": [{"year": 1, "kind": "team", "text": "kept"}]}]}
	var r := FcSaveMigrator.new().migrate(payload, 3, 4)
	assert_true(r["ok"], r["message"])
	var rows: Array = r["payload"]["career_profiles"]
	assert_eq([rows[0]["fan_favor"], rows[0]["media_image"], rows[0]["hype"]], [50, 50, 0])
	assert_eq(rows[0]["timeline"].size(), 2)
	assert_eq(rows[0]["timeline"][0]["kind"], "season")
	assert_eq(rows[0]["timeline"][1]["kind"], "decision")
	assert_eq(rows[1]["timeline"].size(), 1, "an existing timeline is untouched")
	assert_true(not payload["career_profiles"][0].has("fan_favor"), "the original payload was not edited in place")
	assert_true(FcSaveMigrator.new().migrate({"mode": "owner"}, 3, 4)["ok"], "a payload with no careers migrates")
	var loaded := FcCareerProfile.from_dict(rows[0])
	assert_eq(loaded.timeline.size(), 2)


# --- the controller -----------------------------------------------------------------------------------------------

func test_joining_a_team_and_finishing_a_season_write_the_timeline_and_the_image_once() -> void:
	var c := _career()
	var kinds: Array = []
	for row in c.profile().timeline:
		kinds.append(str(row["kind"]))
	assert_true("team" in kinds, "signing is the first moment")
	var year := c.state.current_season
	var pending := c.pending_event()
	if not pending.is_empty():
		assert_true(c.answer_event(str(pending["choices"][0]["key"]))["ok"])
	var r := c.finish_season()
	assert_true(r["ok"], str(r.get("reason", "")))
	assert_eq(c.profile().public_year, year, "the season's image change was applied")
	var seasons := 0
	for row in c.profile().timeline:
		if str(row["kind"]) == "season" and int(row["year"]) == year:
			seasons += 1
	assert_eq(seasons, 1)
	assert_true(c.profile().validate().is_empty(), str(c.profile().validate()))
