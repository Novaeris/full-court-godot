extends SceneTree
## Demonstrates the save system with sample data: save, list, load, then damage
## a file on purpose and watch recovery. Uses a scratch folder, not real saves.
## Run:  ./tools/inspect_saves.ps1

const DIR := "user://inspect_saves"


func _initialize() -> void:
	var defs := FcDefinitionSet.load_default()
	var manager := FcSaveManager.new(DIR)
	for slot in ["slot_1", "autosave"]:
		manager.delete_slot(slot)

	var state := FcTestData.game_state()
	print("Saving 'slot_1' (season 2026), then saving again (season 2027)...")
	manager.save("slot_1", state, "Demo game")
	state.current_season = 2027
	manager.save("slot_1", state, "Demo game")
	manager.autosave(state)

	print("")
	print("=== Save list ===")
	for m in manager.list_slots():
		print("%-9s | %-10s | %s | season %d | %s | backup: %s | saved %s" % [
			m.slot_id, m.label, m.team_name, m.season, m.mode, str(m.has_backup), m.saved_at])

	var r := manager.load_slot("slot_1", defs)
	print("")
	print("Normal load: ok=%s season=%d recovered_from='%s' warnings=%d" % [
		str(r.is_ok()), r.state.current_season, r.recovered_from, r.warnings.size()])

	var path := ProjectSettings.globalize_path(DIR).path_join("slot_1.sav")
	var text := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.replace("Testville", "Testvxlle"))
	f.close()
	print("")
	print("Damaged slot_1.sav on purpose (changed one letter).")
	r = manager.load_slot("slot_1", defs)
	print("Load after damage: ok=%s season=%d recovered_from='%s'" % [
		str(r.is_ok()), r.state.current_season, r.recovered_from])
	print("  -> the game fell back to the previous save instead of losing everything.")

	print("")
	print("Save files are in: %s" % ProjectSettings.globalize_path(DIR))
	quit(0)
