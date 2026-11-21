extends FcTestCase
## Perceived variety, not parameter variety (D-059): over 400 seeded players the VISIBLE feature groups (face shape, eyes, brows, nose and mouth,
## hair, facial hair, skin and undertone, body, and the identifying extras) must each take many values, no two players may match in everything,
## and almost every PAIR must differ in several groups at once (so two players rarely look alike at a glance), including inside a 15-man roster.
## The pixel-level check (nearest-neighbour distance of the rendered faces, before and after) is tools/portrait_variety.gd, run in a window.

const COUNT := 400


## The visible feature groups of a key, each as one comparable string.
static func groups(key: String, age: int = 0) -> Dictionary:
	var visual := FcPlayerVisual.resolve(FcPlayerPresentation.subject(key, "V", {}, 0, {}, "", {"age": age} if age > 0 else {}))
	var id: Dictionary = visual["identity"]
	var p: Dictionary = id["proportions"]
	var t := FcPlayerTraits.of(key, age)
	var b := FcPlayerTraits.body(key)
	return {
		"face": "%s/%s/%s/%s/%s" % [p["jaw"], t["chin"], t["cheek"], p["face_w"], id["face"]],
		"eyes": "%s/%s/%s/%s/%s" % [t["eye_shape"], t["eye_tilt"], t["iris"], p["eye_gap"], p["eye_size"]],
		"brows": "%s/%s" % [p["brow"], t["brow_arch"]],
		"nose_mouth": "%s/%s/%s/%s" % [p["nose"], t["nose_w"], p["mouth"], t["lips"]],
		"hair": "%s/%s/%s/%s" % [id["hair"], t["hair_variant"], (id["hair_color"] as Color).to_html(false), t["forehead"]],
		"facial_hair": str(id["facial_hair"]),
		"skin": "%s/%s/%s" % [id["skin"], t["undertone"], p["warmth"]],
		"body": "%s/%s/%s/%s/%s" % [id["build"], t["slope"], t["neck"], b["shoulder"], b["girth"]],
		"extras": "%s/%s/%s/%s/%s/%s/%s/%s/%s/%s" % [t["tattoo"] if int(t["tattoo"]) < 2 else 9, t["sleeve"], t["chain"], t["earring"], t["cleft"], p["accessory"], t["scar"], t["freckles"], t["glasses"], t["brow_gap"]],
	}


func _all() -> Array:
	var out: Array = []
	for i in COUNT:
		out.append(groups("variety:%d" % i))
	return out


func test_each_feature_group_takes_many_values() -> void:
	var all := _all()
	for g in all[0]:
		var seen := {}
		for entry in all:
			seen[entry[g]] = true
		var minimum := 4 if g == "facial_hair" else (5 if g == "brows" else 12)
		assert_true(seen.size() >= minimum, "%s takes at least %d different values over %d players (got %d)" % [g, minimum, COUNT, seen.size()])


func test_no_two_players_match_in_everything() -> void:
	var seen := {}
	for entry in _all():
		seen["|".join(entry.values())] = true
	assert_eq(seen.size(), COUNT, "400 players, 400 different looks")


func test_almost_every_pair_differs_in_several_groups() -> void:
	var all := _all()
	var names: Array = all[0].keys()
	var close_pairs := 0
	var pairs := 0
	var total_diff := 0
	for i in COUNT:
		for j in range(i + 1, COUNT):
			var diff := 0
			for g in names:
				if all[i][g] != all[j][g]:
					diff += 1
			pairs += 1
			total_diff += diff
			if diff < 5:
				close_pairs += 1
	assert_true(float(close_pairs) / float(pairs) < 0.0005, "pairs differing in fewer than 5 of 9 groups: %d of %d" % [close_pairs, pairs])
	assert_true(float(total_diff) / float(pairs) > 7.0, "on average a pair differs in %.2f of 9 groups" % (float(total_diff) / float(pairs)))


func test_a_roster_of_fifteen_has_no_look_alikes() -> void:
	var all := _all()
	for start in range(0, COUNT - 15, 15):
		var worst := 0
		for i in range(start, start + 15):
			for j in range(i + 1, start + 15):
				var diff := 0
				for g in all[i]:
					if all[i][g] != all[j][g]:
						diff += 1
				if diff < 4:
					worst += 1
		assert_eq(worst, 0, "roster starting at %d has two players differing in fewer than 4 groups" % start)


func test_ageing_changes_marks_only_and_keeps_the_face() -> void:
	for i in 40:
		var key := "variety_age:%d" % i
		var young := groups(key, 20)
		var old := groups(key, 40)
		for g in ["face", "eyes", "brows", "nose_mouth", "skin", "body", "extras", "facial_hair"]:
			assert_eq(young[g], old[g], "%s keeps its %s from 20 to 40" % [key, g])
	var older := 0
	for i in 40:
		var key := "variety_age:%d" % i
		if FcPlayerTraits.of(key, 40)["lines"] > FcPlayerTraits.of(key, 20)["lines"]:
			older += 1
	assert_eq(older, 40, "everyone shows more lines at 40 than at 20")


func test_body_follows_the_known_physical_data_only_subtly() -> void:
	var small := FcPlayerTraits.body("body:1", {"height_cm": 180, "weight_kg": 75, "position": "PG"})
	var big := FcPlayerTraits.body("body:1", {"height_cm": 214, "weight_kg": 125, "position": "C"})
	assert_true(int(big["height"]) > int(small["height"]), "a taller player is drawn taller")
	assert_true(int(big["girth"]) > int(small["girth"]) and int(big["shoulder"]) > int(small["shoulder"]), "a heavier player is broader")
	for k in ["height", "shoulder", "girth", "leg", "arm"]:
		assert_true(absi(int(big[k]) - int(small[k])) <= 22, "%s differs only moderately (not a caricature)" % k)
	assert_eq(FcPlayerTraits.body("body:1", {}), FcPlayerTraits.body("body:1", {}), "deterministic")
	assert_eq(FcPlayerTraits.body("body:2")["height"] >= 98 and FcPlayerTraits.body("body:2")["height"] <= 102, true, "without data every player is close to the standard height")


func test_position_nudges_are_small() -> void:
	var guard := FcPlayerTraits.body("pos:1", {"position": "PG"})
	var forward := FcPlayerTraits.body("pos:1", {"position": "SF"})
	var big := FcPlayerTraits.body("pos:1", {"position": "C"})
	assert_true(int(big["shoulder"]) - int(guard["shoulder"]) <= 6 and int(guard["leg"]) - int(forward["leg"]) <= 3, "position only nudges proportions by a few percent")
