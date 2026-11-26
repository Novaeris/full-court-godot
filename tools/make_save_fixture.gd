extends SceneTree
## Writes a small, real save of the CURRENT data version to tests/fixtures/ (an 8-team Owner league, 12 days into the season, one
## news item of each common kind), so the migration step that follows this version can be tested on a genuine old save. Run it once
## before a change bumps FcVersion.DATA_VERSION:
##   godot_console --headless --path . --script res://tools/make_save_fixture.gd
## The file is named after the version it was written with (save_v<N>_owner.sav). Never edit a fixture after a migration uses it.


func _initialize() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	var game := FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 4242, FcGameState.MODE_OWNER, 0)
	game.advance_days(12)
	var dir := "user://fixture_build"
	var saves := FcSaveManager.new(dir)
	var result := saves.save("fixture", game.state, "Fixture")
	if not result.is_ok():
		push_error("save failed: " + result.message)
		quit(1)
		return
	var text := FileAccess.get_file_as_string(dir.path_join("fixture.sav"))
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var out_path := "res://tests/fixtures/save_v%d_owner.sav" % FcVersion.DATA_VERSION
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote %s (%d bytes, data version %d)" % [out_path, text.length(), FcVersion.DATA_VERSION])
	quit(0)
