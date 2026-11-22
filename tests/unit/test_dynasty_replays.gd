extends FcTestCase
## Dynasty game history (Phase 2E): the last few games' replays are kept in the profile (Dynasty data version 2), survive saving and
## loading, are limited in number and size, older profiles migrate to an empty list, and the Play screen offers them.

const DIR := "user://test_dynasty_replays"

var env: FcDynastyEnv


func before_each() -> void:
	FcSafeFile.remove_tree(DIR)
	env = FcDynastyEnv.make(41)


func after_each() -> void:
	FcSafeFile.remove_tree(DIR)
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)


func _play(count: int) -> void:
	for i in count:
		var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
		assert_true(r.ok, r.message)


func test_a_played_game_keeps_its_replay_and_it_matches_the_game() -> void:
	_play(1)
	var kept: Array = env.profile().replays
	assert_eq(kept.size(), 1)
	var entry: Dictionary = kept[0]
	assert_eq(entry["n"], env.profile().game_counter)
	var box := FcBoxScore.from_dict(entry["box"])
	var timeline := FcPlayByPlay.entries(FcGameEventLog.from_dict(entry["events"]), box)
	assert_eq([timeline[timeline.size() - 1]["home"], timeline[timeline.size() - 1]["away"]], [box.scores[0], box.scores[1]], "the events add up to the kept box")
	var history: Dictionary = env.profile().game_history[env.profile().game_history.size() - 1]
	assert_true(str(entry["label"]).contains("%d-%d" % [history["score_for"], history["score_against"]]), "the label carries the score: %s" % entry["label"])
	assert_true(str(entry["label"]).begins_with("#%d" % entry["n"]))


func test_only_the_last_few_replays_are_kept() -> void:
	var limit := env.catalog.config.get_int(["replay_limit"], 5)
	assert_eq(limit, 5)
	_play(limit + 2)
	var kept: Array = env.profile().replays
	assert_eq(kept.size(), limit, "no more than the limit")
	assert_eq(kept[kept.size() - 1]["n"], env.profile().game_counter, "the newest is kept")
	assert_eq(kept[0]["n"], env.profile().game_counter - limit + 1, "the oldest ones dropped off")
	assert_eq(env.profile().game_history.size(), limit + 2, "the game history list itself is untouched")


func test_replays_survive_saving_and_loading_as_whole_numbers() -> void:
	_play(2)
	var store := FcDynastyStore.new(DIR)
	assert_true(store.save("slot_a", env.profile()).ok)
	var loaded := store.load_slot("slot_a")
	assert_true(loaded.ok, loaded.message)
	var back: FcDynastyProfile = loaded.data["profile"]
	assert_eq(back.replays, env.profile().replays, "the replays came back identical")
	assert_true(back.replays[0]["events"]["rows"][0][0] is int, "events are integers again after JSON")
	assert_true(FcReplay.build(back.replays[0]["box"], back.replays[0]["events"]).size() > 0, "and still open as a replay")


func test_the_kept_replays_stay_small() -> void:
	_play(5)
	var text := JSON.stringify(env.profile().replays)
	assert_true(text.length() < 160000, "five replays are %d characters" % text.length())


func test_an_older_profile_migrates_to_an_empty_replay_list() -> void:
	assert_eq(FcVersion.DYNASTY_DATA_VERSION, 4)
	var old := FcDynastyStore.new(DIR)
	old.current_version = 1   # a version-1 game wrote this file
	var p := env.profile()
	p.replays = []
	var payload_check := p.to_dict()
	payload_check.erase("replays")
	assert_true(not payload_check.has("replays"))
	assert_true(old.save("legacy", p).ok)
	var loaded := FcDynastyStore.new(DIR).load_slot("legacy")
	assert_true(loaded.ok, loaded.message)
	assert_eq((loaded.data["profile"] as FcDynastyProfile).replays, [])
	var step := FcDynastyMigrator.new().migrate({"team_name": "X"}, 1, 2)
	assert_true(step["ok"])
	assert_eq(step["payload"]["replays"], [], "the step adds the empty list")
	assert_eq(step["payload"]["team_name"], "X", "and changes nothing else")
	var kept := FcDynastyMigrator.new().migrate({"replays": [{"n": 1}]}, 1, 2)
	assert_eq(kept["payload"]["replays"], [{"n": 1}], "an existing list is not wiped")


func test_a_failed_game_save_keeps_no_replay() -> void:
	var before: Array = env.profile().replays.duplicate(true)
	var r := env.session.commit(func() -> FcDynastyResult:
		FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even")
		return FcDynastyResult.failure("forced", "undo this"))
	assert_true(not r.ok)
	assert_eq(env.profile().replays, before, "the commit rolled the replay back with everything else")


func test_games_without_events_keep_nothing() -> void:
	var p := env.profile()
	var catalog := env.catalog
	FcDynastyProgress.keep_replay(p, catalog, 99, {"won": true, "score_for": 1, "score_against": 0, "opponent": "X"}, {}, {})
	FcDynastyProgress.keep_replay(p, catalog, 99, {"won": true, "score_for": 1, "score_against": 0, "opponent": "X"}, {}, {"rows": []})
	assert_eq(p.replays.size(), 0)
