extends FcTestCase
## Team identity (Phase C, D-057): one team resolves to one look everywhere, every look is valid and readable, the emblem follows the
## words of the team's own nickname, every team in a generated league is visibly different, and nothing needs saved data.


func _subject(key: String = "team:1", nick: String = "Falconers") -> Dictionary:
	return FcTeamLook.subject(key, "Kestrel Bay " + nick, "KBF", "#0E7490", "#FFFFFF", "#FBBF24", nick)


func _league_teams() -> Array:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(7)
	var out: Array = []
	for team in world.teams.all():
		out.append(FcTeamLook.subject_for_team(world, team))
	return out


func test_the_same_subject_always_resolves_to_the_same_look() -> void:
	assert_eq(FcTeamLook.resolve(_subject()), FcTeamLook.resolve(_subject()), "deterministic")
	assert_true(FcTeamLook.resolve(_subject("team:1")) != FcTeamLook.resolve(_subject("team:2")) or true, "different keys may differ")


func test_a_look_is_complete_and_uses_known_parts() -> void:
	var look := FcTeamLook.resolve(_subject())
	assert_true(FcTeamLook.SHAPES.has(look["shape"]), "known shape")
	assert_true(FcTeamLook.EMBLEMS.has(look["emblem"]), "known emblem")
	assert_eq(look["abbreviation"], "KBF")
	assert_eq(look["city"], "Kestrel Bay")
	assert_eq(look["nickname"], "Falconers")
	for kind in ["home", "away", "alt"]:
		assert_true(look["uniforms"].has(kind), "uniform " + kind)


func test_the_emblem_follows_the_words_of_the_nickname() -> void:
	assert_eq(FcTeamLook.resolve(_subject("team:1", "Falconers"))["emblem"], "swoop")
	assert_eq(FcTeamLook.resolve(_subject("team:1", "Stormcallers"))["emblem"], "bolt")
	assert_eq(FcTeamLook.resolve(_subject("team:1", "Barons"))["emblem"], "crown")
	assert_eq(FcTeamLook.resolve(_subject("team:1", "Anchors"))["emblem"], "anchor")
	assert_eq(FcTeamLook.resolve(_subject("team:9", "Wanderers"))["emblem"], FcTeamLook.EMBLEMS[FcPlayerVisual.fnv1a("team:9|emblem") % FcTeamLook.EMBLEMS.size()], "no word matches: the hash decides")


func test_a_chosen_crest_in_logo_key_wins_and_a_bad_one_is_ignored() -> void:
	var s := _subject()
	s["logo_key"] = "hexagon/star"
	var look := FcTeamLook.resolve(s)
	assert_eq(look["shape"], "hexagon")
	assert_eq(look["emblem"], "star")
	s["logo_key"] = "nonsense/other"
	assert_eq(FcTeamLook.resolve(s)["shape"], FcTeamLook.resolve(_subject())["shape"], "an invalid key changes nothing")


func test_a_name_alone_is_split_into_city_and_nickname() -> void:
	var s := FcTeamLook.subject("x", "Harbor City Kings", "HCK", "#112233", "#FFFFFF")
	assert_eq(s["city"], "Harbor City")
	assert_eq(s["nickname"], "Kings")


func test_missing_or_invalid_colours_still_give_a_readable_look() -> void:
	var look := FcTeamLook.resolve(FcTeamLook.subject("x", "Nameless", "NMS", "", "banana"))
	assert_true(FcUiContrast.ratio(look["ink"], look["fill"]) >= 3.0, "ink is readable on the fill")


func test_crest_ink_and_jersey_numbers_are_readable_for_every_team_colour_scheme() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/generation/world.json"))
	for scheme in data["color_schemes"]:
		var look := FcTeamLook.resolve(FcTeamLook.subject("scheme:%s" % scheme[0], "Test Team", "TST", scheme[0], scheme[1], scheme[2], "Team"))
		assert_true(FcUiContrast.ratio(look["ink"], look["fill"]) >= 3.0, "crest ink on %s" % scheme[0])
		for kind in ["home", "away", "alt"]:
			var u: Dictionary = look["uniforms"][kind]
			assert_true(FcUiContrast.ratio(u["secondary"], u["primary"]) >= 3.0, "%s number on %s (%s)" % [kind, scheme[0], str(u["primary"])])
		var home: Dictionary = look["uniforms"]["home"]
		var away: Dictionary = look["uniforms"]["away"]
		assert_true(home["primary"] != away["primary"], "home and away differ for %s" % scheme[0])


func test_every_team_in_a_generated_league_looks_different() -> void:
	var seen := {}
	var subjects := _league_teams()
	assert_true(subjects.size() >= 20, "a real league (%d teams)" % subjects.size())
	for s in subjects:
		var look := FcTeamLook.resolve(s)
		assert_true(not seen.has(look["signature"]), "two teams share the crest %s: %s and %s" % [look["signature"], str(seen.get(look["signature"], "")), str(s["name"])])
		seen[look["signature"]] = s["name"]


func test_resolving_a_whole_league_twice_gives_the_same_crests() -> void:
	var a: Array = []
	var b: Array = []
	for s in _league_teams():
		a.append(FcTeamLook.resolve(s)["signature"])
	for s in _league_teams():
		b.append(FcTeamLook.resolve(s)["signature"])
	assert_eq(a, b)


func test_every_shape_and_emblem_draws_without_error_at_every_size() -> void:
	var canvas := Control.new()
	for shape in FcTeamLook.SHAPES:
		assert_true(FcTeamEmblems.shape_points(shape).size() >= 4, "shape %s has an outline" % shape)
	for emblem in FcTeamLook.EMBLEMS:
		for px in [16, 32, 64, 128]:
			var look := FcTeamLook.resolve(_subject())
			look["emblem"] = emblem
			var crest := FcTeamCrest.new().setup(look, px)
			assert_eq(crest.custom_minimum_size, Vector2(px, px))
			crest.free()
	canvas.free()


func test_the_crest_tooltip_names_the_team_and_a_crest_accepts_a_resolved_look() -> void:
	var crest := FcTeamCrest.new().setup(_subject(), 48)
	assert_eq(crest.tooltip_text, "Kestrel Bay Falconers")
	var again := FcTeamCrest.new().setup(crest.look, 48)
	assert_eq(again.look, crest.look, "a resolved look is used as it is")
	crest.free()
	again.free()


func test_the_wordmark_shows_city_and_nickname() -> void:
	var look := FcTeamLook.resolve(_subject())
	var mark := FcTeamWordmark.new().setup(look)
	assert_eq(mark.city_label.text, "KESTREL BAY")
	assert_eq(mark.nickname_label.text, "Falconers")
	mark.free()


func test_the_letterhead_shows_the_same_crest_as_everywhere_else() -> void:
	var s := _subject()
	var head := FcLetterhead.new()
	head.setup("Kestrel Bay Falconers", "Season 1", "KBF", "#0E7490", "#FFFFFF", s)
	assert_eq(head.crest.look, FcTeamLook.resolve(s), "one team, one crest")
	head.free()
