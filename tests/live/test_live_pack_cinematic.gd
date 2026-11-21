extends FcLiveTestCase
## The cinematic pack opening (prototype): the five stages happen in order, the committed opening is never changed or reordered, Skip gives
## exactly the same result as watching and leaves nothing running, reduced motion shows no show, and every effect is bounded.

const RARITIES_MIXED := ["common", "uncommon", "rare", "epic", "legendary"]


func before_each() -> void:
	super.before_each()
	FcMotion.reduced = false


func after_each() -> void:
	FcMotion.reduced = false
	super.after_each()


func _reveal(rarities: Array) -> FcPackRevealCinematic:
	var cards: Array = []
	var rows := {}
	for i in rarities.size():
		var id := "card_%d" % i
		cards.append({"card_id": id, "new": i % 2 == 0, "quantity": 1})
		rows[id] = {"card_id": id, "rarity": rarities[i], "overall": 70 + i, "position": "SG", "name": "Player %d" % i, "edition": "Base", "owned": true, "available": true}
	var reveal := FcPackRevealCinematic.new()
	reveal.size = Vector2(900, 640)
	host.add_child(reveal)
	reveal.setup({"opening_id": "op_cine", "pack_id": "p", "cards": cards}, "Cine Pack", {"name": "Cine Pack", "cards_per_pack": cards.size(), "odds": {"legendary": 100}},
		func(id: String) -> Dictionary: return rows[id].duplicate(),
		func(_r: String) -> int: return 10,
		func() -> Dictionary: return {"owned": 5, "total": 20},
		func() -> void: pass)
	return reveal


func _card_log(reveal: FcPackReveal) -> Array:
	var out: Array = []
	for e in reveal.effects_log:
		out.append([e["index"], e["card_id"], e["rarity"], e["intensity"]])
	return out


func test_the_five_stages_happen_in_order() -> void:
	var reveal := _reveal(["common", "epic"])
	await frames(3)
	assert_eq(reveal.phase, FcPackRevealCinematic.Phase.PRESENT, "stage 1: the pack is presented")
	assert_true(reveal._pack != null, "and it is on screen")
	reveal.open_pack()
	assert_eq(reveal.phase, FcPackRevealCinematic.Phase.OPENING, "stage 2: it opens")
	await seconds(2.0)
	assert_eq(reveal.phase, FcPackRevealCinematic.Phase.REVEALING, "the cards are out")
	reveal.reveal_next()
	await seconds(0.6)
	assert_true(reveal.spotlight != null, "stage 3: the card comes forward")
	reveal.reveal_next()   # continue: the common card lands, the epic one comes forward
	await seconds(2.2)
	assert_true("special" in reveal.presentation_log.map(func(e: Dictionary) -> String: return e["stage"]), "stage 4: the epic card gets the special treatment")
	reveal.reveal_next()
	await seconds(0.3)
	reveal.reveal_next()
	await seconds(0.3)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY, "stage 5: the summary")
	var stages: Array = reveal.presentation_log.map(func(e: Dictionary) -> String: return e["stage"])
	assert_eq(stages[0], "present")
	assert_eq(stages[stages.size() - 1], "summary")


func test_the_opening_record_is_never_changed_or_reordered() -> void:
	var reveal := _reveal(RARITIES_MIXED)
	var before := reveal.opening.duplicate(true)
	await seconds(0.5)
	reveal.open_pack()
	await seconds(2.0)
	for i in RARITIES_MIXED.size():
		reveal.reveal_next()
		await seconds(0.3)
	assert_eq(reveal.opening, before, "the committed opening is exactly as it was")
	assert_eq(reveal.entries, before["cards"], "cards are in the order they were rolled")


