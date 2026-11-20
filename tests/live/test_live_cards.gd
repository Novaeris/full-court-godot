extends FcLiveTestCase
## Cards in a live scene tree: drawing without errors, hover lift and the light sweep, focus, and the flip.


func _row(rarity: String = "legendary") -> Dictionary:
	return {"card_id": "c1", "rarity": rarity, "overall": 94, "position": "PG", "secondary": "", "name": "Maya Okoro", "edition": "Base Edition",
		"team": "Harbor", "badges": ["a", "b"], "quantity": 2, "owned": true, "available": true, "mastery": 3, "art_path": ""}


func test_every_rarity_state_and_size_draws_without_errors() -> void:
	var flow := HFlowContainer.new()
	flow.size = Vector2(800, 600)
	host.add_child(flow)
	for rarity in ["common", "uncommon", "rare", "epic", "legendary", "future_rarity"]:
		for kind in ["mini", "standard", "hero"]:
			flow.add_child(FcCardView.build(_row(rarity), {"size": FcCardFace.size_for(kind), "tag": "NEW", "selected": rarity == "rare", "inspected": rarity == "epic"}))
	flow.add_child(FcCardView.build({}, {"face_down": true}))
	flow.add_child(FcCardView.build({"rarity": "epic", "owned": false, "available": false}, {"caption": "500 credits"}))
	await frames(4)
	assert_eq(flow.get_child_count(), 20)
	for c in flow.get_children():
		assert_true(c.size.x > 0.0, "every card was laid out")


func test_hovering_lifts_the_card_and_leaving_puts_it_down() -> void:
	var card := FcCardView.build(_row("epic"))
	host.add_child(card)
	await frames(2)
	card.mouse_entered.emit()
	await seconds(0.4)
	assert_eq(card.lift, 1.0, "fully lifted")
	assert_true(is_equal_approx(card.scale.x, 1.04), "and slightly larger")
	assert_eq(card.z_index, 1, "above its neighbours")
	card.mouse_exited.emit()
	await seconds(0.4)
	assert_eq(card.lift, 0.0)
	assert_eq(card.scale, Vector2.ONE)
	assert_eq(card.z_index, 0)


func test_focus_lifts_a_card_too_so_keyboard_users_see_it() -> void:
	var card := FcCardView.build(_row("rare"))
	host.add_child(card)
	await frames(2)
	card.grab_focus()
	await seconds(0.4)
	assert_true(card.has_focus() and card.lift == 1.0)
	card.mouse_exited.emit()
	await seconds(0.3)
	assert_eq(card.lift, 1.0, "the pointer leaving does not drop a focused card")
	card.release_focus()
	await seconds(0.4)
	assert_eq(card.lift, 0.0)


func test_the_light_sweep_crosses_a_rare_card_on_hover() -> void:
	var card := FcCardView.build(_row("rare"))
	host.add_child(card)
	await frames(2)
	var mat: ShaderMaterial = null
	for c in card.get_children():
		if c is ColorRect:
			mat = c.material
	assert_true(mat != null, "a rare card has the sweep")
	card.mouse_entered.emit()
	await seconds(0.2)
	var mid: float = mat.get_shader_parameter("progress")
	assert_true(mid > -0.3 and mid < 1.3, "the band is part-way across (%s)" % mid)
	await seconds(0.6)
	assert_true(float(mat.get_shader_parameter("progress")) >= 1.29, "and it finishes on the far side")


func test_reduced_motion_has_no_sweep_and_lifts_at_once() -> void:
	FcMotion.reduced = true
	var card := FcCardView.build(_row("legendary"))
	host.add_child(card)
	await frames(2)
	card.mouse_entered.emit()
	assert_eq(card.lift, 1.0, "instant")
	var mat: ShaderMaterial = null
	for c in card.get_children():
		if c is ColorRect:
			mat = c.material
	await seconds(0.2)
	var progress = mat.get_shader_parameter("progress")
	assert_true(progress == null or float(progress) <= -0.29, "the sweep never runs")


func test_a_card_flips_over_and_back() -> void:
	var card := FcCardView.build(_row("epic"), {"face_down": true})
	host.add_child(card)
	await frames(2)
	var tw := card.flip_to(false, 0.2)
	assert_true(tw != null, "an animated flip")
	await seconds(0.12)
	assert_true(card.scale.x < 1.0, "narrow while turning")
	await seconds(0.3)
	assert_true(not card.face_down, "face up afterwards")
	assert_eq(card.scale, Vector2.ONE, "at full width")
	card.flip_to(true, 0.2)
	await seconds(0.4)
	assert_true(card.face_down)


func test_reduced_motion_flip_is_instant() -> void:
	FcMotion.reduced = true
	var card := FcCardView.build(_row("epic"), {"face_down": true})
	host.add_child(card)
	await frames(2)
	assert_true(card.flip_to(false) == null)
	assert_true(not card.face_down and card.scale == Vector2.ONE)


func test_a_face_down_card_does_not_lift() -> void:
	var card := FcCardView.build(_row(), {"face_down": true})
	host.add_child(card)
	await frames(2)
	card.mouse_entered.emit()
	await seconds(0.3)
	assert_eq(card.lift, 0.0, "the back of a card gives no feedback that hints at its rarity")


func test_cards_can_be_tabbed_between() -> void:
	var row := HBoxContainer.new()
	host.add_child(row)
	var a := FcCardView.build(_row("common"))
	var b := FcCardView.build(_row("rare"))
	row.add_child(a)
	row.add_child(b)
	await frames(2)
	a.grab_focus()
	await frames(1)
	assert_true(a.has_focus())
	assert_true(b.focus_mode == Control.FOCUS_ALL, "the next card can take focus (arrow keys and the controller reach it)")
