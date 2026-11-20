extends FcTestCase
## FcMotion without a live scene tree: the duration rules, and the rule that a node outside the tree simply receives the end
## state. (Real tweens run in the live tests, tests/live/test_live_motion.gd: the unit runner starts before the first frame,
## when nodes are not yet inside the tree.)


func after_each() -> void:
	FcMotion.reduced = false


func test_durations_follow_the_reduce_motion_setting() -> void:
	assert_eq(FcMotion.duration(0.4), 0.4, "normal motion keeps the length")
	assert_eq(FcMotion.duration(0.4, true), 0.4)
	FcMotion.reduced = true
	assert_eq(FcMotion.duration(0.4), 0.0, "movement is instant when reduced")
	assert_eq(FcMotion.duration(0.4, true), FcUiTokens.DUR_REDUCED_FADE, "fades are capped at 80 ms")
	assert_eq(FcMotion.duration(0.05, true), 0.05, "short fades stay as they are")


func test_a_node_outside_the_tree_gets_the_end_state() -> void:
	var node := ColorRect.new()
	node.size = Vector2(100, 60)
	assert_true(FcMotion.fade_in(node) == null, "no tween without a tree")
	assert_eq(node.modulate.a, 1.0, "but it is visible")
	node.modulate.a = 0.2
	FcMotion.pop_in(node)
	assert_eq(node.scale, Vector2.ONE)
	assert_eq(node.modulate.a, 1.0)
	node.position = Vector2(40, 10)
	FcMotion.slide_in(node, Vector2(-30, 0))
	assert_eq(node.position, Vector2(40, 10), "slide_in leaves it where it belongs")
	assert_true(FcMotion.press(node) == null)
	assert_eq(node.scale, Vector2.ONE)
	node.free()


func test_fade_out_frees_a_node_outside_the_tree() -> void:
	var loose := ColorRect.new()
	FcMotion.fade_out(loose, 0.2, true)
	assert_true(loose.is_queued_for_deletion(), "freed at once")
	var kept := ColorRect.new()
	FcMotion.fade_out(kept, 0.2, false)
	assert_eq(kept.modulate.a, 0.0, "faded without being freed")
	assert_true(not kept.is_queued_for_deletion())
	kept.free()


func test_count_to_and_tween_property_jump_without_a_tree() -> void:
	var label := Label.new()
	FcMotion.count_to(label, 0, 1200, 0.5, func(n: int) -> String: return "%d cr" % n)
	assert_eq(label.text, "1200 cr", "the number is final and formatted")
	var plain := Label.new()
	FcMotion.count_to(plain, 5, 99)
	assert_eq(plain.text, "99")
	var node := ColorRect.new()
	FcMotion.tween_property(node, "rotation", 1.5)
	assert_eq(node.rotation, 1.5)
	for n in [label, plain, node]:
		n.free()


func test_reduced_motion_makes_everything_instant_even_in_a_tree() -> void:
	FcMotion.reduced = true
	var label := Label.new()
	assert_true(FcMotion.count_to(label, 0, 99) == null)
	assert_eq(label.text, "99")
	label.free()
