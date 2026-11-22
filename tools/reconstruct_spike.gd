extends SceneTree
## The feasibility measurement for B1 (docs/validation/B1_RECONSTRUCTION_SPIKE.md): reconstructs many simulated games, validates every one with
## the independent validator, and measures how often the reconstruction needs more time than the recorded game clock allows ("clock
## compressed"), which is what decides whether replaying it at game speed is credible. Read-only; prints numbers.
##
## Run:  godot_console --headless --path . --script res://tools/reconstruct_spike.gd -- [games=40] [seed=7000]


func _initialize() -> void:
	var games := 40
	var seed_base := 7000
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "games":
			games = int(kv[1])
		elif kv.size() == 2 and kv[0] == "seed":
			seed_base = int(kv[1])
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var ratings := FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	var world := FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ids := world.teams.ids()
	var problems_total := 0
	var keyframes := 0
	var events := 0
	var steps := 0
	var compressed := 0
	var compressed_by_kind := {}
	var steps_by_kind := {}
	var dts: Array = []
	var recon_seconds := 0.0
	var game_seconds := 0.0
	var identical := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var sim := FcGameSimulator.new()
		sim.recorder = FcGameEventLog.new()
		var home := ids[g % ids.size()]
		var away := ids[(g + 1) % ids.size()]
		var box := sim.simulate(FcGameTeam.from_world(world, home, ratings), FcGameTeam.from_world(world, away, ratings), FcRng.new(seed_base + g))
		var timeline := FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))
		var result := FcReconstructor.build(timeline)
		problems_total += FcReconstructionValidator.validate(timeline, result).size()
		var again := FcReconstructor.build(timeline)
		if _digest(result) == _digest(again):
			identical += 1
		var frames: Array = result["keyframes"]
		keyframes += frames.size()
		events += timeline.size() - timeline.model.start_index()
		recon_seconds += float(frames[frames.size() - 1]["t"])
		game_seconds += float(box.overtimes * 300 + 2880)
		for k in range(1, frames.size()):
			var a := timeline.model.entries[int(frames[k - 1]["event"])]
			var b := timeline.model.entries[int(frames[k]["event"])]
			if int(a["period"]) != int(b["period"]):
				continue
			var dt := float(frames[k]["t"]) - float(frames[k - 1]["t"])
			var gap := float(a["clock"]) - float(b["clock"])   # game seconds that passed between the two events (the clock counts down)
			var kind := str(frames[k]["kind"])
			steps += 1
			steps_by_kind[kind] = int(steps_by_kind.get(kind, 0)) + 1
			dts.append(dt)
			if dt > gap + 1.0:
				compressed += 1
				compressed_by_kind[kind] = int(compressed_by_kind.get(kind, 0)) + 1
	dts.sort()
	print("=== B1 reconstruction spike: %d games from seed %d in %.1f s ===" % [games, seed_base, (Time.get_ticks_msec() - t0) / 1000.0])
	print("events from the tip-off %d, keyframes %d, validator problems %d, repeat builds identical %d of %d" % [events, keyframes, problems_total, identical, games])
	print("reconstruction time per game %.0f s on its own axis (the game clock is %.0f s)" % [recon_seconds / games, game_seconds / games])
	print("step length: median %.2f s, p95 %.2f s, max %.2f s" % [dts[dts.size() / 2], dts[int(dts.size() * 0.95)], dts[dts.size() - 1]])
	print("clock-compressed steps (the reconstruction needs more than the game clock gave plus 1 s): %d of %d (%.1f%%)" % [compressed, steps, 100.0 * compressed / maxf(1.0, steps)])
	var kinds: Array = steps_by_kind.keys()
	kinds.sort()
	for k in kinds:
		print("  %-12s %5d steps, %5d compressed (%.1f%%)" % [k, steps_by_kind[k], int(compressed_by_kind.get(k, 0)), 100.0 * int(compressed_by_kind.get(k, 0)) / float(steps_by_kind[k])])
	quit(1 if problems_total > 0 or identical != games else 0)


func _digest(result: Dictionary) -> String:
	var parts: Array = []
	for f in result["keyframes"]:
		var ids: Array = (f["players"] as Dictionary).keys()
		ids.sort()
		var s := "%d|%s|%.4f|%.3f,%.3f,%.3f|%d" % [int(f["event"]), f["kind"], float(f["t"]), f["ball"].x, f["ball"].y, f["ball"].z, int(f["holder"])]
		for pid in ids:
			s += "|%d:%.3f,%.3f" % [int(pid), f["players"][pid].x, f["players"][pid].y]
		parts.append(s)
	return "\n".join(PackedStringArray(parts)).sha256_text()
