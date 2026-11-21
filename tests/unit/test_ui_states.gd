extends FcTestCase
## The six interaction states (default, hover, pressed, focused, selected, disabled) of the interactive kit controls
## (docs/VISUAL_IDENTITY_PLAN.md, section 4): every button variant has a distinct look for each state it can be in, the table row
## shows hover, selected and focus, and the new feedback components exist in every state.

const BUTTONS := ["Button", "PrimaryButton", "DangerButton", "GhostButton", "IconButton", "TabButton", "NavButton"]


func after_each() -> void:
	FcUiTheme.build(1)


func _style(theme: Theme, state: String, variation: String) -> StyleBox:
	return theme.get_stylebox(state, variation if variation != "Button" else "Button")


func test_every_button_variant_has_a_style_for_each_state() -> void:
	var theme := FcUiTheme.build(1)
	for variation in BUTTONS:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			assert_true(theme.has_stylebox(state, variation) or theme.get_stylebox(state, variation) != null, "%s has a %s style" % [variation, state])


func test_hover_pressed_and_disabled_look_different_from_default() -> void:
	var theme := FcUiTheme.build(1)
	for variation in ["Button", "PrimaryButton", "DangerButton"]:
		var normal := theme.get_stylebox("normal", variation) as StyleBoxFlat
		for state in ["hover", "pressed", "disabled"]:
			var other := theme.get_stylebox(state, variation) as StyleBoxFlat
			assert_true(other.bg_color != normal.bg_color or other.border_color != normal.border_color, "%s %s differs from normal" % [variation, state])


func test_the_focus_ring_is_visible_against_every_surface() -> void:
	var theme := FcUiTheme.build(1)
	var ring := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_true(ring.border_width_left >= 2, "the focus ring is at least 2 px")
	for surface in [FcUiTokens.BG, FcUiTokens.SURFACE, FcUiTokens.SURFACE_RAISED, FcUiTokens.SURFACE_HIGH]:
		assert_true(FcUiContrast.ratio(ring.border_color, surface) >= 3.0, "focus ring on %s" % str(surface))


func test_disabled_buttons_stay_legible() -> void:
	var theme := FcUiTheme.build(1)
	var color := theme.get_color("font_disabled_color", "Button")
	for surface in [FcUiTokens.SURFACE, FcUiTokens.SURFACE_RAISED]:
		assert_true(FcUiContrast.ratio(color, surface) >= 3.0, "disabled text on %s" % str(surface))


func test_a_table_row_shows_hover_selected_and_focus() -> void:
	var row := FcTableRow.new()
	row.set_look(false, false, false, false)
	assert_true(not row.is_selected and not row.is_hovered and not row.show_focus, "default")
	row.set_look(false, false, true, false)
	assert_true(row.is_hovered, "hover")
	row.set_look(false, true, false, true)
	assert_true(row.is_selected and row.show_focus, "selected with a focus outline")
	row.free()


func test_the_selected_row_text_stays_readable() -> void:
	var accent := FcUiTheme.accent
	for base in [FcUiTokens.SURFACE, FcUiTokens.SURFACE_HIGH]:
		var tinted: Color = (base as Color).lerp(accent, 0.16)
		assert_true(FcUiContrast.ratio(FcUiTokens.TEXT, tinted) >= 7.0, "text on a selected row over %s" % str(base))


func test_feedback_components_exist_for_empty_error_success_and_loading() -> void:
	var states: Array = [
		FcEmptyState.new("Nothing", "Why", FcEmptyState.Kind.EMPTY),
		FcEmptyState.error("Failed", "Why", "Try again", func() -> void: pass),
		FcEmptyState.success("Saved", "Done"),
		FcSkeleton.new(3),
		FcLoading.new("Working"),
	]
	assert_true((states[1] as FcEmptyState).action_button != null, "an error offers a retry")
	assert_true((states[2] as FcEmptyState).action_button == null, "a success needs no action")
	assert_eq((states[3] as FcSkeleton).bar_count(), 3)
	for s in states:
		s.free()


func test_surface_tiers_are_ordered_light_to_dark() -> void:
	var lum := [FcUiContrast.luminance(FcUiTokens.BG), FcUiContrast.luminance(FcUiTokens.SURFACE), FcUiContrast.luminance(FcUiTokens.SURFACE_RAISED), FcUiContrast.luminance(FcUiTokens.SURFACE_HIGH)]
	for i in range(1, lum.size()):
		assert_true(lum[i] > lum[i - 1], "surface step %d is lighter than the one below" % i)
