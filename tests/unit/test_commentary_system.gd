extends FcTestCase
## Broadcast pass 2, M6: structured commentary (roles, facts, priorities), the arbiter (one voice, repetition control, preemption), the sinks
## (captions now, any voice later), the booth that joins them, and the audio mixing it drives (ducking, crowd intensity). All from recorded data,
## all offline.

const SEEDS := [3, 12, 77, 404, 9001]
var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)
	ratings = FcPlayerRatings.load_default()


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


func _ev(role: String, priority: int, text: String, key: String, cooldown: float = 0.0) -> Dictionary:
	return {"index": 0, "role": role, "kind": "t", "text": text, "priority": priority, "key": key, "cooldown": cooldown, "source": FcPresentationEvent.SIM_RECORDED, "facts": {}, "cue": ""}


# --- ducking ---------------------------------------------------------------------------------------------------------------------

func test_ducking_ramps_down_fast_and_back_slowly_never_past_the_target() -> void:
	var d := FcDuckingModel.new()
	assert_eq(d.advance(1.0), 0.0, "no voice, no ducking")
	d.set_speaking("announcer", true)
	var last := 0.0
	for i in 40:
		var now := d.advance(0.01)
		assert_true(now <= last and now >= -9.0, "a smooth fall that stops at the target")
		last = now
	assert_eq(last, -9.0)
	d.set_speaking("announcer", false)
	var attack_time := 0.0
	var back := -9.0
	var steps := 0
	while back < 0.0 and steps < 1000:
		var next := d.advance(0.01)
		assert_true(next >= back and next <= 0.0, "a smooth rise that stops at 0")
		back = next
		steps += 1
	assert_true(steps * 0.01 > 0.4, "the release is slower than the attack (%.2f s)" % (steps * 0.01))
	attack_time = 9.0 / FcDuckingModel.ATTACK_DB_PER_SECOND
	assert_true(attack_time < steps * 0.01)


func test_the_announcer_ducks_deeper_and_only_background_buses_duck() -> void:
	var d := FcDuckingModel.new()
	d.set_speaking("color", true)
	assert_eq(d.target_db(), -6.0)
	d.set_speaking("announcer", true)
	assert_eq(d.target_db(), -9.0, "the deepest voice decides")
	d.advance(1.0)
	for b in ["Crowd", "Ambience", "Music"]:
		assert_eq(d.offset_for(b), -9.0)
	for b in ["UI", "SFX", "Commentary", "Announcer"]:
		assert_eq(d.offset_for(b), 0.0, "%s never ducks itself or the effects" % b)
	d.set_speaking("nonsense", true)
	assert_true(d.is_speaking(), "the real voices still count")
	d.set_speaking("color", false)
	d.set_speaking("announcer", false)
	assert_true(not d.is_speaking())


# --- crowd intensity -----------------------------------------------------------------------------------------------------------------

func test_ambience_weights_crossfade_and_add_up() -> void:
	for l in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0, -3.0, 7.0]:
		var w := FcAudio.ambience_weights(l)
		assert_true(absf(float(w["ambience_low"]) + float(w["ambience_mid"]) + float(w["ambience_high"]) - 1.0) < 0.0001, "weights add up at %s" % str(l))
	assert_eq(FcAudio.ambience_weights(0.0), {"ambience_low": 1.0, "ambience_mid": 0.0, "ambience_high": 0.0})
	assert_eq(FcAudio.ambience_weights(0.5), {"ambience_low": 0.0, "ambience_mid": 1.0, "ambience_high": 0.0})
	assert_eq(FcAudio.ambience_weights(1.0), {"ambience_low": 0.0, "ambience_mid": 0.0, "ambience_high": 1.0})
	assert_eq(FcAudio.ambience_weights(0.25)["ambience_low"], 0.5)


func test_crowd_intensity_follows_the_game() -> void:
	var late_close := []
	var early := []
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var a := FcAmbienceModel.level_at(t, i)
			assert_eq(a, FcAmbienceModel.level_at(t, i), "deterministic")
			assert_true(a >= 0.0 and a <= 1.0)
			var snap := t.snapshot(i)
			if bool(snap["clutch"]) and int(t.model.entries[i]["points"]) > 0:
				late_close.append(a)
			elif int(snap["period"]) == 1 and absi(int(snap["lead"])) > 6:
				early.append(a)
	assert_true(not late_close.is_empty() and not early.is_empty())
	assert_true(_mean(late_close) > _mean(early) + 0.3, "clutch scoring is much louder than early, uneventful play")
	assert_eq(FcAmbienceModel.level_at(null, 0), 0.0)


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(maxi(1, values.size()))


# --- commentary events ----------------------------------------------------------------------------------------------------------------

