extends FcTestCase
## Replay v2 (Broadcast pass 2, M4): one importance model behind highlights, key plays and bookmarks; replay references that are valid pointers
## and never video; automatic packages in game order; a bookmark file that never fails and cannot grow without limit; and PROOF of what the
## replay can and cannot claim: the reconstruction is byte-identical for the same events, and an instant replay window maps back to the
## original recorded event indices.

const SEEDS := [3, 12, 77, 404, 9001]
const PATH := "user://test_replay_bookmarks.json"
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
	DirAccess.remove_absolute(PATH)


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func _timeline(seed_value: int, team_a: int = 0, team_b: int = 1) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[team_a], ratings), FcGameTeam.from_world(world, ids[team_b], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


# --- importance ---------------------------------------------------------------------------------------------------------------

func test_importance_is_deterministic_bounded_and_explained() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var a := FcImportanceModel.scored(t)
		assert_eq(a, FcImportanceModel.scored(t), "same game, same scores")
		assert_true(a.size() > 20)
		var last := -1
		for entry in a:
			assert_true(int(entry["index"]) > last, "game order")
			last = int(entry["index"])
			assert_true(int(entry["importance"]) >= 0 and int(entry["importance"]) <= 100)
			assert_eq(int(entry["importance"]), FcImportanceModel.importance_of(int(entry["score"])))
			assert_true(not (entry["reasons"] as Array).is_empty() and str(entry["title"]) != "")
	assert_eq(FcImportanceModel.importance_of(0), 0)
	assert_eq(FcImportanceModel.importance_of(10000), 100)


func test_context_raises_importance() -> void:
	var t := _timeline(12)
	var clutch_seen := false
	var three_seen := false
	for entry in FcImportanceModel.scored(t):
		var reasons: Array = entry["reasons"]
		var base := int(FcImportanceModel.WEIGHT[entry["kind"]])
		if reasons.has("clutch time"):
			clutch_seen = true
			assert_true(int(entry["score"]) >= base + FcImportanceModel.CLUTCH_BONUS)
		if reasons.has("three-pointer"):
			three_seen = true
			assert_true(int(entry["score"]) >= base + FcImportanceModel.THREE_BONUS)
		if reasons.has("last basket"):
			assert_true(int(entry["score"]) >= base + FcImportanceModel.LAST_BASKET_BONUS)
	assert_true(three_seen)
	assert_true(clutch_seen or t.clutch_start_index() < 0)


func test_highlights_are_the_importance_models_best_plays() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var scored := FcImportanceModel.scored(t)
		var picked := FcHighlights.select(t, 6)
		var best := {}
		for e in scored:
			best[int(e["index"])] = int(e["score"])
		for h in picked:
			assert_true(best.has(int(h["index"])), "every highlight is a scored play")
			assert_eq(int(h["score"]), best[int(h["index"])])
		assert_eq(picked, FcImportanceModel.top(scored, 6, FcHighlights.MIN_GAP), "one source of truth")


# --- references and collections -----------------------------------------------------------------------------------------------------

func test_every_reference_is_valid_for_its_game_and_only_its_game() -> void:
	var t := _timeline(12)
	var other := _timeline(77)
	var pack := FcReplayCollections.package(t)
	assert_true(not (pack["refs"] as Array).is_empty())
	assert_true(float(pack["seconds"]) > 0.0)
	var last := -1
	for ref in pack["refs"]:
		assert_true(FcReplayReference.is_valid(t, ref), "valid in its own game")
		assert_true(not FcReplayReference.is_valid(other, ref), "not valid in another game")
		assert_eq(ref["source"], FcReplayReference.AUTO_HIGHLIGHT)
		assert_true(int(ref["end"]) > last, "game order")
		last = int(ref["end"])
	for ref in FcReplayCollections.key_plays(t):
		assert_true(FcReplayReference.is_valid(t, ref))
		assert_eq(ref["source"], FcReplayReference.KEY_PLAY)
	assert_true(not FcReplayReference.is_valid(t, {"game_key": t.model.game_key(), "start": 5, "end": 2, "label": "x", "source": "key_play", "importance": 1}), "start after end")
	assert_true(not FcReplayReference.is_valid(t, {"label": "x"}), "missing fields")
	assert_true(not FcReplayReference.is_valid(null, {}))


func test_bookmarks_become_references_and_bad_indices_are_ignored() -> void:
	var t := _timeline(12)
	var refs := FcReplayCollections.bookmarks(t, [60, 20, 9999, -3, 20])
	assert_eq(refs.size(), 3, "20 twice counts twice here (the store prevents duplicates); out of range ones are dropped: %s" % str(refs.size()))
	assert_true(int(refs[0]["end"]) <= int(refs[1]["end"]))
	for ref in refs:
		assert_eq(ref["source"], FcReplayReference.USER_BOOKMARK)
		assert_true(FcReplayReference.is_valid(t, ref))
	assert_eq(FcReplayCollections.bookmarks(null, [1]), [])


func test_game_keys_are_stable_and_tell_games_apart() -> void:
	var a := _timeline(12)
	assert_eq(a.model.game_key(), _timeline(12).model.game_key(), "the same game, the same key")
	assert_true(a.model.game_key() != _timeline(77).model.game_key())
	assert_true(a.model.game_key() != _timeline(12, 1, 2).model.game_key())


func test_replay_wording_says_reconstructed_and_not_video() -> void:
	assert_true(FcReplayReference.REPLAY_WORDING.contains("reconstructed") and FcReplayReference.REPLAY_WORDING.contains("not video"))
	assert_true(FcReplayReference.BADGE_TEXT.contains("reconstructed") and FcReplayReference.REEL_BADGE_TEXT.contains("reconstructed"))


# --- the proofs the brief asked for ---------------------------------------------------------------------------------------------------------

func test_the_reconstruction_is_byte_identical_for_the_same_events() -> void:
	for s in SEEDS:
		var a := var_to_str(FcReconstructor.build(_timeline(s)))
		var b := var_to_str(FcReconstructor.build(_timeline(s)))   # a fresh simulation, log, model and timeline
		assert_eq(a, b, "seed %d: the same recorded game always reconstructs to the same bytes" % s)
		assert_true(a.length() > 1000)


func test_an_instant_replay_window_maps_to_the_original_events() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var floor_index := t.model.start_index()
		for i in range(floor_index, t.size()):
			var w := t.replay_window(i)
			var start := int(w["start"])
			var end := int(w["end"])
			assert_eq(end, i, "the window ends at the event asked for")
			assert_true(start >= floor_index and start <= end, "inside the game")
			assert_true(end - start < 10, "never longer than the cap")
			for k in range(start, end):
				assert_true(not FcBroadcastTimeline.ends_possession(t.model.entries[k]), "event %d inside the window does not end a possession" % k)
			if start > floor_index and end - start < 9:
				assert_true(FcBroadcastTimeline.ends_possession(t.model.entries[start - 1]), "the window starts right after the previous possession ended")


# --- the bookmark file ----------------------------------------------------------------------------------------------------------------------

func test_bookmarks_save_load_toggle_and_never_fail() -> void:
	var a := FcBookmarkStore.new(PATH)
	assert_eq(a.indices("g"), [])
	assert_true(a.add("g", 40) and a.add("g", 12))
	assert_true(not a.add("g", 12), "no duplicates")
	assert_eq(a.indices("g"), [12, 40], "ascending")
	var b := FcBookmarkStore.new(PATH)
	assert_eq(b.indices("g"), [12, 40], "kept in the file")
	assert_true(not b.toggle("g", 12) and b.toggle("g", 77))
	assert_eq(FcBookmarkStore.new(PATH).indices("g"), [40, 77])
	assert_true(b.remove("g", 40) and b.remove("g", 77))
	assert_eq(b.game_count(), 0, "an empty game is dropped")
	var memory := FcBookmarkStore.new("")
	assert_true(memory.add("g", 1), "an in-memory store works")
	assert_true(not memory.save_file(), "but has no file to write")
	assert_true(not a.add("", 5) and not a.add("g", -1))


func test_a_damaged_bookmark_file_is_an_empty_store_and_the_limits_hold() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_eq(FcBookmarkStore.new(PATH).game_count(), 0)
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99, "games": {"g": [1]}}))
	f.close()
	assert_eq(FcBookmarkStore.new(PATH).game_count(), 0, "an unknown version is ignored, not guessed at")
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "games": {"g": [3, "x", -1, 3, 2.0], "h": "no"}}))
	f.close()
	assert_eq(FcBookmarkStore.new(PATH).indices("g"), [2, 3], "only sound entries survive")
	var s := FcBookmarkStore.new(PATH)
	for i in FcBookmarkStore.MAX_PER_GAME + 5:
		s.add("many", i)
	assert_eq(s.indices("many").size(), FcBookmarkStore.MAX_PER_GAME)
	for g in FcBookmarkStore.MAX_GAMES + 10:
		s.add("game%d" % g, 1)
	assert_true(s.game_count() <= FcBookmarkStore.MAX_GAMES, "the oldest games are dropped")
