extends FcLiveTestCase
## Regression (docs/STABILIZATION_AUDIT.md S1-UI-2): the post-game line score has a fixed-width cell per period, so a game that went to
## overtime (7 or more columns) was wider than a 360 px phone and pushed the whole Dynasty play tab sideways. It now sits in a centred,
## sideways-scrolling holder, so any number of overtimes keeps the screen inside the window while every cell is still there.

## A phone is 360 px wide; the screen margins and the panel's own padding leave this much for the panel's content at its narrowest.
const MAX_PANEL_MINIMUM_WIDTH := 300.0


func _vm(periods: int) -> Dictionary:
	var columns: Array = ["Team"]
	var row_a: Array = ["AAA"]
	var row_b: Array = ["BBB"]
	for p in periods:
		columns.append(str(p + 1) if p < 4 else ("OT" if p == 4 else "OT%d" % (p - 3)))
		row_a.append(25)
		row_b.append(24)
	columns.append("T")
	row_a.append(25 * periods)
	row_b.append(24 * periods)
	return {"line_score": {"columns": columns, "rows": [row_a, row_b]}}


func test_a_line_score_with_overtimes_never_widens_the_screen_beyond_a_phone() -> void:
	for periods in [4, 5, 6, 8]:   # regulation, one, two and four overtimes
		var screen := FcPostGameScreen.new()
		screen.vm = _vm(periods)
		var panel: Control = screen._line_score()
		host.add_child(panel)
		await frames(2)
		assert_true(panel.get_combined_minimum_size().x <= MAX_PANEL_MINIMUM_WIDTH,
			"%d periods: the line score asks for %d px (limit %d)" % [periods, int(panel.get_combined_minimum_size().x), int(MAX_PANEL_MINIMUM_WIDTH)])
		var grid := panel.find_children("*", "GridContainer", true, false)[0] as GridContainer
		assert_eq(grid.get_child_count(), (periods + 2) * 3, "%d periods: every header and score cell is still there" % periods)
		host.remove_child(panel)
		panel.free()
		screen.free()
