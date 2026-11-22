extends FcTestCase
## Career Mode phase 4C: the legacy summary (FcLegacy, data/career/legacy.json). Exact numbers from hand-built careers.

var w: FcWorld
var lid: int
var t: Array


func before_each() -> void:
	var f := FcHistoryFixture.league(77)
	w = f["world"]
	lid = f["league_id"]
	t = f["teams"]


func _profile(player_id: int, seasons: int) -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = player_id
	for i in seasons:
		p.history.append({"year": 2000 + i})
	return p


func test_the_weights_add_to_one_and_every_pillar_has_a_label_and_lines() -> void:
	var sum := 0.0
	for key in FcLegacy.rules()["weights"]:
		sum += float(FcLegacy.rules()["weights"][key])
	assert_true(absf(sum - 1.0) < 0.0001)
	for key in FcLegacy.PILLARS:
		assert_true(FcLegacy.rules()["labels"].has(key))
		assert_eq((FcLegacy.rules()["lines"][key] as Array).size(), 4)


func test_lines_and_tiers_follow_the_data_thresholds() -> void:
	assert_eq(FcLegacy.line_for("honours", 0), "No major honours")
	assert_eq(FcLegacy.line_for("honours", 24), "No major honours")
	assert_eq(FcLegacy.line_for("honours", 25), "A few honours")
	assert_eq(FcLegacy.line_for("honours", 100), "A trophy case that fills a wall")
	assert_eq(FcLegacy.tier_for(0), "Passing Through")
	assert_eq(FcLegacy.tier_for(35), "Solid Pro")
	assert_eq(FcLegacy.tier_for(100), "All-Time Great")


func test_the_total_is_the_weighted_sum_and_stays_in_range() -> void:
	assert_eq(FcLegacy.total({"production": 100, "honours": 100, "longevity": 100, "public_image": 100, "character": 100}), 100)
	assert_eq(FcLegacy.total({}), 0)
	assert_eq(FcLegacy.total({"production": 100}), 35)
	assert_eq(FcLegacy.total({"honours": 100, "character": 100}), 35)


func test_pillars_measure_longevity_image_and_character_exactly() -> void:
	var p := _profile(900100, 9)
	p.fan_favor = 80
	p.media_image = 60
	p.hype = 20
	p.tags = ["mentor", "community", "controversial"]
	var s := FcLegacy.pillars(p, FcRecords.new(w, lid))
	assert_eq(s["longevity"], 50, "9 of 18 seasons")
	assert_eq(s["public_image"], 61, "80*0.45 + 60*0.35 + 20*0.2")
	assert_eq(s["character"], 35, "two good tags (50) minus one bad (15)")
	assert_eq(s["production"], 0, "no recorded seasons in the league")
	assert_eq(s["honours"], 0)


func test_a_legend_is_a_hall_of_famer_with_a_retired_number() -> void:
	FcHistoryFixture.retired_player(w, t[0], 2000, 12, 2400, 900200)
	var p := _profile(900200, 12)
	var s := FcLegacy.summary(p, w, lid, 2020, true)
	assert_eq(s["hall_of_fame"], "inducted")
	assert_eq(s["inducted_year"], 2013, "two seasons after his last (2011)")
	assert_eq(s["retired_number"]["team_id"], t[0])
	assert_true("Hall of Fame" in str(s["narrative"]) and "retired" in str(s["narrative"]))
	assert_eq((s["pillars"] as Array).size(), 5)
	assert_true(int(s["total"]) > 0 and str(s["tier"]) != "")


func test_a_weak_short_career_gets_no_honours_and_a_low_tier() -> void:
	FcHistoryFixture.retired_player(w, t[0], 2000, 2, 100, 900300)
	var s := FcLegacy.summary(_profile(900300, 2), w, lid, 2020, true)
	assert_eq(s["hall_of_fame"], "no")
	assert_true(s["retired_number"].is_empty())
	assert_eq(s["tier"], "Passing Through")


func test_a_running_career_with_a_hall_of_fame_resume_is_eligible_not_inducted() -> void:
	var p := FcHistoryFixture.retired_player(w, t[0], 2000, 12, 2400, 900400)
	p.status = FcPlayer.Status.ACTIVE
	var s := FcLegacy.summary(_profile(900400, 12), w, lid, 2012, false)
	assert_eq(s["hall_of_fame"], "eligible")
	assert_true(s["retired_number"].is_empty(), "numbers are retired only after retirement")


func test_key_moments_come_from_the_timeline() -> void:
	FcHistoryFixture.retired_player(w, t[0], 2000, 3, 800, 900500)
	var p := _profile(900500, 3)
	FcCareerTimeline.add(p, 2000, "season", "A season")
	FcCareerTimeline.add(p, 2001, "title", "Won the championship")
	var s := FcLegacy.summary(p, w, lid, 2010, true)
	assert_eq(s["moments"].size(), 2)
	assert_eq(str(s["moments"][0]["kind"]), "season", "in the order they happened")
