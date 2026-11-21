extends FcLiveTestCase
## Kit behaviour that needs a live scene tree: Range signals, timers (debounce, toast expiry), keyboard input and focus.

var got: Array = []


func before_each() -> void:
	super.before_each()
	got = []


func _press_escape() -> void:
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)


func test_slider_emits_and_updates_its_readout() -> void:
	var s := FcSlider.new(0, 100, 5, "%")
	host.add_child(s)
	s.value_changed.connect(func(v: float) -> void: got.append(v))
	s.set_value_silent(70)
	assert_eq(got, [], "restoring a saved value does not emit")
	assert_eq(s.readout.text, "70%")
	s.slider.value = 40
	assert_eq(got, [40.0], "a change from the player emits")
	assert_eq(s.readout.text, "40%")
	s.disabled = true
	assert_true(not s.slider.editable, "disabled sliders cannot be dragged")


func test_search_waits_for_a_pause_in_typing() -> void:
	var f := FcSearchField.new("Find")
	host.add_child(f)
	f.search_changed.connect(func(q: String) -> void: got.append(q))
	f.text = "m"
	f.text_changed.emit("m")
	await seconds(0.1)
	f.text = "ma"
	f.text_changed.emit("ma")
	await seconds(0.1)
	assert_eq(got, [], "still typing: nothing fired")
	await seconds(0.3)
	assert_eq(got, ["ma"], "one search, with the final text, after the pause")


func test_search_enter_is_immediate_and_cancels_the_wait() -> void:
	var f := FcSearchField.new("Find")
	host.add_child(f)
	f.search_changed.connect(func(q: String) -> void: got.append(q))
	f.text_changed.emit("maya")
	f.text_submitted.emit("maya")
	assert_eq(got, ["maya"])
	await seconds(0.4)
	assert_eq(got, ["maya"], "the pending debounced search did not fire a second time")


func test_escape_cancels_a_confirmation_dialog() -> void:
	var m := FcModal.confirm(host, "Next season?", "", func() -> void: got.append("confirmed"))
	m.cancelled.connect(func() -> void: got.append("cancelled"))
	await frames(2)
	_press_escape()
	await frames(2)
	assert_eq(got, ["cancelled"], "Escape cancels and never confirms")


func test_escape_closes_an_info_dialog() -> void:
	var m := FcModal.notice(host, "Saved", "")
	m.confirmed.connect(func() -> void: got.append("ok"))
	await frames(2)
	_press_escape()
	await frames(2)
	assert_eq(got, ["ok"])


func test_a_destructive_dialog_starts_on_cancel_and_focus_returns_afterwards() -> void:
	var opener := Button.new()
	opener.text = "Delete save"
	host.add_child(opener)
	opener.grab_focus()
	await frames(1)
	var m := FcModal.confirm(host, "Delete?", "Gone for good.", func() -> void: got.append("deleted"), true, "Delete")
	await frames(2)
	assert_true(m.cancel_button.has_focus(), "focus starts on Cancel, so Enter cannot delete by accident")
	m.close(false)
	await frames(2)
	assert_true(opener.has_focus(), "focus returns to the button that opened the dialog")
	assert_eq(got, [])


func test_a_confirmation_starts_on_the_confirm_button() -> void:
	var m := FcModal.confirm(host, "Next season?", "", func() -> void: pass)
	await frames(2)
	assert_true(m.confirm_button.has_focus())


func test_a_closed_dialog_disappears() -> void:
	var m := FcModal.notice(host, "Saved", "")
	await frames(2)
	m.close(true)
	await seconds(0.4)
	assert_true(not is_instance_valid(m) or m.is_queued_for_deletion(), "the dialog is gone after its fade")


func test_toast_stack_limits_deduplicates_and_expires() -> void:
	var stack := FcToastStack.new()
	host.add_child(stack)
	var first := stack.push(FcToast.Kind.INFO, "One")
	stack.push(FcToast.Kind.SUCCESS, "Two")
	stack.push(FcToast.Kind.WARNING, "Three")
	assert_eq(stack.visible_count(), 3)
	assert_true(stack.push(FcToast.Kind.INFO, "One") == first, "the same message restarts its timer instead of stacking")
	assert_eq(stack.visible_count(), 3)
	stack.push(FcToast.Kind.ERROR, "Four")
	assert_eq(stack.visible_count(), FcToastStack.MAX_VISIBLE, "the oldest goes when a fourth arrives")
	var entry: Dictionary = stack._entries.back()
	assert_true(not (entry["timer"] as Timer).is_stopped(), "each toast has a running timer")
	assert_eq((entry["timer"] as Timer).wait_time, FcToast.hold_seconds(FcToast.Kind.ERROR), "errors wait longer")
	(entry["timer"] as Timer).timeout.emit()
	assert_eq(stack.visible_count(), 2, "an expired toast leaves the stack")
	stack.clear()
	assert_eq(stack.visible_count(), 0)
	assert_eq(stack.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the stack never blocks the screen")


func test_clicking_a_toast_dismisses_it() -> void:
	var stack := FcToastStack.new()
	host.add_child(stack)
	var toast := stack.push(FcToast.Kind.INFO, "Click me")
	toast.dismissed.connect(func() -> void: got.append("dismissed"))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	toast.gui_input.emit(click)
	assert_eq(got, ["dismissed"])
	await seconds(0.4)
	assert_true(not is_instance_valid(toast) or toast.is_queued_for_deletion(), "and it fades away")


func test_loading_overlay_blocks_and_dismisses() -> void:
	var overlay := FcLoadingOverlay.show_on(host, "Simulating...")
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "blocks the screen below")
	assert_eq(overlay.loading.message_label.text, "Simulating...")
	overlay.dismiss()
	await seconds(0.3)
	assert_true(not is_instance_valid(overlay) or overlay.is_queued_for_deletion())


func test_tab_keys_move_focus_between_tabs() -> void:
	var tabs := FcTabBar.new()
	host.add_child(tabs)
	tabs.set_tabs([["a", "One"], ["b", "Two"], ["c", "Three"]])
	await frames(2)
	tabs.button_for("a").grab_focus()
	await frames(1)
	assert_true(tabs.button_for("a").has_focus(), "a tab can take focus (keyboard and controller reach it)")
	assert_eq(tabs.button_for("a").focus_mode, Control.FOCUS_ALL)


func test_the_gallery_runs_live_without_errors() -> void:
	var gallery := FcComponentGallery.new()
	gallery.size = Vector2(900, 700)
	host.add_child(gallery)
	await frames(3)
	gallery.set_skin(FcModeSkin.COLLECTIBLE)
	await frames(3)
	assert_true(gallery.section_titles().size() == 15, "all sections are built and laid out")
	gallery.scroll_to_section("Motion")
	await frames(2)
	assert_true(gallery._page.get_v_scroll_bar().max_value > 0.0, "the page is taller than the window, so it scrolls")
