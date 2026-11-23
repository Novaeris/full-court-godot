extends FcLiveTestCase
## The replay screen's crowd and court sounds and captions (master plan B3): playing and stepping forward make the sounds the mapping
## says, scrubbing and stepping back are silent, captions follow the setting, and nothing about the game changes.

const PREFS := "user://test_preferences_live_broadcast_audio.cfg"

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


func _screen() -> FcReplayScreen:
	host.size = Vector2(1100, 800)
	var screen := FcReplayScreen.new().setup(FcReplayModel.build(game["log"], game["box"]), [], false)
	screen.size = Vector2(1100, 780)
	host.add_child(screen)
	return screen


func test_playing_makes_each_events_sounds_and_the_caption_follows() -> void:
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	var sounded := 0
	for i in 60:
		var before := screen.current_index()
		audio.requested.clear()   # the audio keeps only its last 40 requests, so compare event by event
		screen.advance(10.0)      # long enough to move on by one event
		if screen.current_index() == before:
			continue
		var expected := FcBroadcastAudio.cues_at(screen.timeline, screen.current_index())
		var heard: Array[String] = []
		heard.assign(audio.requested.filter(func(id: String) -> bool: return id != "pa_chime"))   # the stadium announcer's chime (M6) is not one of the crowd and court cues
		assert_eq(heard, expected, "event %d asked for exactly the sounds the mapping gives, in order" % screen.current_index())
		assert_eq(screen.sound_caption.text, FcBroadcastAudio.caption_for(expected), "and its caption")
		sounded += expected.size()
	assert_true(sounded > 20, "the sample had many sounds (%d)" % sounded)


func test_stepping_forward_sounds_but_stepping_back_and_scrubbing_are_silent() -> void:
	var screen := await _screen()
	await frames(2)
	var foul_index := -1
	for e in screen.model.entries:
		if e["type"] == FcGameEventLog.EV_FOUL:
			foul_index = e["index"]
			break
	assert_true(foul_index > 0)
	screen.seek(foul_index - 1, false)
	audio.requested.clear()
	screen.seek(foul_index, false)   # a jump or scrub
	assert_true(audio.requested.is_empty(), "scrubbing is silent")
	assert_eq(screen.sound_caption.text, "")
	screen.seek(foul_index - 1, false)
	screen.step(1)
	assert_eq(screen.current_index(), screen.model.step(foul_index - 1, 1, screen.filter))
	if screen.current_index() == foul_index:
		assert_true(audio.requested.has(FcBroadcastAudio.CUE_WHISTLE), "stepping onto a foul blows the whistle")
		assert_true(screen.sound_caption.text.contains("(whistle)"), screen.sound_caption.text)
	audio.requested.clear()
	screen.step(-1)
	assert_true(audio.requested.is_empty(), "stepping back is silent")


func test_captions_can_be_turned_off_and_the_game_data_never_changes() -> void:
	var rows_before := FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows)
	var box_before := FcOnlineCrypto.canonical((game["box"] as FcBoxScore).to_dict())
	var screen := await _screen()
	await frames(2)
	prefs.sound_captions = false
	screen.toggle_play()
	for i in 80:
		screen.advance(10.0)
		assert_eq(screen.sound_caption.text, "", "captions are off")
		assert_eq(screen.commentary_label.text, "", "and so is the commentary text")
	prefs.sound_captions = true
	screen.toggle_play()
	screen.toggle_play()
	var captioned := false
	var commented := false
	for i in 120:
		screen.advance(10.0)
		captioned = captioned or screen.sound_caption.text != ""
		commented = commented or screen.commentary_label.text != ""
	assert_true(captioned, "with captions on, some sound is described")
	assert_true(commented, "with captions on, the commentary says something")
	assert_eq(FcOnlineCrypto.canonical((game["log"] as FcGameEventLog).rows), rows_before)
	assert_eq(FcOnlineCrypto.canonical((game["box"] as FcBoxScore).to_dict()), box_before)


func test_a_muted_game_asks_for_sounds_but_plays_none_and_still_captions() -> void:
	prefs.audio_muted = true
	var screen := await _screen()
	await frames(2)
	screen.toggle_play()
	var played := 0
	var captioned := false
	for i in 60:
		screen.advance(10.0)
		captioned = captioned or screen.sound_caption.text != ""
	for id in audio.requested:
		if FcBroadcastAudio.all_cues().has(id):
			played += 1 if audio.play(id) else 0
	assert_eq(played, 0, "muted: nothing starts")
	assert_true(captioned, "captions still describe the sounds for a player who has the sound off")
