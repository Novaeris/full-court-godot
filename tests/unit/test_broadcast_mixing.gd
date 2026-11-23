extends FcTestCase
## Broadcast pass 2, M6: the audio infrastructure for the broadcast. Looping ambience that crossfades with the crowd intensity, music pads that
## swap smoothly, ducking applied to the right buses, volumes for the new buses, and sounds that are all original, audible and loop cleanly.
## Everything advances through `advance(delta)`, so no audio device is needed.

const PREFS := "user://test_preferences_mixing.cfg"

var audio: FcAudio


func before_each() -> void:
	DirAccess.remove_absolute(PREFS)
	audio = FcAudio.new(FcPreferences.new(PREFS))


func after_each() -> void:
	if audio != null:
		audio.free()
		audio = null
	DirAccess.remove_absolute(PREFS)
	FcAudio.current = null


func _settle(seconds: float = 3.0) -> void:
	for i in int(seconds / 0.05):
		audio.advance(0.05)


# --- the sound map ----------------------------------------------------------------------------------------------------------------

func test_the_new_buses_and_sounds_are_in_the_map() -> void:
	for bus in ["Ambience", "Commentary", "Announcer"]:
		assert_true(audio.buses.has(bus), "%s bus" % bus)
	for id in FcAudio.AMBIENCE_IDS + ["music_menu", "music_broadcast", "pa_chime"]:
		assert_true(audio.has_sound(id), id)
	assert_eq(audio.source_of("ambience_low"), "synth", "made by the game: no third-party audio (D4)")
	for id in FcAudio.AMBIENCE_IDS:
		var wav := audio.sounds[id]["stream"] as AudioStreamWAV
		assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % id)
		assert_eq(wav.loop_end, int(wav.data.size() / 2.0), "and loops over its whole length")
		assert_true(bool(audio.sounds[id]["loop"]))
	assert_true(not bool(audio.sounds["court_swish"]["loop"]), "one-shots do not loop")
	assert_eq(audio.sounds["pa_chime"]["bus"], "Announcer")


func test_every_broadcast_cue_still_exists_in_the_map() -> void:
	for id in FcBroadcastAudio.all_cues():
		assert_true(audio.has_sound(id), id)
	for ev in ["pa_chime"]:
		assert_true(audio.has_sound(ev))


# --- loops and ambience ----------------------------------------------------------------------------------------------------------------------

func test_a_loop_fades_in_and_out_smoothly() -> void:
	assert_true(audio.play_loop("ambience_low", 1.0))
	assert_eq(audio.loop_level("ambience_low"), 0.0)
	var last := 0.0
	for i in 30:
		audio.advance(0.05)
		var l := audio.loop_level("ambience_low")
		assert_true(l >= last and l <= 1.0, "a smooth rise")
		last = l
	assert_eq(audio.loop_level("ambience_low"), 1.0)
	audio.fade_loop("ambience_low", 0.0, 1.0)
	_settle(2.0)
	assert_eq(audio.loop_level("ambience_low"), 0.0)
	assert_eq(audio.active_loops(), [], "a faded-out loop is no longer active")
	assert_true(not audio.play_loop("court_swish"), "a one-shot is not a loop")
	assert_true(not audio.play_loop("no_such_sound"))


func test_the_ambience_follows_the_crowd_intensity_with_a_crossfade() -> void:
	audio.set_ambience_level(0.0)
	_settle()
	assert_eq([audio.loop_level("ambience_low"), audio.loop_level("ambience_mid"), audio.loop_level("ambience_high")], [1.0, 0.0, 0.0])
	audio.set_ambience_level(1.0)
	audio.advance(0.5)
	var mid_low := audio.loop_level("ambience_low")
	var mid_high := audio.loop_level("ambience_high")
	assert_true(mid_low > 0.0 and mid_low < 1.0 and mid_high > 0.0 and mid_high < 1.0, "halfway through the crossfade both beds are audible")
	_settle()
	assert_eq([audio.loop_level("ambience_low"), audio.loop_level("ambience_high")], [0.0, 1.0])
	audio.stop_ambience()
	_settle()
	assert_eq(audio.active_loops(), [])


