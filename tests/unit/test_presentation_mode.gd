extends FcTestCase
## Presentation modes and HUD levels (Broadcast pass 2, M1): three genuinely different layouts, a HUD that removes things in steps, the
## shared playback state, and the two additive preferences (defaults, round trip, bad values).

const PREFS := "user://test_preferences_presentation.cfg"


func test_the_three_modes_have_different_layouts() -> void:
	var seen: Array = []
	for m in FcPresentationMode.MODES:
		var lay := FcPresentationMode.layout(m[0])
		assert_true(lay.has("camera") and lay.has("view") and lay.has("panels"))
		seen.append(str(lay["panels"]) + str(lay["camera"]) + str(lay["view"]))
	assert_eq(seen.size(), 3)
	assert_true(seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2], "no two modes share a layout")


func test_broadcast_is_immersive_and_analysis_is_informative() -> void:
	var b := FcPresentationMode.layout(FcPresentationMode.BROADCAST)
	assert_eq(b["camera"], "auto")
	assert_eq(b["view"], "3d")
	for p in [FcPresentationMode.P_FEED, FcPresentationMode.P_CAMERA, FcPresentationMode.P_LINEUPS, FcPresentationMode.P_TEAMS, FcPresentationMode.P_ROSTERS]:
		assert_true(not bool(b["panels"][p]), "broadcast hides %s" % p)
	var a := FcPresentationMode.layout(FcPresentationMode.ANALYSIS)
	assert_eq(a["view"], "flat")
	assert_eq(a["camera"], "manual")
	for p in [FcPresentationMode.P_FEED, FcPresentationMode.P_ROSTERS, FcPresentationMode.P_LINEUPS, FcPresentationMode.P_TEAMS]:
		assert_true(bool(a["panels"][p]), "analysis shows %s" % p)
	var r := FcPresentationMode.layout(FcPresentationMode.REPLAY)
	assert_true(bool(r["panels"][FcPresentationMode.P_SCRUBBER]) and bool(r["panels"][FcPresentationMode.P_HIGHLIGHTS]))


func test_hud_levels_remove_things_in_steps() -> void:
	for e in [FcPresentationMode.E_SCOREBUG, FcPresentationMode.E_OVERLAY, FcPresentationMode.E_BADGE, FcPresentationMode.E_CAPTIONS, FcPresentationMode.E_TRANSPORT]:
		assert_true(FcPresentationMode.hud_shows(FcPresentationMode.HUD_FULL, e))
		assert_true(not FcPresentationMode.hud_shows(FcPresentationMode.HUD_HIDDEN, e))
	assert_true(FcPresentationMode.hud_shows(FcPresentationMode.HUD_MINIMAL, FcPresentationMode.E_SCOREBUG))
	assert_true(FcPresentationMode.hud_shows(FcPresentationMode.HUD_MINIMAL, FcPresentationMode.E_OVERLAY))
	assert_true(not FcPresentationMode.hud_shows(FcPresentationMode.HUD_MINIMAL, FcPresentationMode.E_CAPTIONS))
	assert_true(not FcPresentationMode.hud_shows(FcPresentationMode.HUD_MINIMAL, FcPresentationMode.E_TRANSPORT))
	for m in FcPresentationMode.MODES:
		for p in [FcPresentationMode.P_FEED, FcPresentationMode.P_SCRUBBER, FcPresentationMode.P_CAMERA]:
			assert_true(not FcPresentationMode.panel_visible(m[0], FcPresentationMode.HUD_HIDDEN, p), "a hidden HUD hides every panel")
		assert_true(not FcPresentationMode.panel_visible(m[0], FcPresentationMode.HUD_MINIMAL, FcPresentationMode.P_SCRUBBER), "no transport in the minimal HUD")


func test_hud_key_cycles_through_all_levels() -> void:
	var level := FcPresentationMode.HUD_FULL
	var seen: Array = []
	for i in 4:
		seen.append(level)
		level = FcPresentationMode.next_hud(level)
	assert_eq(seen, ["full", "minimal", "hidden", "full"])


func test_playback_state_snapshot_is_a_copy() -> void:
	var s := FcPlaybackState.new()
	s.index = 7
	s.instant = {"start": 1}
	var snap := s.snapshot()
	s.index = 9
	s.instant["start"] = 5
	assert_eq(snap[0], 7)
	assert_eq(snap[3], {"start": 1})
	assert_true(s.is_instant())


func test_preferences_default_round_trip_and_bad_values() -> void:
	DirAccess.remove_absolute(PREFS)
	var p := FcPreferences.new(PREFS)
	assert_eq(p.presentation_mode, "replay")
	assert_eq(p.hud_level, "full")
	p.presentation_mode = "analysis"
	p.hud_level = "minimal"
	assert_true(p.save_file())
	var q := FcPreferences.new(PREFS)
	assert_eq(q.presentation_mode, "analysis")
	assert_eq(q.hud_level, "minimal")
	var cfg := ConfigFile.new()
	cfg.set_value("broadcast", "mode", "bogus")
	cfg.set_value("broadcast", "hud", "bogus")
	cfg.save(PREFS)
	var r := FcPreferences.new(PREFS)
	assert_eq(r.presentation_mode, "replay")
	assert_eq(r.hud_level, "full")
	DirAccess.remove_absolute(PREFS)
