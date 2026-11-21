extends FcLiveTestCase
## The main menu in a real scene at the window shapes that matter: it draws (the mode art, the arena backdrop and the save cards run their
## _draw code), fits the width, keeps the three cards one height on a wide window, and the startup splash plays, skips and respects
## reduced motion. (Runtime script errors fail the test through the live runner's logger.)

const SHAPES := [Vector2(1920, 1080), Vector2(1280, 800), Vector2(800, 600), Vector2(412, 915)]


func _slots() -> Array:
	var out: Array = []
	for i in 3:
		var m := FcSaveMetadata.new()
		m.slot_id = "slot_%d" % i
		m.label = "Save number %d with a fairly long name to test ellipsis" % i
		m.mode = ["owner", "career", "dynasty"][i]
		m.team_name = "Harbor Kings"
		m.season = 2026
		m.saved_at = "2026-11-21T18:16:08"
		out.append(m)
	return out


func _actions() -> Dictionary:
	var noop := func(_a = null) -> void: pass
	return {"open_owner": noop, "open_career": noop, "open_dynasty": noop, "continue_latest": noop, "load": noop, "delete": noop, "select": noop, "settings": noop, "credits": noop, "quit": noop}


func _build(shape: Vector2, with_saves: bool = true) -> Dictionary:
	host.size = shape
	var frame := Control.new()   # a plain frame of exactly the window shape (FcScreenHost always fills the whole test window)
	frame.size = shape
	host.add_child(frame)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(box)
	var compact := shape.x < 700.0
	var result := FcMainMenu.build(box, _slots() if with_saves else [], _actions(), {"compact": compact})
	result["host"] = frame
	result["box"] = box
	return result


func test_the_menu_draws_and_fits_at_every_window_shape() -> void:
	for shape in SHAPES:
		var m := await _build(shape)
		await frames(3)
		var page: Control = m["box"].find_child("MenuPage", true, false)
		assert_true(page.get_combined_minimum_size().x <= shape.x, "the menu needs %d px of %d" % [int(page.get_combined_minimum_size().x), int(shape.x)])
		assert_eq(m["mode_cards"].size(), 3)
		(m["host"] as Control).queue_free()
		await frames(1)


func test_the_arena_backdrop_and_the_mode_art_draw_without_errors() -> void:
	var backdrop := FcScreenHost.new()
	host.add_child(backdrop)
	backdrop.set_skin(FcModeSkin.resolve(FcModeSkin.NEUTRAL, {"background": "arena"}))
	assert_eq(backdrop.backdrop_style(), "arena")
	for kind in FcModeArt.KINDS:
		var art := FcModeArt.new(kind, FcUiTokens.PRIMARY)
		art.size = Vector2(300, 200)
		host.add_child(art)
	await frames(3)


func test_the_three_mode_cards_share_one_height_on_a_wide_window() -> void:
	var m := await _build(Vector2(1280, 800), false)
	await frames(3)
	var heights: Array = []
	for card in m["mode_cards"]:
		heights.append(int((card as Control).size.y))
	assert_true(heights.max() - heights.min() <= 2, "card heights %s" % str(heights))
	var widths: Array = []
	for card in m["mode_cards"]:
		widths.append(int((card as Control).size.x))
	assert_true(widths[0] > widths[1], "Owner is the widest card: %s" % str(widths))
	assert_true(m["mode_cards"][0].position.y == m["mode_cards"][2].position.y, "all three sit in one row")


func test_on_a_phone_the_cards_stack() -> void:
	var m := await _build(Vector2(412, 915), false)
	await frames(3)
	assert_true(m["mode_cards"][1].position.y > m["mode_cards"][0].position.y, "the cards are one under the other")


func test_the_splash_plays_both_logos_and_a_key_skips_it() -> void:
	host.size = Vector2(1280, 800)
	var splash := FcSplash.new()
	host.add_child(splash)
	var done: Array = []
	splash.finished.connect(func() -> void: done.append(true))
	splash.start()
	await frames(3)
	assert_true(splash._logo.texture != null, "a logo is showing")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	splash._gui_input(key)
	assert_eq(done.size(), 1, "any key skips it")


func test_with_reduced_motion_the_splash_shows_each_logo_without_fading() -> void:
	FcMotion.reduced = true
	host.size = Vector2(1280, 800)
	var splash := FcSplash.new()
	host.add_child(splash)
	var done: Array = []
	splash.finished.connect(func() -> void: done.append(true))
	splash.start()
	await frames(2)
	assert_eq(splash._logo.modulate.a, 1.0, "visible at once, no fade in")
	await seconds(2.6)
	assert_eq(done.size(), 1, "both logos have shown and it finished by itself")
