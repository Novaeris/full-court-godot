extends FcTestCase
## The layout ratchet (docs/UI_POLISH_PLAN.md, section 7): the smallest window each screen needs may only shrink. Baseline numbers
## are in tests/support/ui_layout_baseline.json (measured at the start of the redesign). When a phase makes a screen narrower,
## lower its number there. Owner and Career must stay usable at 800x600 (D6) and Dynasty heads for a 412-wide phone (Phase 8).

const BASELINE_PATH := "res://tests/support/ui_layout_baseline.json"


func test_no_screen_needs_a_bigger_window_than_the_baseline() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	assert_true(parsed is Dictionary and not (parsed as Dictionary).is_empty(), "the baseline file must load")
	if not (parsed is Dictionary):
		return
	var baseline: Dictionary = parsed
	for screen in FcUiLayoutProbe.SCREENS:
		assert_true(baseline.has(screen), "%s has a baseline" % screen)
		if not baseline.has(screen):
			continue
		var now := FcUiLayoutProbe.measure_screen(screen)
		assert_true(now["w"] > 0 and now["h"] > 0, "%s reports a real size" % screen)
		assert_true(now["w"] <= int(baseline[screen]["w"]), "%s now needs %d px of width (baseline %d): a screen got wider" % [screen, now["w"], int(baseline[screen]["w"])])
		assert_true(now["h"] <= int(baseline[screen]["h"]), "%s now needs %d px of height (baseline %d): a screen got taller" % [screen, now["h"], int(baseline[screen]["h"])])
