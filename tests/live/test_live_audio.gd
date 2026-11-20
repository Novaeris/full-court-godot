extends FcLiveTestCase
## The sound layer in a running scene: sounds really start on a voice, every button clicks, mute and volume stop them, a pack reveal asks for
## the sounds that match what was pulled (and nothing is asked for when it is skipped), and the whole thing is harmless with sound off.

const PREFS := "user://test_preferences_live_audio.cfg"

var audio: FcAudio
var prefs: FcPreferences


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	prefs = FcPreferences.new(PREFS)
	audio = FcAudio.new(prefs)
	host.add_child(audio)
	FcAudio.current = audio


func after_each() -> void:
	FcAudio.current = null
	DirAccess.remove_absolute(PREFS)
	super.after_each()


func _playing() -> int:
	var n := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			n += 1
	return n


func test_a_sound_starts_on_a_voice_with_the_right_bus_and_level() -> void:
	assert_true(audio.play("rarity_3"), "the sound started")
	var voice: AudioStreamPlayer = null
	for child in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			voice = child
	assert_true(voice != null, "a voice is playing")
	if voice == null:
		return
	assert_eq(str(voice.bus), "SFX")
	assert_true(voice.stream is AudioStreamWAV, "the built sound")
	assert_true(voice.volume_db <= 0.0)


func test_mute_and_a_zero_volume_stop_sounds_from_starting() -> void:
	prefs.audio_muted = true
	assert_true(not audio.play("ui_click"), "muted")
	prefs.audio_muted = false
	prefs.audio_master = 0
	assert_true(not audio.play("ui_click"), "master at zero")
	prefs.audio_master = 80
	prefs.audio_ui = 0
	assert_true(not audio.play("ui_click"), "the interface bus at zero")
	prefs.audio_ui = 80
	assert_true(audio.play("ui_click"), "and it plays again once the volume is back")


func test_many_quick_sounds_reuse_the_voices_without_error() -> void:
	for i in 40:
		audio.play("card_flip")
	await frames(2)
	assert_true(_playing() <= FcAudio.VOICES, "never more voices than the pool has")


func test_every_button_in_the_app_clicks_and_a_button_can_opt_out() -> void:
	var app := FcApp.new()
	app.preferences = prefs
	prefs.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_audio")
	host.add_child(app)
	app.setup()
	await frames(2)
	assert_true(FcAudio.current == app.audio)
	var button := Button.new()
	app.host.content.add_child(button)
	button.pressed.emit()
	assert_eq(app.audio.requested.back(), "ui_click")
	var quiet := Button.new()
	quiet.set_meta("silent", true)
	app.host.content.add_child(quiet)
	var before := app.audio.requested.size()
	quiet.pressed.emit()
	assert_eq(app.audio.requested.size(), before, "a button can opt out")
	FcSafeFile.remove_tree("user://test_saves_live_audio")


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


func test_a_pack_reveal_asks_for_the_flip_and_the_sting_of_what_was_pulled() -> void:
	var reveal := _reveal(["common", "epic", "common"])
	await seconds(1.0)
	assert_true("pack_tear" in audio.requested, "the pack tearing has its sound")
	audio.requested.clear()
	reveal.reveal_next()
	var tier0 := FcRarityStyle.intensity("common")
	assert_eq(audio.requested, ["card_flip", "rarity_%d" % clampi(tier0, 0, 4)])
	await seconds(0.7)
	audio.requested.clear()
	reveal.reveal_next()
	assert_eq(audio.requested, ["card_flip", "rarity_%d" % clampi(FcRarityStyle.intensity("epic"), 0, 4)], "a bigger pull gets its bigger sting")


func test_skipping_a_reveal_is_quiet() -> void:
	var reveal := _reveal(["common", "epic"])
	await seconds(1.0)
	audio.requested.clear()
	reveal.reveal_next(false)
	assert_true(not ("rarity_0" in audio.requested) and not audio.requested.any(func(id: String) -> bool: return id.begins_with("rarity_")), "no sting when the reveal is skipped")


func test_the_game_is_fully_usable_with_the_sound_off() -> void:
	prefs.audio_muted = true
	var reveal := _reveal(["common", "legendary"])
	await seconds(1.0)
	reveal.reveal_next()
	await seconds(0.7)
	reveal.reveal_next()
	await seconds(1.0)
	assert_eq(reveal.stage, FcPackReveal.Stage.SUMMARY, "the reveal finishes exactly the same")
	assert_eq(_playing(), 0, "and nothing was heard")
