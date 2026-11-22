extends FcTestCase
## Broadcast audio (master plan B3): which sounds each event makes, their captions, the sounds themselves (built by the game, original),
## the crowd volume and the caption setting. The mapping is pure, so the same replay always sounds the same.

const SEEDS := [12, 13, 14, 21, 22, 23]
const PREFS := "user://test_preferences_broadcast_audio.cfg"

var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)


func after_each() -> void:
	DirAccess.remove_absolute(PREFS)


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


func _map() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/audio.json"))


func test_every_cue_the_game_can_make_is_in_the_sound_map_with_a_caption_entry() -> void:
	var sounds: Dictionary = _map()["sounds"]
	for id in FcBroadcastAudio.all_cues():
		assert_true(sounds.has(id), "%s is in data/ui/audio.json" % id)
		assert_true(["SFX", "Crowd"].has(str(sounds[id]["bus"])), "%s is on the SFX or Crowd bus" % id)
		assert_true(sounds[id].has("synth"), "%s is built by the game (no third-party audio)" % id)
		assert_true(FcBroadcastAudio.CAPTIONS.has(id))
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			for id in FcBroadcastAudio.cues_at(t, i):
				assert_true(FcBroadcastAudio.all_cues().has(id), "%s is a known cue" % id)


func test_the_new_sounds_render_loud_enough_short_enough_and_the_same_every_time() -> void:
	var sounds: Dictionary = _map()["sounds"]
	for id in FcBroadcastAudio.all_cues():
		var recipe: Dictionary = sounds[id]["synth"]
		var a := FcAudioSynth.render(recipe, id)
		var b := FcAudioSynth.render(recipe, id)
		assert_true(a.size() > 0, "%s has samples" % id)
		assert_eq(a, b, "%s is deterministic" % id)
		var loudest := 0.0
		for v in a:
			loudest = maxf(loudest, absf(v))
		assert_true(loudest > 0.1 and loudest <= FcAudioSynth.PEAK + 0.0001, "%s peak %.2f is audible and not clipping" % [id, loudest])
		assert_true(FcAudioSynth.duration_ms(recipe) <= 2500, "%s is at most 2.5 s" % id)


func test_each_event_makes_the_sounds_its_kind_calls_for() -> void:
	var seen := {}
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var e := t.model.entries[i]
			var cues := FcBroadcastAudio.cues_at(t, i)
			assert_true(cues.size() <= FcBroadcastAudio.MAX_CUES)
			var unique := {}
			for c in cues:
				assert_true(not unique.has(c), "no duplicate cue at event %d" % i)
				unique[c] = true
			match int(e["type"]):
				FcGameEventLog.EV_SHOT_MADE:
					assert_true(cues.has(FcBroadcastAudio.CUE_SWISH), "a made shot swishes")
					assert_eq(cues.has(FcBroadcastAudio.CUE_CHEER_SMALL) or cues.has(FcBroadcastAudio.CUE_CHEER_BIG), int(e["side"]) == 0, "the crowd cheers a HOME basket (event %d)" % i)
				FcGameEventLog.EV_SHOT_MISSED:
					assert_eq(cues, [FcBroadcastAudio.CUE_RIM] as Array[String])
				FcGameEventLog.EV_SHOT_BLOCKED:
					assert_true(cues.has(FcBroadcastAudio.CUE_BLOCK) and cues.has(FcBroadcastAudio.CUE_OH))
				FcGameEventLog.EV_FOUL:
					assert_true(cues.has(FcBroadcastAudio.CUE_WHISTLE))
				FcGameEventLog.EV_PERIOD_END, FcGameEventLog.EV_GAME_END:
					assert_true(cues.has(FcBroadcastAudio.CUE_BUZZER))
				FcGameEventLog.EV_REBOUND, FcGameEventLog.EV_SUBSTITUTION, FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_STARTER:
					assert_true(not cues.has(FcBroadcastAudio.CUE_WHISTLE) and not cues.has(FcBroadcastAudio.CUE_RIM), "quiet events stay quiet")
			for c in cues:
				seen[c] = true
	for id in FcBroadcastAudio.all_cues():
		assert_true(seen.has(id), "%s occurred in the sample" % id)


