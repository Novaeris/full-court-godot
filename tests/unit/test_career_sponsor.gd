extends FcTestCase
## Career Mode: sponsorships (money for reputation, with a controversial option) and cosmetic spending.

var defs: FcDefinitionSet
const NAMES := ["Alpha Foods", "Beta Shoes", "Gamma Energy", "Delta Bank", "Epsilon Cars"]


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile(reputation: int = 20) -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	p.reputation = reputation
	p.appearance = {"skin": "tone_3", "hair": "short", "face": "face_1", "facial_hair": "none"}
	return p


func _career(seed_value: int = 111) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	return c


func test_nobody_sponsors_an_unknown_player_and_offers_scale_with_reputation() -> void:
	assert_eq(FcCareerRules.sponsor_offers(_profile(4), 2026, FcRng.new(1), NAMES), [])
	assert_eq(FcCareerRules.sponsor_offers(_profile(20), 2026, FcRng.new(1), []), [])
	var small := FcCareerRules.sponsor_offers(_profile(10), 2026, FcRng.new(1), NAMES)
	var big := FcCareerRules.sponsor_offers(_profile(80), 2026, FcRng.new(1), NAMES)
	assert_eq(small.size(), 3)
	assert_eq(big[0]["edge"], "safe")
	assert_eq(big[2]["edge"], "bold")
	assert_true(big[0]["amount"] > small[0]["amount"], "a bigger name earns more")
	assert_true(big[2]["amount"] > big[0]["amount"], "the bold brand pays more")
	assert_true(big[2]["years"] <= 2 and big[0]["years"] >= 2, "bold deals are short")
	assert_eq(FcCareerRules.sponsor_offers(_profile(80), 2026, FcRng.new(1), NAMES), big, "seeded: the same offers every time")
	var names := {}
	for o in big:
		names[o["sponsor"]] = true
	assert_eq(names.size(), 3, "three different brands")


func test_one_deal_at_a_time_paid_each_season_until_it_runs_out() -> void:
	var p := _profile(20)
	var offers := FcCareerRules.sponsor_offers(p, 2026, FcRng.new(2), NAMES)
	assert_true(FcCareerRules.sign_sponsor(p, offers[0])["ok"])
	assert_true(not FcCareerRules.sign_sponsor(p, offers[1])["ok"], "one sponsor at a time")
	var years := int(p.sponsor_deal["years_left"])
	var amount := int(p.sponsor_deal["amount"])
	for i in years:
		var paid := FcCareerRules.pay_sponsor(p, 2026 + i)
		assert_eq(paid["paid"], amount)
	assert_eq(p.currency, amount * years)
	assert_eq(p.sponsor_deal, {}, "the deal has run out")
	assert_eq(FcCareerRules.pay_sponsor(p, 2040)["paid"], 0, "nothing without a deal")
	assert_true(FcCareerRules.sign_sponsor(p, offers[1])["ok"], "free to sign another")


func test_a_season_is_paid_only_once() -> void:
	var p := _profile(20)
	FcCareerRules.sign_sponsor(p, {"sponsor": "Alpha Foods", "amount": 500, "years": 3, "edge": "safe"})
	assert_eq(FcCareerRules.pay_sponsor(p, 2026)["paid"], 500)
	assert_eq(FcCareerRules.pay_sponsor(p, 2026)["paid"], 0, "the same season does not pay twice")
	assert_eq(p.currency, 500)
	assert_eq(p.sponsor_deal["years_left"], 2)


func test_a_bold_brand_pays_more_but_costs_reputation_and_chemistry_every_season() -> void:
	var p := _profile(20)
	p.chemistry = 50
	FcCareerRules.sign_sponsor(p, {"sponsor": "Beta Shoes", "amount": 900, "years": 2, "edge": "bold"})
	var result := FcCareerRules.pay_sponsor(p, 2026)
	assert_eq([result["paid"], result["reputation"], result["chemistry"]], [900, -1, -1])
	assert_eq([p.reputation, p.chemistry], [19, 49])
	FcCareerRules.pay_sponsor(p, 2027)
	assert_eq([p.reputation, p.chemistry, p.currency], [18, 48, 1800])
	var low := _profile(0)
	FcCareerRules.sign_sponsor(low, {"sponsor": "Beta Shoes", "amount": 900, "years": 1, "edge": "bold"})
	FcCareerRules.pay_sponsor(low, 2026)
	assert_eq(low.reputation, 0, "reputation never goes below zero")


func test_ending_a_deal_early_costs_reputation() -> void:
	var p := _profile(20)
	assert_true(not FcCareerRules.drop_sponsor(p)["ok"])
	FcCareerRules.sign_sponsor(p, {"sponsor": "Alpha Foods", "amount": 500, "years": 3, "edge": "safe"})
	assert_true(FcCareerRules.drop_sponsor(p)["ok"])
	assert_eq([p.sponsor_deal, p.reputation], [{}, 19])


func test_looks_cost_currency_change_nothing_else_and_are_validated() -> void:
	var p := _profile()
	p.currency = 400
	assert_true(not FcCareerRules.change_appearance(p, "hair", "rainbow")["ok"])
	assert_true(not FcCareerRules.change_appearance(p, "wings", "big")["ok"])
	assert_true(not FcCareerRules.change_appearance(p, "hair", "short")["ok"], "the same look costs nothing and changes nothing")
	assert_eq(p.currency, 400)
	assert_true(FcCareerRules.change_appearance(p, "hair", "afro")["ok"])
	assert_eq([p.currency, p.appearance["hair"]], [400 - FcCareerRules.COSMETIC_COST, "afro"])
	var poor := _profile()
	poor.currency = 10
	var refused := FcCareerRules.change_appearance(poor, "hair", "afro")
	assert_true(not refused["ok"] and "costs" in refused["reason"])
	assert_eq(poor.appearance["hair"], "short")


func test_through_the_career_a_deal_pays_at_season_end_and_everything_saves() -> void:
	var c := _career()
	c.profile().reputation = 30
	var offers := c.sponsor_offers()
	assert_eq(offers.size(), 3)
	assert_true(not c.sign_sponsor("Nobody Inc")["ok"])
	assert_true(c.sign_sponsor(offers[0]["sponsor"])["ok"])
	var amount: int = offers[0]["amount"]
	var cash := c.profile().currency
	var result := c.finish_season()
	assert_true(result["ok"])
	assert_true(c.profile().currency >= cash + amount, "the season's sponsor money arrived (milestones may add more)")
	assert_eq(result["summary"]["sponsor_paid"], amount)
	var before := c.player().attributes.to_dict()
	assert_true(c.change_appearance("skin", "tone_5")["ok"] or c.profile().currency < FcCareerRules.COSMETIC_COST)
	assert_eq(c.player().attributes.to_dict(), before, "a look never changes ability")
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_eq(back.checksum(), c.profile().checksum(), "deal, payment year and look survive saving")
	assert_eq(c.state.validate(), [] as Array[String])
