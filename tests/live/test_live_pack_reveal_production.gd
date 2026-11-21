extends FcLiveTestCase
## The production pack opening (D-059): rarity-scaled presentation (common and uncommon are quick, rare is enhanced, epic cinematic, legendary
## full cinematic), the Quick style and the preference, a legendary that makes the PLAYER the centrepiece (name as the banner, LEGENDARY as the
## supporting label), exactly-once acknowledgement, and integrity (nothing written, skip equals watching, reduced motion quiet).

const MIXED := ["common", "uncommon", "rare", "epic", "legendary"]


func before_each() -> void:
	super.before_each()
	FcMotion.reduced = false


func after_each() -> void:
	FcMotion.reduced = false
	super.after_each()


func _reveal(rarities: Array, on_done: Callable = Callable(), quick: bool = false) -> FcPackReveal:
	var cards: Array = []
	var rows := {}
	for i in rarities.size():
		var id := "card_%d" % i
		cards.append({"card_id": id, "new": i % 2 == 0, "quantity": 1})
		rows[id] = {"card_id": id, "rarity": rarities[i], "overall": 70 + i, "position": "SG", "name": "Player %d" % i, "edition": "Base", "team": "Harbor Kings", "owned": true, "available": true}
	var reveal: FcPackReveal = FcPackReveal.new() if quick else FcPackRevealCinematic.new()
	reveal.size = Vector2(900, 640)
	host.add_child(reveal)
	reveal.setup({"opening_id": "op_prod", "pack_id": "p", "cards": cards}, "Prod Pack", {"name": "Prod Pack", "cards_per_pack": cards.size(), "odds": {"legendary": 100}},
		func(id: String) -> Dictionary: return rows[id].duplicate(),
		func(_r: String) -> int: return 10,
		func() -> Dictionary: return {"owned": 5, "total": 20},
		on_done if on_done.is_valid() else func() -> void: pass)
	return reveal


func test_common_and_uncommon_cards_are_quick_and_rare_and_up_come_forward() -> void:
	for rarity in ["common", "uncommon"]:
		assert_true(not bool(FcRevealSpec.of(rarity)["spotlight"]), "%s has no spotlight" % rarity)
	for rarity in ["rare", "epic", "legendary"]:
		assert_true(bool(FcRevealSpec.of(rarity)["spotlight"]), "%s comes forward" % rarity)
	var reveal := _reveal(["common", "uncommon", "rare"])
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	reveal.reveal_next()
	assert_true(reveal.spotlight == null, "a common card turns over in its place")
	await seconds(0.45)
	assert_true(not (reveal._faces[0] as FcCardFace).face_down, "and is face up after one tap")
	reveal.reveal_next()
	assert_true(reveal.spotlight == null, "an uncommon one too")
	await seconds(0.45)
	reveal.reveal_next()
	await seconds(0.4)
	assert_true(reveal.spotlight != null, "a rare card comes forward")


func test_the_presentation_grows_with_the_rarity() -> void:
	var prev_total := -1.0
	for rarity in MIXED:
		var spec := FcRevealSpec.of(rarity)
		var total := float(spec["tease"]) + float(spec["flip"]) + float(spec["hold"]) + float(spec["particles"]) / 100.0 + float(spec["dim"])
		assert_true(total > prev_total, "%s is more elaborate than the one before it" % rarity)
		prev_total = total
	assert_true(float(FcRevealSpec.of("common")["tease"]) == 0.0 and int(FcRevealSpec.of("common")["particles"]) == 0, "common is plain")
	assert_true(bool(FcRevealSpec.of("legendary")["banner"]) and str(FcRevealSpec.of("legendary")["banner_text"]) == "name", "the legendary banner is the player's name")


func test_a_legendary_makes_the_player_the_centrepiece() -> void:
	var reveal := _reveal(["legendary"])
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	reveal.reveal_next()
	await seconds(2.6)
	var labels: Array = reveal.fx.find_children("*", "Label", true, false)
	var texts: Array = labels.map(func(l: Label) -> String: return l.text)
	assert_true("Player 0" in texts, "the player's name is the primary banner (%s)" % str(texts))
	assert_true("LEGENDARY" in texts, "LEGENDARY is the supporting label")
	var big: Label = labels.filter(func(l: Label) -> bool: return l.text == "Player 0")[0]
	var small: Label = labels.filter(func(l: Label) -> bool: return l.text == "LEGENDARY")[0]
	assert_true(big.get_theme_font_size("font_size") > small.get_theme_font_size("font_size"), "the name is larger than the rarity word")
	assert_true(reveal.spotlight != null and reveal.spotlight.row.get("name", "") == "Player 0", "and the portrait card is in the spotlight")


