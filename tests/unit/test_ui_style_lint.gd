extends FcTestCase
## The style ratchet (docs/UI_POLISH_PLAN.md, section 7): screens must take colours and text sizes from the design system, so the
## number of style literals in src/ui may only go down. When a screen is migrated, lower its numbers in
## tests/support/ui_style_baseline.json (the failure message prints the new count to use).

const BASELINE_PATH := "res://tests/support/ui_style_baseline.json"


func _baseline() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	return parsed if parsed is Dictionary else {}


func test_no_ui_file_gains_style_literals() -> void:
	var baseline := _baseline()
	assert_true(not baseline.is_empty(), "the baseline file must load")
	var scanned := FcUiStyleScan.scan()
	for path in scanned:
		var allowed: Dictionary = baseline.get(path, {"color": 0, "font": 0, "sized_label": 0})
		for kind in ["color", "font", "sized_label"]:
			var now: int = scanned[path][kind]
			var limit: int = int(allowed.get(kind, 0))
			assert_true(now <= limit, "%s has %d literal %s uses (allowed %d). Use FcUiTokens / the theme / the kit, or lower the baseline after migrating." % [path.get_file(), now, kind, limit])


func test_the_baseline_has_no_stale_entries() -> void:
	# a baseline that is higher than reality hides regressions, so entries must be tight
	var scanned := FcUiStyleScan.scan()
	for path in _baseline():
		var now: Dictionary = scanned.get(path, {"color": 0, "font": 0, "sized_label": 0})
		for kind in ["color", "font", "sized_label"]:
			assert_true(int(_baseline()[path].get(kind, 0)) <= int(now[kind]), "%s: the baseline allows %d %s but there are only %d now; lower it" % [path.get_file(), int(_baseline()[path].get(kind, 0)), kind, int(now[kind])])


func test_the_scanner_counts_what_it_claims() -> void:
	var c := FcUiStyleScan.count_text("var a := Color(1, 0, 0)\n# Color(0,0,0)\nx.add_theme_font_size_override(\"font_size\", 9)\nFcUiTables.label(\"Hi\", 18, true)\nFcUiTables.label(\"Plain\")\n")
	assert_eq(c["color"], 1, "one colour literal (the comment is ignored)")
	assert_eq(c["font"], 1, "one font override")
	assert_eq(c["sized_label"], 1, "one sized label")
