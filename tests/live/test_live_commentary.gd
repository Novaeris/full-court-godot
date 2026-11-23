extends FcLiveTestCase
## Broadcast pass 2, M6 in a real scene: the screen shows the analyst, narrator and stadium-announcer lines from the commentary booth as captions
## (never from a made-up fact), the PA chime plays with an announcer line, the arena ambience follows the game and goes away when the screen
## does, a captions-only booth ducks nothing, a seek starts the commentary afresh, and the broadcast music follows its setting.

const PREFS := "user://test_preferences_live_commentary.cfg"

var game: Dictionary = {}
var audio: FcAudio
var prefs: FcPreferences


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	var world := FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ratings := FcPlayerRatings.load_default()
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(12))
	game = {"box": box, "log": sim.recorder}
	prefs = FcPreferences.new(PREFS)
	audio = FcAudio.new(prefs)
	host.add_child(audio)
	FcAudio.current = audio


func after_each() -> void:
	if FcAudio.current == audio:
		FcAudio.current = null
	DirAccess.remove_absolute(PREFS)
	super.after_each()


func _screen(with_prefs: FcPreferences = null) -> FcReplayScreen:
	host.size = Vector2(1100, 900)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false, with_prefs)
	screen.size = Vector2(1100, 880)
	host.add_child(screen)
	return screen


func test_the_booth_lines_appear_as_captions_and_come_from_recorded_facts() -> void:
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	var analyst := {}
	var announcer := {}
	var chimes := 0
	for i in 300:
		audio.requested.clear()
		screen.advance(30.0)   # far longer than any line: every event gets the voice to itself
		if screen.analyst_label.text != "":
			analyst[screen.analyst_label.text] = true
		if screen.announcer_label.text != "":
			announcer[screen.announcer_label.text] = true
		if audio.requested.has("pa_chime"):
			chimes += 1
		if not screen.is_playing():
			break
	assert_true(analyst.size() > 2, "the analyst and narrator speak (%d lines)" % analyst.size())
	assert_true(announcer.size() > 5, "the stadium announcer speaks (%d lines)" % announcer.size())
	assert_true(chimes > 0, "the PA chime precedes announcements")
	var all_text := ""
	for t in announcer:
		all_text += t + "\n"
	assert_true(all_text.contains("number ") and all_text.contains("Final score") or all_text.contains("End of the"), "announcements carry display numbers and scores")
	# every analyst line is one of the booth's own events for some event of this game
	var known := {}
	for i in screen.timeline.size():
		for ev in FcCommentaryEvents.at(screen.timeline, i):
			known[str(ev["text"])] = true
	for t in analyst:
		assert_true(known.has(t), "%s is a recorded-fact line" % t)
	for t in announcer:
		assert_true(known.has(t))


func test_a_captions_only_booth_never_ducks_the_crowd() -> void:
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	for i in 80:
		screen.advance(30.0)
		assert_eq(audio.ducking.offset_db, 0.0, "captions do not duck")
		assert_true(not audio.ducking.is_speaking())
	assert_eq(screen.booth.sinks.size(), 1)
	assert_true(not screen.booth.sinks[0].has_voice())


func test_a_voice_sink_would_duck_while_it_speaks() -> void:
	var screen := await _screen()
	await frames(2)
	var voice := FcRecordingSink.new()
	screen.booth.add_sink(voice)
	screen.toggle_play()
	var ducked := false
	for i in 120:
		screen.advance(0.9)
		audio.advance(0.3)
		if audio.ducking.is_speaking():
			ducked = true
			assert_true(audio.effective_bus_db("Crowd") <= audio._db(audio.bus_percent("Crowd")), "the crowd is at or below its setting while a voice speaks")
	assert_true(ducked and not voice.spoken.is_empty(), "a voice sink is spoken to, and the audio ducks while it speaks")
	screen.toggle_play()
	screen.booth.tick(1.0e6)
	audio.advance(3.0)
	assert_eq(audio.ducking.offset_db, 0.0, "and the crowd is back when it stops")


func test_a_jump_starts_the_commentary_afresh_and_clears_the_lines() -> void:
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	for i in 60:
		screen.advance(30.0)
	assert_true(screen.caption_sink.history.size() > 3)
	screen.seek(screen.model.start_index() + 5, false)
	assert_eq(screen.analyst_label.text, "")
	assert_eq(screen.announcer_label.text, "")
	assert_eq(screen.booth.arbiter.current, {}, "the booth forgot what it just said")
	assert_eq(screen.caption_sink.lines, {})


func test_captions_off_hides_the_new_lines_too() -> void:
	prefs.sound_captions = false
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	for i in 60:
		screen.advance(30.0)
		assert_eq(screen.analyst_label.text, "")
		assert_eq(screen.announcer_label.text, "")
		assert_eq(screen.commentary_label.text, "")


func test_the_hud_hides_all_three_caption_lines() -> void:
	var screen := await _screen()
	await frames(2)
	screen.set_hud("minimal")
	assert_true(not screen.analyst_label.visible and not screen.announcer_label.visible and not screen.commentary_label.visible)
	screen.set_hud("full")
	assert_true(screen.analyst_label.visible and screen.announcer_label.visible)


func test_the_ambience_follows_the_game_and_leaves_with_the_screen() -> void:
	var screen := await _screen()
	await frames(2)
	assert_true(not audio.active_loops().is_empty(), "the ambience bed starts with the replay")
	var quiet_i := -1
	var loud_i := -1
	for i in range(screen.model.start_index(), screen.model.size()):
		var l := FcAmbienceModel.level_at(screen.timeline, i)
		if quiet_i < 0 and l < 0.35:
			quiet_i = i
		if l > 0.7:
			loud_i = i
	assert_true(quiet_i >= 0 and loud_i >= 0)
	screen.seek(quiet_i, false)
	for k in 40:
		audio.advance(0.1)
	assert_true(audio.loop_level("ambience_low") > 0.3, "a quiet moment sounds quiet: %s" % str(audio.loop_level("ambience_low")))
	screen.seek(loud_i, false)
	for k in 40:
		audio.advance(0.1)
	assert_true(audio.loop_level("ambience_high") > audio.loop_level("ambience_low"), "a big moment sounds big")
	screen.queue_free()
	await frames(2)
	for k in 60:
		audio.advance(0.1)
	assert_eq(audio.active_loops(), [], "the ambience stops when the replay screen goes")


func test_broadcast_music_follows_its_setting_and_the_mode() -> void:
	var screen := await _screen(prefs)
	await frames(2)
	for k in 30:
		audio.advance(0.1)
	assert_eq(audio.loop_level("music_broadcast"), 0.0, "off by default")
	prefs.broadcast_music = true
	screen.set_mode("broadcast")
	for k in 40:
		audio.advance(0.1)
	assert_eq(audio.loop_level("music_broadcast"), 1.0, "on in the Broadcast mode when the player wants it")
	screen.set_mode("replay")
	for k in 40:
		audio.advance(0.1)
	assert_eq(audio.loop_level("music_broadcast"), 0.0, "and gone in the review modes")
	prefs.broadcast_music = false
	DirAccess.remove_absolute(PREFS)