func test_done_acknowledges_exactly_once() -> void:
	var calls := [0]
	var reveal := _reveal(MIXED, func() -> void: calls[0] += 1)
	await seconds(0.3)
	reveal.reveal_all()
	await frames(2)
	var done: Button = null
	for b in reveal._actions.get_children():
		if b is Button and (b as Button).text == "Done":
			done = b
	assert_true(done != null, "the summary offers Done")
	done.pressed.emit()
	done.pressed.emit()
	done.pressed.emit()
	assert_eq(calls[0], 1, "three presses acknowledge once")


func test_watching_acknowledges_nothing_before_done() -> void:
	var calls := [0]
	var reveal := _reveal(["common", "epic"], func() -> void: calls[0] += 1)
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	for i in 4:
		reveal.reveal_next()
		await seconds(1.0)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(calls[0], 0, "the reveal itself never acknowledges or grants anything")


func test_quick_style_is_the_shipped_reveal_and_gives_the_same_result() -> void:
	var quick := _reveal(MIXED, Callable(), true)
	await seconds(1.0)
	quick.reveal_all()
	var cine := _reveal(MIXED)
	await seconds(0.3)
	cine.reveal_all()
	await frames(2)
	assert_eq(quick.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(cine.stage, FcPackReveal.Stage.SUMMARY)
	var a: Array = quick.effects_log.map(func(e: Dictionary) -> Array: return [e["index"], e["card_id"], e["rarity"], e["intensity"]])
	var b: Array = cine.effects_log.map(func(e: Dictionary) -> Array: return [e["index"], e["card_id"], e["rarity"], e["intensity"]])
	assert_eq(a, b, "Quick and Cinematic present the same cards in the same order")
	assert_eq(quick.new_count(), cine.new_count())


func test_the_preference_chooses_the_style_and_is_saved() -> void:
	var path := "user://test_preferences_reveal_style.cfg"
	var prefs := FcPreferences.new(path)
	assert_eq(prefs.pack_reveal_style, "cinematic", "cinematic is the default")
	prefs.pack_reveal_style = "quick"
	prefs.save_file()
	var again := FcPreferences.new(path)
	assert_eq(again.pack_reveal_style, "quick", "saved")
	var cfg := ConfigFile.new()
	cfg.set_value("display", "pack_reveal", "nonsense")
	cfg.save(path)
	assert_eq(FcPreferences.new(path).pack_reveal_style, "cinematic", "an unknown value falls back to cinematic")
	DirAccess.remove_absolute(path)


func test_reduced_motion_suppresses_every_effect_for_every_rarity() -> void:
	FcMotion.reduced = true
	var reveal := _reveal(MIXED)
	await frames(3)
	for i in MIXED.size():
		reveal.reveal_next()
		await frames(3)
		assert_true(reveal.spotlight == null, "no spotlight for %s" % MIXED[i])
		if is_instance_valid(reveal.fx):   # the effects layer goes with the stage when the summary replaces it
			assert_true(not reveal.fx.is_active(), "no effect for %s" % MIXED[i])
			assert_eq(reveal.fx.particle_count(), 0)
	await frames(3)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_true(reveal.effects_log.all(func(e: Dictionary) -> bool: return e["quiet"]), "every card was presented quietly")


func test_every_rarity_presents_and_the_limits_hold() -> void:
	var reveal := _reveal(MIXED)
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	for i in MIXED.size():
		reveal.reveal_next()
		await seconds(1.8)
		assert_true(reveal.fx.particle_count() <= int(FcRevealSpec.caps()["particles"]))
	var stats: Dictionary = reveal.fx.stats.duplicate()
	reveal.reveal_next()
	await seconds(0.4)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_true(int(stats["flashes"]) >= 1 and int(stats["peak_particles"]) <= int(FcRevealSpec.caps()["particles"]))
	var kinds: Array = reveal.presentation_log.map(func(e: Dictionary) -> String: return e["stage"])
	for stage in ["present", "open", "emerge", "card", "impact", "special", "summary"]:
		assert_true(stage in kinds, "stage %s happened" % stage)


func test_the_opening_is_never_written_to() -> void:
	var reveal := _reveal(MIXED)
	var before := reveal.opening.duplicate(true)
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	for i in 7:
		reveal.reveal_next()
		await seconds(1.0)
	assert_eq(reveal.opening, before)
