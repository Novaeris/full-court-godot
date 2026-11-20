extends SceneTree
## Dynasty Mode health check with timings (invented fixture content, scratch folders only): builds the catalog, rolls packs,
## plays games and a tournament, saves and reloads, and prints how long each step took. Run: ./tools/dynasty_check.ps1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var env := FcDynastyEnv.make()
	print("catalog + profile (32 cards): %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	for s in 1000:
		FcDynastyPacks.roll(env.catalog, "elite_pack", FcRng.new(s), 0)
	print("1000 pack rolls: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var wins := 0
	for i in 50:
		var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
		if r.ok and r.data["summary"]["won"]:
			wins += 1
	print("50 simulated games with saves: %d ms (won %d of 50 against even teams)" % [Time.get_ticks_msec() - t0, wins])
	t0 = Time.get_ticks_msec()
	env.fund("credits", 500)
	env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(env.session.profile, env.catalog, "test_cup"))
	while FcDynastyTournament.has_active(env.profile()):
		env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(env.session.profile, env.catalog))
	print("one tournament: %d ms, placed %s" % [Time.get_ticks_msec() - t0, env.profile().tournament["history"][0]["placement"]])
	t0 = Time.get_ticks_msec()
	var back := env.store.load_slot("env")
	print("load profile (%d ledger lines): %d ms, ok=%s" % [env.profile().ledger.size(), Time.get_ticks_msec() - t0, back.ok])
	FcDynastyEnv.cleanup()
	quit(0 if back.ok else 1)