func test_events_are_complete_deterministic_and_the_play_by_play_is_the_existing_commentary() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var events := FcCommentaryEvents.at(t, i)
			assert_eq(events, FcCommentaryEvents.at(t, i), "deterministic")
			for ev in events:
				assert_true(ev["role"] in FcCommentaryEvents.ROLES)
				assert_true(str(ev["text"]) != "" and str(ev["key"]) != "" and int(ev["priority"]) > 0 and int(ev["priority"]) <= 100)
				assert_true(ev["source"] in [FcPresentationEvent.SIM_RECORDED, FcPresentationEvent.DERIVED_FROM_RECORDED, FcPresentationEvent.PRESENTATION])
				assert_eq(int(ev["index"]), i)
				if ev["role"] == FcCommentaryEvents.ROLE_PBP:
					assert_eq(ev["text"], FcCommentary.line_at(t, i), "the play-by-play role is the established commentary")
	assert_eq(FcCommentaryEvents.at(null, 0), [])


func test_every_role_speaks_somewhere_in_real_games() -> void:
	var seen := {}
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			for ev in FcCommentaryEvents.at(t, i):
				seen[str(ev["role"])] = true
				seen["kind:" + str(ev["kind"])] = true
	for role in FcCommentaryEvents.ROLES:
		assert_true(seen.has(role), "the %s role is used" % role)
	for kind in ["shooting", "foul_trouble", "lead_changes", "run", "basket", "foul", "period_end", "final"]:
		assert_true(seen.has("kind:" + kind), "%s lines occur" % kind)


func test_the_facts_behind_every_line_are_the_recorded_numbers() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			for ev in FcCommentaryEvents.at(t, i):
				var f: Dictionary = ev["facts"]
				var text := str(ev["text"])
				match str(ev["kind"]):
					"shooting":
						var line := t.player_line(i, int(f["player_id"]))
						assert_eq([int(f["fgm"]), int(f["fga"])], [int(line["fgm"]), int(line["fga"])])
						assert_true(text.contains("%d of %d" % [int(f["fgm"]), int(f["fga"])]))
					"foul_trouble":
						assert_eq(int(f["pf"]), int(t.player_line(i, int(f["player_id"]))["pf"]))
						assert_true(text.contains(str(int(f["pf"]))) and int(f["pf"]) >= FcCommentaryEvents.FOUL_TROUBLE)
					"rebounds":
						assert_eq(int(f["reb"]), int(t.player_line(i, int(f["player_id"]))["reb"]))
					"turnovers":
						assert_eq(int(f["tov"]), int(t.team_line(i, int(f["side"]))["tov"]))
					"lead_changes":
						assert_eq(int(f["lead_changes"]), int(t.snapshot(i)["lead_changes"]))
					"run":
						assert_eq(int(f["points"]), int(t.snapshot(i)["run"]["points"]))
					"comeback":
						assert_true(int(f["deficit"]) >= FcCommentaryEvents.COMEBACK_DEFICIT)
					"milestone":
						assert_eq(int(f["points"]), int(t.snapshot(i)["milestone"]["points"]))
					"period_end", "final":
						assert_eq([int(f["home"]), int(f["away"])], [int(t.snapshot(i)["home"]), int(t.snapshot(i)["away"])])
					"basket":
						assert_eq(int(t.model.entries[i]["side"]), 0, "the stadium announces home baskets")


func test_no_line_talks_about_speed_distance_or_position() -> void:
	var banned := ["feet", "foot", "mph", "sprint", "fast", "speed", "distance", "ran ", "yards", "metre", "meter"]
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			for ev in FcCommentaryEvents.at(t, i):
				for word in banned:
					assert_true(not str(ev["text"]).to_lower().contains(word), "%s: %s" % [word, ev["text"]])


func test_the_announcer_uses_display_numbers() -> void:
	var t := _timeline(12)
	var numbers := FcJerseyNumbers.for_box(t.model.box)
	var checked := 0
	for i in t.size():
		for ev in FcCommentaryEvents.at(t, i):
			if ev["role"] == FcCommentaryEvents.ROLE_ANNOUNCER and str(ev["kind"]) in ["basket", "foul"]:
				var number := int(numbers.get(int(ev["facts"]["player_id"]), 0))
				if number > 0:
					assert_true(str(ev["text"]).contains("number %d," % number), str(ev["text"]))
					checked += 1
				assert_eq(ev["cue"], "pa_chime")
	assert_true(checked > 5)


# --- the arbiter ------------------------------------------------------------------------------------------------------------------------

