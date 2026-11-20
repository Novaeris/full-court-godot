extends FcLiveTestCase
## FcMotion with real tweens in a live scene tree: each animation ends in its documented end state, and reduced motion removes
## movement and scale while keeping only a short fade.


func test_fade_in_runs_and_ends_visible() -> void:
	var node := ColorRect.new()
	host.add_child(node)
	var tw := FcMotion.fade_in(node, 0.06)
	assert_true(tw != null and tw.is_running(), "a real tween runs in the tree")
	assert_eq(node.modulate.a, 0.0, "starts transparent")
	await seconds(0.2)
	assert_eq(node.modulate.a, 1.0, "ends visible")


func test_pop_in_scales_from_the_centre_and_settles_at_full_size() -> void:
	var node := ColorRect.new()
	node.size = Vector2(100, 60)
	host.add_child(node)
	FcMotion.pop_in(node, 0.08)
	assert_true(node.scale.x < 1.0, "starts smaller")
	assert_eq(node.pivot_offset, Vector2(50, 30), "scales from the centre")
	await seconds(0.25)
	assert_eq(node.scale, Vector2.ONE)
	assert_eq(node.modulate.a, 1.0)


func test_slide_in_returns_to_the_resting_position() -> void:
	var node := ColorRect.new()
	node.position = Vector2(40, 10)
	host.add_child(node)
	FcMotion.slide_in(node, Vector2(-30, 0), 0.08)
	assert_eq(node.position, Vector2(10, 10), "starts offset")
	await seconds(0.25)
	assert_eq(node.position, Vector2(40, 10), "ends where it belongs")


func test_fade_out_frees_the_node_when_done() -> void:
	var node := ColorRect.new()
	host.add_child(node)
	FcMotion.fade_out(node, 0.05, true)
	assert_true(not node.is_queued_for_deletion(), "still there while fading")
	await seconds(0.2)
	assert_true(not is_instance_valid(node) or node.is_queued_for_deletion(), "freed afterwards")


func test_press_feedback_springs_back() -> void:
	var node := ColorRect.new()
	node.size = Vector2(80, 30)
	host.add_child(node)
	var tw := FcMotion.press(node)
	assert_true(tw != null, "animated")
	await seconds(0.25)
	assert_eq(node.scale, Vector2.ONE, "back to normal size")


func test_count_to_counts_up_and_ends_on_the_target() -> void:
	var label := Label.new()
	host.add_child(label)
	FcMotion.count_to(label, 0, 1200, 0.15, func(n: int) -> String: return "%d cr" % n)
	await seconds(0.05)
	var mid := int(label.text.get_slice(" ", 0))
	assert_true(mid >= 0 and mid <= 1200, "a number in between while counting")
	await seconds(0.3)
	assert_eq(label.text, "1200 cr")


func test_reduced_motion_removes_movement_and_keeps_a_short_fade() -> void:
	FcMotion.reduced = true
	var node := ColorRect.new()
	node.size = Vector2(100, 60)
	node.position = Vector2(40, 10)
	host.add_child(node)
	var tw := FcMotion.pop_in(node, 0.5)
	assert_eq(node.scale, Vector2.ONE, "no scaling")
	assert_true(tw != null, "only the fade remains")
	await seconds(0.2)
	assert_eq(node.modulate.a, 1.0, "the 0.5 s fade is done within 80 ms (plus a frame)")
	FcMotion.slide_in(node, Vector2(-50, 0), 0.5)
	assert_eq(node.position, Vector2(40, 10), "no sliding")
	assert_true(FcMotion.press(node) == null, "no press feedback")


func test_spinner_turns_only_when_motion_is_allowed() -> void:
	var loading := FcLoading.new("Working")
	host.add_child(loading)
	await frames(6)
	var spinner = loading._spinner
	assert_true(spinner._angle > 0.0, "the arc rotates")
	FcMotion.reduced = true
	var still := FcLoading.new("Working")
	host.add_child(still)
	await frames(6)
	assert_eq(still._spinner._angle, 0.0, "a reduced-motion spinner stays still")
