extends FcTestCase

const DIR := "user://test_saves"
const Code := FcSaveResult.Code

var manager: FcSaveManager
var defs: FcDefinitionSet


func before_each() -> void:
	_wipe()
	manager = FcSaveManager.new(DIR)
	defs = FcTestData.defs()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _state(season: int = 2026) -> FcGameState:
	var s := FcTestData.game_state()
	s.current_season = season
	return s


func _slot_file(slot: String) -> String:
	return DIR.path_join(slot + ".sav")


func _damage(path: String) -> void:
	# Same length, different content: only the checksum can notice.
	var text := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.replace("Testville", "Testvxlle"))
	f.close()


func test_round_trip_preserves_everything() -> void:
	var s := _state(2029)
	for i in 10:
		s.rng.next_float()
	var saved := manager.save("slot_1", s, "My first game")
	assert_true(saved.is_ok(), saved.message)
	assert_eq(saved.warnings, [] as Array[String])
	var loaded := manager.load_slot("slot_1", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.recovered_from, "")
	assert_eq(loaded.warnings, [] as Array[String])
	assert_eq(loaded.state.to_dict(), s.to_dict())
	assert_eq(loaded.state.rng.next_float(), s.rng.next_float(), "random continues")
	assert_eq(loaded.metadata.label, "My first game")
	assert_eq(loaded.metadata.team_name, "Testville Testers")
	assert_eq(loaded.metadata.season, 2029)
	assert_eq(loaded.metadata.mode, "owner")
	assert_eq(loaded.metadata.game_version, FcVersion.GAME_VERSION)


func test_staff_survive_save_and_load() -> void:
	var s := _state()
	s.world.staff.get_by_id(2).skills.set_value("game_management", 97)
	manager.save("slot_1", s)
	var loaded := manager.load_slot("slot_1", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	assert_eq(loaded.state.world.staff.get_by_id(2).skills.get_value("game_management"), 97)
	assert_eq(loaded.state.world.staff_in_role(1, FcStaffRole.Id.HEAD_COACH).id, 2)


func test_invalid_slot_names_rejected_and_nothing_written() -> void:
	for bad in ["", "../evil", "UPPER", "has space", "dot.name", "a".repeat(33), "sub/dir"]:
		assert_eq(manager.save(bad, _state()).code, Code.INVALID_SLOT, "'%s'" % bad)
		assert_eq(manager.load_slot(bad, defs).code, Code.INVALID_SLOT)
		assert_eq(manager.delete_slot(bad).code, Code.INVALID_SLOT)
	assert_eq(manager.list_slots().size(), 0)


func test_loading_missing_slot() -> void:
	assert_eq(manager.load_slot("nothing_here", defs).code, Code.NOT_FOUND)


func test_overwrite_keeps_previous_save_as_backup() -> void:
	manager.save("slot_1", _state(2026))
	manager.save("slot_1", _state(2027))
	assert_eq(manager.load_slot("slot_1", defs).state.current_season, 2027)
	assert_true(manager.list_slots()[0].has_backup)
	assert_true(FileAccess.file_exists(_slot_file("slot_1") + ".bak"))
	assert_true(not FileAccess.file_exists(_slot_file("slot_1") + ".tmp"), "no leftover temp file")


func test_damaged_main_file_recovers_from_backup() -> void:
	manager.save("slot_1", _state(2026))
	manager.save("slot_1", _state(2027))
	_damage(_slot_file("slot_1"))
	var r := manager.load_slot("slot_1", defs)
	assert_true(r.is_ok(), r.message)
	assert_eq(r.recovered_from, "backup")
	assert_eq(r.state.current_season, 2026, "the older, intact save")


func test_damaged_file_without_backup_is_corrupt() -> void:
	manager.save("slot_1", _state())
	_damage(_slot_file("slot_1"))
	var r := manager.load_slot("slot_1", defs)
	assert_eq(r.code, Code.CORRUPT)
	assert_true(r.state == null)
	assert_true(not r.message.is_empty())


func test_truncated_and_garbage_files_are_corrupt() -> void:
	manager.save("slot_1", _state())
	var text := FileAccess.get_file_as_string(_slot_file("slot_1"))
	var f := FileAccess.open(_slot_file("slot_1"), FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))
	f.close()
	assert_eq(manager.load_slot("slot_1", defs).code, Code.CORRUPT, "truncated")

	var g := FileAccess.open(_slot_file("slot_2"), FileAccess.WRITE)
	g.store_string("this is not a save")
	g.close()
	assert_eq(manager.load_slot("slot_2", defs).code, Code.CORRUPT, "garbage")

	var h := FileAccess.open(_slot_file("slot_3"), FileAccess.WRITE)
	h.close()
	assert_eq(manager.load_slot("slot_3", defs).code, Code.CORRUPT, "empty file")


func test_tampered_header_checksum_detected() -> void:
	manager.save("slot_1", _state())
	var text := FileAccess.get_file_as_string(_slot_file("slot_1"))
	var f := FileAccess.open(_slot_file("slot_1"), FileAccess.WRITE)
	f.store_string(text.replace("\"payload_sha256\":\"", "\"payload_sha256\":\"0"))
	f.close()
	assert_eq(manager.load_slot("slot_1", defs).code, Code.CORRUPT)