func test_one_voice_at_a_time_and_a_busy_voice_drops_the_rest() -> void:
	var a := FcCommentaryArbiter.new()
	var first := a.offer([_ev("play_by_play", 60, "Smith makes the jumper and the crowd goes wild.", "k1")], 0.0)
	assert_eq(first["line"]["key"], "k1")
	assert_true(a.is_speaking(1.0))
	var busy := a.offer([_ev("play_by_play", 50, "Jones misses.", "k2")], 1.0)
	assert_eq(busy["line"], {}, "still speaking: the new line is dropped, not queued")
	assert_eq(busy["dropped"][0]["reason"], "busy")
	var later := a.offer([_ev("play_by_play", 50, "Jones misses.", "k3")], a.speaker_until + 0.1)
	assert_eq(later["line"]["key"], "k3", "free again")


func test_a_big_play_by_play_line_preempts_but_a_small_one_does_not() -> void:
	var a := FcCommentaryArbiter.new()
	a.offer([_ev("color", 35, "Smith is 5 of 10 from the field and shooting well tonight.", "c1")], 0.0)
	var small := a.offer([_ev("play_by_play", 40, "Jones misses.", "p1")], 0.5)
	assert_eq(small["line"], {}, "a small play does not interrupt the analyst")
	var big := a.offer([_ev("play_by_play", 85, "Jones hits the three!", "p2")], 0.6)
	assert_eq(big["line"]["key"], "p2")
	assert_true(bool(big["preempted"]))
	var a2 := FcCommentaryArbiter.new()
	a2.offer([_ev("announcer", 45, "Basket by number 24, Herrera.", "a1")], 0.0)
	var narr := a2.offer([_ev("narrative", 70, "We're in clutch time: HOU 90, MEX 88.", "n1")], 0.3)
	assert_eq(narr["line"], {}, "a lower-ranked role cannot interrupt the announcer")


func test_a_minor_play_by_play_line_is_never_spoken() -> void:
	var a := FcCommentaryArbiter.new()
	var r := a.offer([_ev("play_by_play", 40, "Jones misses.", "k1")], 0.0)
	assert_eq(r["line"], {})
	assert_eq(r["dropped"][0]["reason"], "minor")
	assert_eq(a.offer([_ev("color", 35, "Smith has 3 fouls.", "k2")], 0.1)["line"]["key"], "k2", "so the analyst gets the floor")


func test_the_right_role_wins_when_several_speak_at_once() -> void:
	var a := FcCommentaryArbiter.new()
	var r := a.offer([_ev("color", 90, "c", "k1"), _ev("narrative", 60, "n", "k2"), _ev("announcer", 30, "a", "k3"), _ev("play_by_play", 60, "p", "k4")], 0.0)
	assert_eq(r["line"]["role"], "play_by_play", "rank beats priority")
	assert_eq((r["dropped"] as Array).size(), 3)
	var b := FcCommentaryArbiter.new()
	assert_eq(b.offer([_ev("color", 20, "x", "k1"), _ev("color", 40, "y", "k2")], 0.0)["line"]["key"], "k2", "then priority")


func test_nothing_repeats_too_soon() -> void:
	var a := FcCommentaryArbiter.new()
	a.offer([_ev("color", 35, "Smith has 3 fouls.", "color:pf:1:3", 12.0)], 0.0)
	var same_key := a.offer([_ev("color", 35, "Smith has three fouls now.", "color:pf:1:3", 12.0)], 5.0)
	assert_eq(same_key["dropped"][0]["reason"], "repeat_key")
	var role_gap := a.offer([_ev("color", 35, "Jones has 4 rebounds.", "color:reb:2:4", 12.0)], 5.0)
	assert_eq(role_gap["dropped"][0]["reason"], "role_gap", "the analyst keeps a gap between lines")
	var same_text := a.offer([_ev("color", 35, "Smith has 3 fouls.", "other", 0.0)], 30.0)
	assert_eq(same_text["dropped"][0]["reason"], "repeat_text", "the same words are not said twice within 90 s")
	var fine := a.offer([_ev("color", 35, "Smith has 3 fouls.", "other2", 0.0)], 130.0)
	assert_eq(fine["line"]["key"], "other2", "much later it may be said again")


func test_durations_are_estimated_from_the_text() -> void:
	assert_eq(FcCommentaryArbiter.duration_of("Hi"), FcCommentaryArbiter.MIN_SECONDS)
	assert_true(FcCommentaryArbiter.duration_of("x".repeat(140)) > 9.9)


