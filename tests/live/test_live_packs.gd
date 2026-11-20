extends FcLiveTestCase
## The pack reveal with real animation: the pack tears open, cards flip, rare pulls get particles, a flash and a banner, skipping works
## mid-animation, and reduced motion removes the movement and effects.


func _reveal(rarities: Array) -> FcPackReveal:
	var cards: Array = []
	var rows := {}
	for i in rarities.size():
		var id := "card_%d" % i
		cards.append({"card_id": id, "new": true, "quantity": 1})
		rows[id] = {"card_id": id, "rarity": rarities[i], "overall": 70 + i, "position": "SG", "name": "Player %d" % i, "edition": "Base", "owned": true, "available": true}
	var reveal := FcPackReveal.new()
	reveal.size = Vector2(900, 500)
	host.add_child(reveal)
	reveal.setup({"opening_id": "op_1", "pack_id": "p", "cards": cards}, "Live Pack", {"name": "Live Pack", "cards_per_pack": cards.size(), "odds": {"legendary": 100}},
		func(id: String) -> Dictionary: return rows[id].duplicate(),
		func(_r: String) -> int: return 10,
		func() -> Dictionary: return {"owned": 5, "total": 20},
		func() -> void: pass)
	return reveal


func _count(node: Node, type: Variant) -> int:
	var n := 1 if is_instance_of(node, type) else 0
	for c in node.get_children():
		n += _count(c, type)
	return n


func test_the_pack_tears_open_and_the_cards_appear() -> void:
	var reveal := _reveal(["common", "rare"])
	await frames(2)
	assert_true(_count(reveal, FcPackArt) == 1, "the pack artwork plays the intro")
	assert_true(reveal._cards_row.modulate.a < 1.0, "the cards are not shown yet")
	await seconds(1.0)
	assert_eq(_count(reveal, FcPackArt), 0, "the pack is gone once torn")
	assert_eq(reveal._cards_row.modulate.a, 1.0, "and the face-down cards are fully visible")


func test_a_card_flips_over_when_revealed() -> void:
	var reveal := _reveal(["common", "common"])   # two cards, so the stage is still there after the first flip
	await seconds(1.0)
	var face: FcCardFace = reveal._faces[0]
	assert_true(face.face_down)
	reveal.reveal_next()
	await seconds(0.1)
	assert_true(face.scale.x < 1.0, "turning")
	await seconds(0.6)
	assert_true(not face.face_down, "face up afterwards")


func test_an_epic_pull_gets_particles_a_flash_and_a_shake() -> void:
	var reveal := _reveal(["epic", "common"])
	await seconds(1.0)
	reveal.reveal_next()
	await seconds(0.1)
	assert_true(_count(reveal._cards_row, CPUParticles2D) >= 1, "a burst of particles")
	assert_true(reveal._flash.color.a > 0.0, "the flash is showing")
	assert_true(not reveal.effects_log[0]["quiet"], "the effect was recorded as a full effect")
	await seconds(0.6)
	assert_true(reveal._flash.color.a < 0.05, "and it fades")
	assert_eq(reveal._cards_row.position.x, 0.0, "the shake settles back to the start")


func test_a_legendary_pull_shows_a_banner() -> void:
	var reveal := _reveal(["legendary"])
	await seconds(1.0)
	reveal.reveal_next()
	await seconds(0.15)
	var banners := reveal._stage_box.get_children().filter(func(c: Node) -> bool: return c is Label and (c as Label).text == "LEGENDARY!")
	assert_eq(banners.size(), 1, "a banner names the rarity")
	await seconds(1.6)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY, "then the summary follows")


func test_common_cards_have_no_effects() -> void:
	var reveal := _reveal(["common", "common"])
	await seconds(1.0)
	reveal.reveal_next()
	await seconds(0.1)
	assert_eq(_count(reveal, CPUParticles2D), 0)
	assert_eq(reveal._flash.color.a, 0.0)


func test_skipping_in_the_middle_of_an_animation_is_clean() -> void:
	var reveal := _reveal(["common", "epic", "legendary"])
	await seconds(1.0)
	reveal.reveal_next()
	reveal.reveal_next()
	reveal.reveal_all()   # while the epic effect and flips are still running
	await seconds(0.8)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(reveal.effects_log.size(), 3)


func test_reduced_motion_has_no_intro_particles_flash_or_shake() -> void:
	FcMotion.reduced = true
	var reveal := _reveal(["legendary", "epic"])
	await frames(3)
	assert_eq(_count(reveal, FcPackArt), 0, "no intro animation")
	reveal.reveal_next()
	await frames(3)
	assert_eq(_count(reveal, CPUParticles2D), 0, "no particles")
	assert_eq(reveal._flash.color.a, 0.0, "no flash")
	assert_true(reveal.effects_log[0]["quiet"])
	assert_true(not (reveal._faces[0] as FcCardFace).face_down, "the card is simply turned over")


func test_reveal_by_clicking_the_card_works_like_the_button() -> void:
	var reveal := _reveal(["common", "rare"])
	await seconds(1.0)
	(reveal._faces[0] as FcCardFace).activated.emit()
	assert_eq(reveal.next_index, 1)
	(reveal._faces[1] as FcCardFace).activated.emit()
	await seconds(0.8)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)


func test_skipping_during_the_pack_tear_is_clean() -> void:
	var reveal := _reveal(["rare", "epic", "legendary"])
	await frames(2)
	reveal.reveal_all()   # the pack is still shaking: the intro must not touch anything that was removed
	await seconds(1.2)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY)
	assert_eq(reveal.effects_log.size(), 3)