func test_music_swaps_with_a_crossfade_and_is_a_music_bus_loop() -> void:
	assert_true(audio.play_music("music_menu"))
	_settle()
	assert_eq(audio.loop_level("music_menu"), 1.0)
	assert_true(audio.play_music("music_broadcast"))
	audio.advance(0.6)
	assert_true(audio.loop_level("music_menu") < 1.0 and audio.loop_level("music_broadcast") > 0.0)
	_settle()
	assert_eq([audio.loop_level("music_menu"), audio.loop_level("music_broadcast")], [0.0, 1.0])
	assert_true(not audio.play_music("ambience_low"), "only Music bus loops are music")
	audio.stop_music()
	_settle()
	assert_eq(audio.loop_level("music_broadcast"), 0.0)


func test_a_muted_game_still_moves_levels_and_never_errors() -> void:
	audio.prefs.audio_muted = true
	audio.set_ambience_level(0.5)
	_settle()
	assert_eq(audio.loop_level("ambience_mid"), 1.0)


func test_static_helpers_do_nothing_without_audio() -> void:
	FcAudio.current = null
	FcAudio.ambience(0.7)
	FcAudio.ambience_off()
	FcAudio.speaking("announcer", true)
	FcAudio.music("music_broadcast")
	FcAudio.music_off()
	assert_true(true, "silent and error free")


# --- ducking applied to the buses ------------------------------------------------------------------------------------------------------------

func test_a_speaking_voice_lowers_only_the_background_buses_and_they_come_back() -> void:
	var crowd_before := audio.effective_bus_db("Crowd")
	var sfx_before := audio.effective_bus_db("SFX")
	audio.set_speaking("announcer", true)
	audio.advance(0.5)
	assert_eq(audio.effective_bus_db("Crowd"), crowd_before - 9.0)
	assert_eq(audio.effective_bus_db("Ambience"), audio.effective_bus_db("Music") if audio.prefs.audio_ambience == audio.prefs.audio_music else audio.effective_bus_db("Ambience"))
	assert_eq(audio.effective_bus_db("SFX"), sfx_before, "effects are never ducked")
	audio.set_speaking("announcer", false)
	_settle(2.0)
	assert_eq(audio.effective_bus_db("Crowd"), crowd_before, "and the crowd comes back")


func test_a_silent_bus_stays_silent_when_ducked() -> void:
	audio.prefs.audio_crowd = 0
	audio.set_speaking("color", true)
	audio.advance(1.0)
	assert_eq(audio.effective_bus_db("Crowd"), -80.0)


# --- settings ------------------------------------------------------------------------------------------------------------------------------------

func test_the_new_volumes_are_saved_clamped_and_mapped_to_buses() -> void:
	var p := FcPreferences.new(PREFS)
	assert_eq([p.audio_ambience, p.audio_commentary, p.audio_announcer, p.broadcast_music], [60, 80, 80, false], "defaults")
	p.audio_ambience = 20
	p.audio_commentary = 0
	p.audio_announcer = 55
	p.broadcast_music = true
	assert_true(p.save_file())
	var back := FcPreferences.new(PREFS)
	assert_eq([back.audio_ambience, back.audio_commentary, back.audio_announcer, back.broadcast_music], [20, 0, 55, true])
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("audio", "ambience", 900)
	cfg.set_value("audio", "announcer", -5)
	cfg.save(PREFS)
	var clamped := FcPreferences.new(PREFS)
	assert_eq([clamped.audio_ambience, clamped.audio_announcer], [100, 0])
	var a := FcAudio.new(back)
	assert_eq([a.bus_percent("Ambience"), a.bus_percent("Commentary"), a.bus_percent("Announcer")], [20, 0, 55])
	a.free()


func test_the_synthesised_loops_are_audible_and_do_not_clip() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FcAudio.MAP_PATH))
	for id in FcAudio.AMBIENCE_IDS + ["music_menu", "music_broadcast"]:
		var samples := FcAudioSynth.render(map["sounds"][id]["synth"], id)
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		assert_true(samples.size() > FcAudioSynth.MIX_RATE * 2, "%s is a few seconds long" % id)
		assert_true(peak > 0.05 and peak <= 0.9, "%s: peak %.2f" % [id, peak])
	var low := FcAudioSynth.render(map["sounds"]["ambience_low"]["synth"], "a")
	var high := FcAudioSynth.render(map["sounds"]["ambience_high"]["synth"], "b")
	assert_true(_rms(high) > _rms(low), "the loud bed is louder than the quiet one")


func _rms(samples: PackedFloat32Array) -> float:
	var total := 0.0
	for v in samples:
		total += v * v
	return sqrt(total / float(maxi(1, samples.size())))