func test_a_home_win_is_cheered_and_a_home_loss_groaned_at_the_final_buzzer() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var cues := FcBroadcastAudio.cues_at(t, t.size() - 1)
		assert_true(cues.has(FcBroadcastAudio.CUE_BUZZER))
		var home_won := t.model.box.scores[0] > t.model.box.scores[1]
		assert_eq(cues.has(FcBroadcastAudio.CUE_CHEER_BIG), home_won, "seed %d" % s)
		assert_eq(cues.has(FcBroadcastAudio.CUE_GROAN), not home_won)


func test_the_mapping_is_repeatable_and_changes_nothing() -> void:
	var t := _timeline(12)
	var rows_before := FcOnlineCrypto.canonical(t.model.box.to_dict())
	for i in t.size():
		assert_eq(FcBroadcastAudio.cues_at(t, i), FcBroadcastAudio.cues_at(t, i))
	assert_eq(FcOnlineCrypto.canonical(t.model.box.to_dict()), rows_before)
	assert_eq(FcBroadcastAudio.cues_at(null, 3), [] as Array[String])
	assert_eq(FcBroadcastAudio.cues_at(FcBroadcastTimeline.build(null), 0), [] as Array[String])


func test_captions_describe_only_the_sounds_that_play() -> void:
	assert_eq(FcBroadcastAudio.caption_for([FcBroadcastAudio.CUE_SWISH] as Array[String]), "", "a swish needs no caption")
	assert_eq(FcBroadcastAudio.caption_for([FcBroadcastAudio.CUE_WHISTLE, FcBroadcastAudio.CUE_GROAN] as Array[String]), "(whistle) (crowd groans)")
	assert_eq(FcBroadcastAudio.caption_for([FcBroadcastAudio.CUE_CHEER_BIG, FcBroadcastAudio.CUE_CHEER_BIG] as Array[String]), "(crowd roars)", "no repeats")
	var t := _timeline(13)
	for i in t.size():
		var cues := FcBroadcastAudio.cues_at(t, i)
		var text := FcBroadcastAudio.caption_for(cues)
		assert_eq(text.contains("crowd cheers") or text.contains("crowd roars"), cues.has(FcBroadcastAudio.CUE_CHEER_SMALL) or cues.has(FcBroadcastAudio.CUE_CHEER_BIG), "a cheer is captioned exactly when it plays (event %d)" % i)


func test_crowd_volume_and_captions_are_preferences_that_save_and_reach_the_bus() -> void:
	var p := FcPreferences.new(PREFS)
	assert_eq([p.audio_crowd, p.sound_captions], [70, true])
	p.audio_crowd = 35
	p.sound_captions = false
	assert_true(p.save_file())
	var back := FcPreferences.new(PREFS)
	assert_eq([back.audio_crowd, back.sound_captions], [35, false])
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", 50)
	cfg.set_value("audio", "crowd", 900)
	cfg.save(PREFS)
	assert_eq(FcPreferences.new(PREFS).audio_crowd, 100, "clamped")
	var old := ConfigFile.new()   # a settings file from before this feature
	old.set_value("audio", "master", 50)
	old.save(PREFS)
	var from_old := FcPreferences.new(PREFS)
	assert_eq([from_old.audio_crowd, from_old.sound_captions], [70, true], "an older file gets the defaults")
	var audio := FcAudio.new(back)
	assert_eq(audio.bus_percent("Crowd"), 35)
	audio.setup_buses()
	assert_true(AudioServer.get_bus_index("Crowd") >= 0, "the Crowd bus exists")
	audio.apply_settings()
	assert_true(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Crowd")), FcAudio._db(35)))
	audio.free()
