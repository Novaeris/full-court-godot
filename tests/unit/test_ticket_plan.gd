extends FcTestCase
## Season tickets and promotion nights (Owner Mode ticket plan).


func _game(seed_value: int = 620) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func _parts(g: FcGameController) -> Dictionary:
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var finance := FcFinanceEngine.new(w)
	var scale := finance.price_scale_for(w.rules_of_league(1), w.leagues.get_by_id(1))
	return {"finance": finance, "city": w.cities.get_by_id(team.city_id), "arena": w.arenas.get_by_id(team.arena_id), "scale": scale}


## The user's revenue lines for the season just played, with the given plan.
func _season_with(plan: Dictionary, price_factor: float = 1.0) -> FcFinanceRecord:
	var g := _game()
	var b := g.business()
	b.ticket_price = roundi(b.ticket_price * price_factor)
	b.season_ticket_share = plan.get("share", 0)
	b.promotion_nights = plan.get("nights", 0)
	g.sim_playoffs()
	return FcFinanceEngine.new(g.state.world).record_of(g.state.user_team_id, g.state.current_season)


func test_the_defaults_change_nothing() -> void:
	var b := FcTeamBusiness.new(1)
	assert_eq(b.season_ticket_share, 0)
	assert_eq(b.promotion_nights, 0)
	var g := _game()
	var p := _parts(g)
	var split: Dictionary = p["finance"].ticket_split(g.business(), p["city"], p["arena"], p["scale"], float(g.business().ticket_price))
	assert_eq(split["holders"], 0)
	assert_eq(split["total"], p["finance"].attendance(g.business(), p["city"], p["arena"], p["scale"], float(g.business().ticket_price)), "same crowd as before")


func test_holders_always_come_even_when_demand_is_weak() -> void:
	var g := _game()
	var p := _parts(g)
	var b := g.business()
	b.ticket_price = b.ticket_price * 3   # far too dear: demand collapses
	var without: Dictionary = p["finance"].ticket_split(b, p["city"], p["arena"], p["scale"], float(b.ticket_price))
	b.season_ticket_share = 40
	var with_holders: Dictionary = p["finance"].ticket_split(b, p["city"], p["arena"], p["scale"], float(b.ticket_price))
	assert_true(with_holders["holders"] > 0 and with_holders["total"] > without["total"], "holders fill seats that single buyers would leave empty")
	assert_true(with_holders["total"] <= p["arena"].capacity)


func test_renewal_follows_fan_interest() -> void:
	var g := _game()
	var p := _parts(g)
	var b := g.business()
	b.season_ticket_share = 50
	b.fan_interest = 90
	var happy: int = p["finance"].ticket_split(b, p["city"], p["arena"], p["scale"], float(b.ticket_price))["holders"]
	b.fan_interest = 10
	var sour: int = p["finance"].ticket_split(b, p["city"], p["arena"], p["scale"], float(b.ticket_price))["holders"]
	assert_true(happy > sour)


func test_season_tickets_help_a_weak_gate_and_cost_a_sold_out_arena() -> void:
	# a far too expensive price (weak demand): holders raise ticket revenue
	var weak := _season_with({}, 6.0)
	var weak_with := _season_with({"share": 40}, 6.0)
	assert_true(weak_with.revenue["tickets"] > weak.revenue["tickets"], "holders help when seats would be empty")
	# a sold-out arena: the discount is pure loss
	var full := _season_with({})
	var full_with := _season_with({"share": 40})
	assert_true(full_with.revenue["tickets"] < full.revenue["tickets"], "the discount costs money when the arena sells out anyway")


func test_promotion_nights_fill_the_arena_cost_money_and_lift_interest() -> void:
	var plain := _season_with({}, 2.0)
	var promoted := _season_with({"nights": 8}, 2.0)
	assert_true(promoted.average_attendance > plain.average_attendance, "fuller arena")
	assert_true(promoted.expenses["promotions"] > 0 and plain.expenses["promotions"] == 0)
	assert_true(promoted.revenue["concessions"] > plain.revenue["concessions"], "more fans buy more food")
	assert_true(promoted.fan_interest_end >= plain.fan_interest_end, "the nights bring in new fans")
	assert_true(promoted.validate().is_empty())


func test_the_controller_validates_the_plan_and_previews_it() -> void:
	var g := _game()
	assert_true(not g.set_season_ticket_share(61) and not g.set_season_ticket_share(-1))
	assert_true(not g.set_promotion_nights(11) and not g.set_promotion_nights(-1))
	assert_true(g.set_season_ticket_share(30) and g.set_promotion_nights(4))
	var preview := g.ticket_plan_preview()
	assert_true(preview["holders"] > 0 and preview["season_price"] < g.business().ticket_price and preview["promo_price"] < preview["season_price"])
	assert_true(preview["total"] <= preview["capacity"])


func test_the_plan_survives_saving_and_old_saves_have_none() -> void:
	var b := FcTeamBusiness.new(3)
	b.season_ticket_share = 35
	b.promotion_nights = 6
	var back := FcTeamBusiness.from_dict(b.to_dict())
	assert_eq(back.season_ticket_share, 35)
	assert_eq(back.promotion_nights, 6)
	var old := FcTeamBusiness.from_dict({"id": 3})
	assert_eq(old.season_ticket_share, 0)
	assert_eq(old.promotion_nights, 0)
	var rec := FcFinanceRecord.from_dict(FcFinanceRecord.new(5).to_dict())
	assert_eq(rec.expenses["promotions"], 0)
