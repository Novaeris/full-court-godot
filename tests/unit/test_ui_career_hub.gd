extends FcTestCase
## The Career hub hero (Phase G): the player on the stage, overall and potential badges, level with an XP bar, the points, the radar of
## attribute groups. It shows only what the career rules compute (level, XP into the level, points) and nothing invented.

func _card() -> Dictionary:
	return {"name": "Maya Okoro", "jersey": 11, "position": "SF", "secondary": "SG", "archetype": "Two-Way Wing", "age": 19, "height_cm": 201, "weight_kg": 96, "wingspan_cm": 207,
		"team": "Not signed yet", "overall": 47, "potential": 78,
		"groups": [{"name": "Offensive", "rows": [["Layups", 52, 99], ["Dunking", 40, 99]]}, {"name": "Defensive", "rows": [["Steals", 54, 99], ["Blocks", 40, 90]]},
			{"name": "Physical", "rows": [["Speed", 52, 98], ["Strength", 40, 99]]}, {"name": "Mental", "rows": [["IQ", 60, 95]]}]}


func _progress() -> Dictionary:
	return {"level": 3, "xp": 400, "into_level": 100, "needed": 250, "development_points": 4, "skill_points": 1}


func _vm() -> Dictionary:
	return {"subject": FcPlayerPresentation.subject("career_player:7", "Maya Okoro", {}, 11)}


func _texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_texts(c, out)
	return out


func test_the_hero_shows_the_rpg_numbers_the_rules_compute() -> void:
	var hero := FcCareerHub.hero(_card(), _progress(), _vm(), func() -> void: pass)
	var text := "\n".join(_texts(hero))
	for expected in ["Level 3", "XP 400 (100 of 250 to the next level)", "Development points 4", "Skill points 1", "Overall", "Potential (your ceiling)", "Player profile", "201 cm"]:
		assert_true(expected in text, "the hero shows: " + expected)
	hero.free()


func test_the_hero_has_the_stage_both_rating_badges_and_an_xp_bar() -> void:
	var hero := FcCareerHub.hero(_card(), _progress(), _vm(), func() -> void: pass)
	var stages := hero.find_children("*", "FcShowcaseStage", true, false)
	assert_eq(stages.size(), 1, "the player is the centrepiece")
	var badges := hero.find_children("*", "FcRatingBadge", true, false)
	assert_eq(badges.size(), 2)
	assert_eq((badges[0] as FcRatingBadge).value, 47)
	assert_eq((badges[1] as FcRatingBadge).value, 78)
	var bars := hero.find_children("*", "FcProgress", true, false)
	assert_eq(bars.size(), 1)
	assert_eq((bars[0] as FcProgress).value, 100.0)
	assert_eq((bars[0] as FcProgress).max_value, 250.0)
	hero.free()


func test_the_profile_button_calls_back() -> void:
	var hits: Array = []
	var hero := FcCareerHub.hero(_card(), _progress(), _vm(), func() -> void: hits.append(true))
	for b in hero.find_children("*", "Button", true, false):
		if (b as Button).text == "Player profile":
			(b as Button).pressed.emit()
	assert_eq(hits.size(), 1)
	hero.free()


func test_the_card_tab_has_a_radar_and_every_attribute_row() -> void:
	var tab := FcCareerHub.card_tab(_card())
	var radars := tab.find_children("*", "FcRadar", true, false)
	assert_eq(radars.size(), 1)
	var radar: FcRadar = radars[0]
	assert_eq(radar.labels, ["Offensive", "Defensive", "Physical", "Mental"])
	assert_eq(radar.values[0], 46.0, "the group average of 52 and 40")
	assert_eq(radar.ceilings[0], 99.0)
	var tables := tab.find_children("*", "FcTable", true, false)
	assert_eq(tables.size(), 4, "one table per group, every attribute kept")
	assert_eq((tables[0] as FcTable).row_count(), 2)
	tab.free()


func test_a_radar_needs_three_groups_and_describes_itself_in_words() -> void:
	var too_few := FcRadar.new(["A", "B"], [10, 20])
	assert_true(not too_few.has_shape())
	assert_eq(too_few.summary(), "")
	var radar := FcRadar.new(["Shooting", "Defense", "Athletic"], [72.4, 50, 80], [80, 60, 90])
	assert_true(radar.has_shape())
	assert_eq(radar.summary(), "Shooting 72 (can reach 80), Defense 50 (can reach 60), Athletic 80 (can reach 90)")
	too_few.free()
	radar.free()