func test_skipping_gives_the_same_result_as_watching() -> void:
	var watched := _reveal(RARITIES_MIXED)
	await seconds(0.3)
	watched.open_pack()
	await seconds(2.0)
	for i in RARITIES_MIXED.size() + 1:
		watched.reveal_next()
		await seconds(2.6 if i >= 3 else 1.0)
	assert_eq(watched.stage, FcPackReveal.Stage.SUMMARY)
	var skipped := _reveal(RARITIES_MIXED)
	await seconds(0.3)
	skipped.reveal_all()
	await frames(2)
	assert_eq(skipped.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(_card_log(skipped), _card_log(watched), "the same cards, in the same order, with the same intensities")
	assert_eq(skipped.new_count(), watched.new_count(), "the same NEW and DUPLICATE marks")
	assert_eq(skipped.entries, watched.entries)


func test_skipping_in_the_middle_leaves_nothing_running() -> void:
	var reveal := _reveal(RARITIES_MIXED)
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	reveal.reveal_next()
	reveal.reveal_next()
	reveal.reveal_next()   # a rare and then an epic come forward: effects are running
	await seconds(0.9)
	var fx := reveal.fx
	reveal.reveal_all()
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_true(not fx.is_active(), "every effect was cleared")
	assert_eq(fx.particle_count(), 0, "no particle is left")
	assert_true(reveal.spotlight == null, "no spotlight card is left")
	assert_eq(reveal.effects_log.size(), RARITIES_MIXED.size(), "every card is accounted for")
	await seconds(1.0)
	assert_eq(reveal.effects_log.size(), RARITIES_MIXED.size(), "nothing happens later")


func test_skipping_during_the_pack_show_is_clean() -> void:
	var reveal := _reveal(["rare", "legendary"])
	await frames(2)
	reveal.open_pack()
	await seconds(0.3)
	reveal.reveal_all()
	await seconds(1.5)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(reveal.effects_log.size(), 2)


func test_reduced_motion_shows_no_show() -> void:
	FcMotion.reduced = true
	var reveal := _reveal(["legendary", "epic"])
	await frames(3)
	assert_true(reveal._pack == null, "no pack show")
	assert_eq(reveal.phase, FcPackRevealCinematic.Phase.REVEALING, "the cards are simply there")
	reveal.reveal_next()
	await frames(3)
	assert_true(reveal.spotlight == null, "no spotlight")
	assert_eq(reveal.fx.particle_count(), 0, "no particles")
	assert_true(not reveal.fx.is_active(), "no flash, dim or rays")
	assert_true(reveal.effects_log[0]["quiet"])
	assert_true(not (reveal._faces[0] as FcCardFace).face_down, "the card turned over in place")


func test_a_legendary_pull_has_the_full_special_presentation() -> void:
	var reveal := _reveal(["legendary", "common"])
	await seconds(0.3)
	reveal.open_pack()
	await seconds(2.0)
	reveal.reveal_next()
	await seconds(0.4)
	assert_true(reveal.spotlight != null and reveal.spotlight.tease > 0.0, "the card back glows while tension builds")
	await seconds(1.9)
	var kinds: Array = reveal.presentation_log.map(func(e: Dictionary) -> String: return e["stage"])
	assert_true("special" in kinds, "the impact happened")
	var banners := reveal.fx.get_children().filter(func(c: Node) -> bool: return c is Label and (c as Label).text == "LEGENDARY!")
	assert_eq(banners.size(), 1, "the banner")
	assert_true(reveal.spotlight.get_child_count() >= 1, "and the name plate")
	assert_true(reveal.fx.stats["peak_particles"] > 60, "a big burst")


func test_effects_are_bounded() -> void:
	var fx := FcRevealFx.new()
	host.add_child(fx)
	fx.seed_from("bounded")
	var cap := int(FcRevealSpec.caps()["particles"])
	for i in 20:
		fx.burst(Vector2(100, 100), Color.GOLD, 120)
	assert_true(fx.particle_count() <= cap, "never more than %d particles (got %d)" % [cap, fx.particle_count()])
	assert_true(fx.stats["particles_dropped"] > 0, "the extra ones were dropped, not queued")
	assert_true(fx.flash(Color.WHITE, 0.5), "the first flash is allowed")
	assert_true(not fx.flash(Color.WHITE, 0.5), "a second one right after is refused (photosensitivity)")
	for i in 6:
		fx.rays(Vector2(10, 10), Color.GOLD, 8)
	assert_true(fx._rays.size() <= int(FcRevealSpec.caps()["rays_at_once"]))
	await seconds(2.0)
	assert_eq(fx.particle_count(), 0, "particles die on their own")
	assert_true(not fx.is_processing(), "and the node stops processing when nothing is left")
	fx.burst(Vector2.ZERO, Color.RED, 50)
	fx.stop_all()
	assert_eq(fx.particle_count(), 0)
	assert_true(not fx.is_active())


func test_effects_do_nothing_with_reduced_motion() -> void:
	FcMotion.reduced = true
	var fx := FcRevealFx.new()
	host.add_child(fx)
	fx.burst(Vector2.ZERO, Color.RED, 50)
	fx.rays(Vector2.ZERO, Color.RED, 8)
	fx.shockwave(Vector2.ZERO, Color.RED)
	fx.dim(0.6)
	fx.banner("LEGENDARY!", Color.GOLD)
	assert_true(not fx.flash(Color.WHITE, 0.5))
	assert_true(not fx.is_active())


func test_a_big_cue_quiets_small_ones_after_it() -> void:
	var prefs := FcPreferences.new("user://test_preferences_cine.cfg")
	var audio := FcAudio.new(prefs)
	host.add_child(audio)
	FcAudio.current = audio
	var reveal := _reveal(["legendary", "common"])
	reveal._cue("rarity_4", 4)
	reveal._cue("rarity_0", 0)
	assert_eq(audio.requested, ["rarity_4"], "a small sting right after a legendary one is not layered on top")
	FcAudio.current = null
	DirAccess.remove_absolute("user://test_preferences_cine.cfg")


func test_the_reveal_spec_covers_every_rarity_and_never_fails() -> void:
	for id in FcRevealSpec.rarity_ids():
		assert_true(FcRarityStyle.known(str(id)), "%s is a known rarity" % id)
	for id in FcRarityStyle.STYLES:
		assert_true(FcRevealSpec.rarity_ids().has(id), "%s has a reveal spec" % id)
	assert_eq(FcRevealSpec.of("mythic_from_a_future_release"), FcRevealSpec.of("common"), "an unknown rarity reveals quietly")
	var prev := -1
	for id in ["common", "uncommon", "rare", "epic", "legendary"]:
		var spec := FcRevealSpec.of(id)
		assert_true(int(spec["particles"]) >= prev, "bigger rarities never get smaller bursts")
		prev = int(spec["particles"])
		assert_true(float(spec["flash"]) <= 0.8, "a flash is never harsher than 0.8")
	assert_true(bool(FcRevealSpec.of("legendary")["banner"]) and not bool(FcRevealSpec.of("epic")["banner"]), "only legendary gets the banner")


func test_the_card_sweep_is_an_explicit_call() -> void:
	var rare := FcCardFace.new().setup({"card_id": "x", "rarity": "rare", "name": "A B", "overall": 80, "position": "PG", "owned": true, "available": true}, {})
	host.add_child(rare)
	await frames(2)
	assert_true(rare.play_sweep() != null, "a rare card sweeps when asked")
	var common := FcCardFace.new().setup({"card_id": "y", "rarity": "common", "name": "A B", "overall": 60, "position": "PG", "owned": true, "available": true}, {})
	host.add_child(common)
	await frames(2)
	assert_true(common.play_sweep() == null, "a common card has no sweep")
	rare.set_glow(2.0)
	assert_eq(rare.lift, 1.0, "the glow is clamped")
