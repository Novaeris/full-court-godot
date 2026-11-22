extends FcTestCase
## Career Mode phase 5 (first slice): decisions with real consequences. Pure, seeded, data-driven.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile(level: int = 1) -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	p.level = level
	return p


func _career(seed_value: int = 61) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("point_forward", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	return c


func test_the_event_data_is_well_formed_and_every_choice_changes_something_or_says_so() -> void:
	assert_true(FcCareerEvents.all().size() >= 18)
	var keys := {}
	for e in FcCareerEvents.all():
		assert_true(not keys.has(e["key"]), "unique key %s" % e["key"])
		keys[e["key"]] = true
		assert_true(e["choices"].size() >= 2, "%s offers a real choice" % e["key"])
		var choice_keys := {}
		for c in e["choices"]:
			assert_true(not choice_keys.has(c["key"]))
			choice_keys[c["key"]] = true
			for field in c["effects"]:
				assert_true(field in FcCareerEvents.EFFECT_KEYS, "%s uses a known effect (%s)" % [e["key"], field])
			assert_true(str(c.get("note", "")) != "", "%s/%s explains itself" % [e["key"], c["key"]])


func test_eligibility_follows_the_level_and_decisions_are_not_repeated_at_once() -> void:
	var p := _profile(1)
	assert_eq(FcCareerEvents.eligible(p, 2026).map(func(e): return e["key"]), ["agent_pitch"])
	p.level = 10
	assert_true(FcCareerEvents.eligible(p, 2026).size() > 1 and FcCareerEvents.eligible(p, 2026).size() < FcCareerEvents.all().size(), "a level-10 rookie meets some situational conditions, not all")
	p.decisions.append({"year": 2026, "key": "agent_pitch", "choice": "loyal"})
	assert_true(not FcCareerEvents.eligible(p, 2027).any(func(e): return e["key"] == "agent_pitch"), "not asked again for 4 seasons")
	assert_true(FcCareerEvents.eligible(p, 2030).any(func(e): return e["key"] == "agent_pitch"), "asked again later")


func test_the_pick_is_seeded_and_empty_when_nothing_qualifies() -> void:
	var p := _profile(10)
	assert_eq(FcCareerEvents.pick(p, 2026, FcRng.new(4)), FcCareerEvents.pick(p, 2026, FcRng.new(4)))
	var seen := {}
	for seed_value in 60:
		seen[FcCareerEvents.pick(p, 2026, FcRng.new(seed_value))] = true
	assert_true(seen.size() >= 4, "different seeds offer different events")
	for e in FcCareerEvents.all():
		p.decisions.append({"year": 2026, "key": e["key"], "choice": "x"})
	assert_eq(FcCareerEvents.pick(p, 2027, FcRng.new(1)), "", "everything was answered recently")


func test_choices_have_real_consequences_and_are_recorded() -> void:
	var p := _profile(3)
	p.reputation = 10
	p.currency = 100
	p.pending_event = "agent_pitch"
	var r := FcCareerEvents.apply_choice(p, "agent_pitch", "flashy", 2026)
	assert_true(r["ok"])
	assert_eq(p.currency, 500)
	assert_eq(p.reputation, 8)
	assert_true(p.tags.has("agent_flashy"))
	assert_eq(p.pending_event, "")
	assert_eq(p.decisions, [{"year": 2026, "key": "agent_pitch", "choice": "flashy"}])
	var q := _profile(3)
	FcCareerEvents.apply_choice(q, "agent_pitch", "loyal", 2026)
	assert_eq(q.reputation, 3)
	assert_true(q.xp >= 40, "XP choices go through the level rules")
	var skills := _profile(3)
	FcCareerEvents.apply_choice(skills, "training_camp", "skills", 2026)
	assert_eq(skills.development_points, 2)
	var film := _profile(3)
	FcCareerEvents.apply_choice(film, "training_camp", "film", 2026)
	assert_eq(film.skill_points, 1)


func test_money_and_reputation_never_go_below_zero_and_bad_answers_change_nothing() -> void:
	var p := _profile(6)
	p.currency = 50
	p.reputation = 1
	FcCareerEvents.apply_choice(p, "charity_event", "host", 2026)
	assert_eq(p.currency, 0, "a donation cannot make the balance negative")
	assert_eq(p.reputation, 7)
	var before := p.checksum()
	assert_true(not FcCareerEvents.apply_choice(p, "charity_event", "bogus", 2026)["ok"])
	assert_true(not FcCareerEvents.apply_choice(p, "nonsense", "x", 2026)["ok"])
	assert_true(not FcCareerEvents.apply_choice(p, "charity_event", "skip", 2026)["ok"], "the same decision cannot be answered twice in a season")
	assert_eq(p.checksum(), before, "refused answers change nothing")
	assert_eq(p.validate(), [] as Array[String])


func test_a_waiting_decision_blocks_play_until_it_is_answered() -> void:
	var c := _career()
	var pending := c.pending_event()
	assert_true(not pending.is_empty() and pending["key"] == "agent_pitch", "level 1 qualifies for the agent decision")
	assert_true(pending["choices"].size() == 3)
	var blocked := c.advance_day()
	assert_true(not blocked["ok"] and "decision" in blocked["reason"])
	assert_true(not c.advance_days(5)["ok"] and not c.finish_season()["ok"])
	assert_true(not c.answer_event("bogus")["ok"])
	var xp := c.profile().xp
	var rep := c.profile().reputation
	assert_true(c.answer_event("loyal")["ok"])
	assert_eq(c.profile().reputation, rep + 3)
	assert_true(c.profile().xp >= xp + 40)
	assert_true(c.pending_event().is_empty())
	assert_true(c.advance_days(3)["ok"], "now the career plays on")
	assert_true(not c.answer_event("loyal")["ok"], "nothing left to decide")


func test_a_new_season_brings_a_new_decision_and_everything_survives_saving() -> void:
	var c := _career(62)
	c.answer_event("none")
	c.finish_season()
	var pending := c.pending_event()
	assert_true(not pending.is_empty(), "the new season starts with a decision")
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_eq(back.pending_event, c.profile().pending_event)
	assert_eq(back.tags, c.profile().tags)
	assert_eq(back.decisions, c.profile().decisions)
	assert_eq(back.checksum(), c.profile().checksum())
	assert_eq(c.state.validate(), [] as Array[String])


func test_the_same_career_gets_the_same_decisions() -> void:
	var a := _career(63)
	var b := _career(63)
	for i in 3:
		assert_eq(a.pending_event().get("key", ""), b.pending_event().get("key", ""))
		a.answer_event(a.pending_event()["choices"][0]["key"])
		b.answer_event(b.pending_event()["choices"][0]["key"])
		a.finish_season()
		b.finish_season()
	assert_eq(a.profile().checksum(), b.profile().checksum(), "deterministic")


# --- phase 4B: situational decisions ----------------------------------------------------------------------------

func test_the_event_data_passes_its_own_validator() -> void:
	assert_eq(FcCareerEvents.validate(), [])


func test_conditions_gate_events_by_level_tags_image_trust_and_rival() -> void:
	var p := _profile(1)
	assert_true(FcCareerEvents.meets(p, {}))
	assert_true(not FcCareerEvents.meets(p, {"min_level": 2}))
	p.level = 10
	assert_true(not FcCareerEvents.meets(p, {"max_level": 9}))
	assert_true(not FcCareerEvents.meets(p, {"min_seasons": 1}), "no seasons played yet")
	p.history.append({"year": 2026})
	assert_true(FcCareerEvents.meets(p, {"min_seasons": 1}))
	assert_true(not FcCareerEvents.meets(p, {"requires_tags": ["mentor"]}))
	p.tags.append("mentor")
	assert_true(FcCareerEvents.meets(p, {"requires_tags": ["mentor"]}))
	assert_true(not FcCareerEvents.meets(p, {"excludes_tags": ["mentor"]}))
	assert_true(not FcCareerEvents.meets(p, {"min_hype": 10}))
	p.hype = 10
	assert_true(FcCareerEvents.meets(p, {"min_hype": 10}))
	assert_true(not FcCareerEvents.meets(p, {"max_coach_trust": 40}), "trust is 50")
	assert_true(not FcCareerEvents.meets(p, {"has_rival": true}))
	p.rival_player_id = 9
	assert_true(FcCareerEvents.meets(p, {"has_rival": true}))
	assert_true(not FcCareerEvents.meets(p, {"has_rival": false}))


func test_a_new_player_is_offered_only_early_events_and_a_veteran_gets_more() -> void:
	var rookie := FcCareerEvents.eligible(_profile(1), 2026)
	for e in rookie:
		assert_true(int(e["when"].get("min_level", 1)) <= 1)
	var star := _profile(20)
	star.history.resize(10)
	star.reputation = 50
	star.hype = 60
	star.fan_favor = 40
	var veteran := FcCareerEvents.eligible(star, 2030)
	assert_true(veteran.size() > rookie.size())


func test_choices_move_the_public_image_trust_and_chemistry_and_clamp() -> void:
	var p := _profile(6)
	p.coach_trust = 98
	p.chemistry = 3
	p.fan_favor = 50
	var r := FcCareerEvents.apply_choice(p, "coach_clash", "apologize", 2026)
	assert_true(r["ok"], str(r.get("reason", "")))
	assert_eq(p.coach_trust, 100, "clamped at 100")
	assert_eq(p.chemistry, 5)
	var r2 := FcCareerEvents.apply_choice(p, "foundation", "found", 2026)
	assert_true(r2["ok"])
	assert_eq([p.fan_favor, p.media_image], [56, 54])
	assert_true(p.tags.has("foundation"))
	var drop := FcCareerEvents.apply_choice(p, "loyalty_call", "listen", 2026)
	assert_true(drop["ok"])
	assert_eq(p.fan_favor, 50)