func test_interrupted_save_leaves_good_save_untouched() -> void:
	manager.save("slot_1", _state(2026))
	# Simulate a crash mid-write: a partial temp file exists next to a good save.
	var f := FileAccess.open(_slot_file("slot_1") + ".tmp", FileAccess.WRITE)
	f.store_string("{\"format\":\"fullcourt-save\",\"for")
	f.close()
	var r := manager.load_slot("slot_1", defs)
	assert_true(r.is_ok())
	assert_eq(r.recovered_from, "")
	assert_eq(r.state.current_season, 2026)
	# The next save works normally and cleans up.
	assert_true(manager.save("slot_1", _state(2027)).is_ok())
	assert_eq(manager.load_slot("slot_1", defs).state.current_season, 2027)


func test_crash_after_verified_temp_before_rename_recovers_newest() -> void:
	# main missing, verified temp (the new save) present, backup (old save) present.
	manager.save("slot_1", _state(2026))
	manager.save("slot_1", _state(2027))
	DirAccess.rename_absolute(_slot_file("slot_1"), _slot_file("slot_1") + ".tmp")
	var r := manager.load_slot("slot_1", defs)
	assert_true(r.is_ok(), r.message)
	assert_eq(r.recovered_from, "temp")
	assert_eq(r.state.current_season, 2027)


func test_save_from_newer_game_is_rejected() -> void:
	var newer := FcSaveManager.new(DIR)
	newer.current_data_version = FcVersion.DATA_VERSION + 1
	newer.save("slot_1", _state())
	var r := manager.load_slot("slot_1", defs)
	assert_eq(r.code, Code.UNSUPPORTED_VERSION)
	assert_true("newer version" in r.message)


func test_migration_upgrades_old_save() -> void:
	manager.current_data_version = 1
	manager.save("slot_1", _state(2026))  # written as data version 1
	var upgraded := FcSaveManager.new(DIR)
	upgraded.current_data_version = 3
	upgraded.migrator.register(1, func(p: Dictionary) -> Dictionary:
		p["current_season"] = int(p["current_season"]) + 100
		return p)
	upgraded.migrator.register(2, func(p: Dictionary) -> Dictionary:
		p["current_season"] = int(p["current_season"]) + 1000
		return p)
	var r := upgraded.load_slot("slot_1", defs)
	assert_true(r.is_ok(), r.message)
	assert_eq(r.state.current_season, 2026 + 100 + 1000, "both steps applied in order")


func test_missing_or_failing_migration_is_reported() -> void:
	manager.current_data_version = 1
	manager.save("slot_1", _state())
	var no_step := FcSaveManager.new(DIR)
	no_step.current_data_version = FcVersion.DATA_VERSION + 1   # the built-in 1 -> 2 and 2 -> 3 and 3 -> 4 steps exist, 4 -> 5 does not
	assert_eq(no_step.load_slot("slot_1", defs).code, Code.MIGRATION_FAILED)

	var failing := FcSaveManager.new(DIR)
	failing.current_data_version = 2
	failing.migrator.register(1, func(_p: Dictionary): return null)
	assert_eq(failing.load_slot("slot_1", defs).code, Code.MIGRATION_FAILED)


func test_list_slots_reads_headers_and_flags_unreadable() -> void:
	manager.save("slot_1", _state(2026), "First")
	manager.save("slot_2", _state(2030), "Second")
	var g := FileAccess.open(_slot_file("broken"), FileAccess.WRITE)
	g.store_string("garbage")
	g.close()
	var slots := manager.list_slots()
	assert_eq(slots.size(), 3)
	var by_id := {}
	for m in slots:
		by_id[m.slot_id] = m
	assert_eq(by_id["slot_2"].label, "Second")
	assert_eq(by_id["slot_2"].season, 2030)
	assert_eq(by_id["slot_2"].team_name, "Testville Testers")
	assert_true(by_id["slot_1"].readable)
	assert_true(not by_id["broken"].readable)


func test_delete_removes_all_copies() -> void:
	manager.save("slot_1", _state())
	manager.save("slot_1", _state())
	assert_true(manager.delete_slot("slot_1").is_ok())
	assert_true(not manager.has_slot("slot_1"))
	assert_true(not FileAccess.file_exists(_slot_file("slot_1") + ".bak"))
	assert_eq(manager.delete_slot("slot_1").code, Code.NOT_FOUND)


func test_autosave_uses_reserved_slot() -> void:
	assert_true(manager.autosave(_state()).is_ok())
	assert_true(manager.has_slot(FcSaveManager.AUTOSAVE_SLOT))
	assert_eq(manager.list_slots()[0].label, "Autosave")


func test_integrity_problems_do_not_block_saving_but_are_reported() -> void:
	var s := _state()
	s.world.players.get_by_id(1).physical.height_cm = 5
	var saved := manager.save("slot_1", s)
	assert_true(saved.is_ok(), "progress is never refused")
	assert_true(not saved.warnings.is_empty())
	var loaded := manager.load_slot("slot_1", defs)
	assert_true(loaded.is_ok())
	assert_true(not loaded.warnings.is_empty(), "problems resurface on load")


func test_two_slots_are_independent() -> void:
	manager.save("slot_1", _state(2026))
	manager.save("slot_2", _state(2040))
	assert_eq(manager.load_slot("slot_1", defs).state.current_season, 2026)
	assert_eq(manager.load_slot("slot_2", defs).state.current_season, 2040)