func test_whole_games_never_overlap_voices_or_repeat_text() -> void:
	for s in SEEDS:
		for speed in [1.0, 4.0]:
			var t := _timeline(s)
			var booth := FcCommentaryBooth.new()
			var voice := FcRecordingSink.new()
			booth.add_sink(voice)
			var now := 0.0
			var starts: Array = []
			for i in range(t.model.start_index(), t.size()):
				var result := booth.on_event(t, i, now)
				if not (result["line"] as Dictionary).is_empty():
					starts.append({"at": now, "line": result["line"], "preempted": result["preempted"]})
				now += t.model.dwell(i) / speed
			assert_true(voice.spoken.size() > 20, "the booth speaks through a game (seed %d: %d lines)" % [s, voice.spoken.size()])
			var last_text := {}
			for k in starts.size():
				var text := str(starts[k]["line"]["text"])
				if last_text.has(text):
					assert_true(float(starts[k]["at"]) - float(last_text[text]) >= FcCommentaryArbiter.TEXT_REPEAT_SECONDS, "%s repeated too soon" % text)
				last_text[text] = float(starts[k]["at"])
				if k > 0 and not bool(starts[k]["preempted"]):
					var before: Dictionary = starts[k - 1]
					var ended := float(before["at"]) + FcCommentaryArbiter.duration_of(str(before["line"]["text"]))
					assert_true(float(starts[k]["at"]) >= ended - 0.0001, "seed %d speed %s: a new voice began while the last was speaking" % [s, speed])
			# whole-game repeatability
			var again := FcCommentaryBooth.new()
			var voice2 := FcRecordingSink.new()
			again.add_sink(voice2)
			var now2 := 0.0
			for i in range(t.model.start_index(), t.size()):
				again.on_event(t, i, now2)
				now2 += t.model.dwell(i) / speed
			assert_eq(voice2.spoken, voice.spoken, "the same game commentates identically")


# --- sinks and the booth ------------------------------------------------------------------------------------------------------------------

func test_the_caption_sink_keeps_the_latest_line_of_each_role() -> void:
	var sink := FcCaptionSink.new()
	assert_eq(sink.kind(), FcCommentarySink.KIND_CAPTION)
	assert_true(not sink.has_voice(), "captions never duck the crowd")
	sink.speak(_ev("color", 35, "Smith has 3 fouls.", "k1"))
	sink.speak(_ev("announcer", 45, "Basket by number 3.", "k2"))
	assert_eq(sink.latest("color"), "Smith has 3 fouls.")
	assert_eq(sink.latest("narrative"), "")
	for i in FcCaptionSink.HISTORY + 20:
		sink.speak(_ev("color", 35, "line %d" % i, "k"))
	assert_eq(sink.history.size(), FcCaptionSink.HISTORY, "the history is capped")
	sink.stop()
	assert_eq(sink.latest("color"), "")
	for k in FcCommentarySink.KINDS:
		assert_true(k in ["caption", "recorded_voice", "tts", "ai"])
	assert_eq(FcRecordingSink.new().kind(), "tts")


func test_the_booth_reports_voices_so_audio_can_duck_and_captions_never_do() -> void:
	var t := _timeline(12)
	var events: Array = []
	var voice_booth := FcCommentaryBooth.new()
	voice_booth.add_sink(FcRecordingSink.new())
	voice_booth.on_speaking = func(role: String, on: bool) -> void: events.append([role, on])
	var caption_events: Array = []
	var caption_booth := FcCommentaryBooth.new()
	caption_booth.add_sink(FcCaptionSink.new())
	caption_booth.on_speaking = func(role: String, on: bool) -> void: caption_events.append([role, on])
	var now := 0.0
	for i in range(t.model.start_index(), t.model.start_index() + 120):
		voice_booth.on_event(t, i, now)
		caption_booth.on_event(t, i, now)
		now += t.model.dwell(i)
	assert_true(events.size() > 4, "a voice sink reports who speaks")
	assert_eq(caption_events, [], "a captions-only booth ducks nothing")
	assert_eq(events[0][1], true)
	var depth := 0
	for e in events:
		depth += 1 if e[1] else -1
		assert_true(depth >= 0 and depth <= 1, "at most one voice at a time, every start has its stop")
	voice_booth.tick(now + 100.0)
	assert_eq(voice_booth.speaking_role, "", "a finished voice stops")
	voice_booth.reset()
	assert_eq(voice_booth.speaking_role, "")


func test_a_booth_with_two_sinks_feeds_both_the_same_line() -> void:
	var t := _timeline(12)
	var booth := FcCommentaryBooth.new()
	var captions := FcCaptionSink.new()
	var voice := FcRecordingSink.new()
	booth.add_sink(captions).add_sink(voice)
	for i in range(t.model.start_index(), t.size()):
		var r := booth.on_event(t, i, float(i) * 20.0)
		if not (r["line"] as Dictionary).is_empty():
			assert_eq(voice.spoken.back(), r["line"])
			assert_eq(captions.latest(str(r["line"]["role"])), str(r["line"]["text"]))
	assert_true(voice.spoken.size() > 50)
