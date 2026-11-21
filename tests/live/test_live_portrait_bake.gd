extends FcLiveTestCase
## The portrait texture cache (D-059): keys hold everything that changes a picture (no cross-player or cross-context mix-ups), the 20 MB
## budget is a hard ceiling with least-recently-used eviction, near sizes share a picture, and drawing never depends on the cache (headless
## cannot read pixels back, so the figure is drawn live and nothing errors). Real baking is measured in a window by tools/portrait_perf.gd.


class Probe extends Control:
	var visual: Dictionary = {}
	var mode := "bust"

	func _draw() -> void:
		match mode:
			"full":
				FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual, true)
			"head":
				FcPlayerFigure.draw_headshot(self, Rect2(Vector2.ZERO, size), visual)
			_:
				FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual)


func after_each() -> void:
	FcPlayerFigure.hd_enabled = true
	super.after_each()


func _visual(key: String, age: int = 0, primary: String = "#1F3A5F", extra: Dictionary = {}) -> Dictionary:
	var subject := FcPlayerPresentation.subject(key, "Bake Test", {"name": "T", "abbreviation": "TTT", "primary": primary, "secondary": "#C8A951"}, 7, {}, "", extra)
	if age > 0:
		subject["age"] = age
	return FcPlayerVisual.resolve(subject)


func _image(px: int) -> Image:
	return Image.create_empty(px, px, false, Image.FORMAT_RGBA8)


func test_the_budget_is_twenty_megabytes() -> void:
	var bake := FcPortraitBake.new()
	host.add_child(bake)
	assert_eq(bake.budget_bytes, 20 * 1024 * 1024, "the approved hard ceiling")


func test_a_changed_picture_is_a_different_key() -> void:
	var base := FcPortraitBake.cache_key(_visual("k:1"), Vector2i(96, 96), "bust")
	assert_eq(base, FcPortraitBake.cache_key(_visual("k:1"), Vector2i(96, 96), "bust"), "the same player in the same context is one key")
	var others := [
		FcPortraitBake.cache_key(_visual("k:2"), Vector2i(96, 96), "bust"),
		FcPortraitBake.cache_key(_visual("k:1", 31), Vector2i(96, 96), "bust"),
		FcPortraitBake.cache_key(_visual("k:1", 0, "#7A1F2B"), Vector2i(96, 96), "bust"),
		FcPortraitBake.cache_key(_visual("k:1"), Vector2i(64, 64), "bust"),
		FcPortraitBake.cache_key(_visual("k:1"), Vector2i(96, 96), "head"),
		FcPortraitBake.cache_key(_visual("k:1"), Vector2i(96, 96), "bust", 0.5),
		FcPortraitBake.cache_key(_visual("k:1", 0, "#1F3A5F", {"position": "C", "physical": {"height_cm": 211, "weight_kg": 120}}), Vector2i(96, 96), "bust"),
	]
	for k in others:
		assert_true(k != base, "a change of player, age, kit, size, crop, aspect or body is a different picture: %s" % k)
	var seen := {}
	for k in others:
		seen[k] = true
	assert_eq(seen.size(), others.size(), "and they differ from each other")


func test_the_shipped_and_hd_pictures_never_share_an_entry() -> void:
	var v := _visual("bake:switch")
	var hd := FcPortraitBake.cache_key(v, Vector2i(64, 64), "bust")
	FcPlayerFigure.hd_enabled = false
	assert_true(hd != FcPortraitBake.cache_key(v, Vector2i(64, 64), "bust"))


func test_near_sizes_share_one_picture_and_the_step_always_covers_the_need() -> void:
	assert_eq(FcPortraitBake.step_for(40.0), 48)
	assert_eq(FcPortraitBake.step_for(48.0), 48)
	assert_eq(FcPortraitBake.step_for(49.0), 64)
	assert_eq(FcPortraitBake.step_for(9999.0), 512, "the largest step is the cap")
	for needed in [10.0, 33.0, 100.0, 300.0, 500.0]:
		assert_true(float(FcPortraitBake.step_for(needed)) >= needed, "the step covers the pixels needed")


func test_the_hard_budget_evicts_the_least_recently_used() -> void:
	var bake := FcPortraitBake.new()
	bake.budget_bytes = 64 * 64 * 4 * 5   # five 64 px pictures
	host.add_child(bake)
	for i in 5:
		bake.store_image("p%d" % i, _image(64))
	assert_eq(bake.size(), 5)
	assert_true(bake.bytes_used() <= bake.budget_bytes)
	bake.store_image("p5", _image(64))
	assert_eq(bake.size(), 5, "the sixth evicted one")
	assert_true(bake._entries.has("p5") and not bake._entries.has("p0"), "the oldest went first")
	assert_true(bake.bytes_used() <= bake.budget_bytes, "never over the ceiling")
	assert_eq(bake.stats["evicted"], 1)


func test_flooding_the_real_budget_never_exceeds_twenty_megabytes() -> void:
	var bake := FcPortraitBake.new()
	host.add_child(bake)
	for i in 400:
		bake.store_image("flood:%d" % i, _image(192))   # 144 KB each, 57 MB offered
		assert_true(bake.bytes_used() <= 20 * 1024 * 1024, "over the ceiling at picture %d" % i)
	assert_true(bake.size() < 400 and bake.stats["evicted"] > 0)
	assert_true(bake.stats["peak_bytes"] <= 20 * 1024 * 1024)
	bake.clear()
	assert_eq(bake.bytes_used(), 0, "clear releases everything")
	assert_eq(bake.size(), 0)


func test_a_picture_larger_than_the_whole_budget_is_refused() -> void:
	var bake := FcPortraitBake.new()
	bake.budget_bytes = 1000
	host.add_child(bake)
	bake.store_image("big", _image(64))
	assert_eq(bake.size(), 0)


func test_drawing_with_a_cache_present_still_works_and_never_errors() -> void:
	var bake := FcPortraitBake.new()
	host.add_child(bake)
	assert_true(FcPortraitBake.shared == bake)
	var probes: Array = []
	for i in 30:
		var p := Probe.new()
		p.visual = _visual("bakedraw:%d" % (i % 10), 20 + i % 15)
		p.mode = ["bust", "head", "full"][i % 3]
		p.size = Vector2(80, 80 if p.mode != "full" else 180)
		host.add_child(p)
		probes.append(p)
	await frames(6)
	assert_eq(probes.size(), 30)
	assert_true(bake.stats["misses"] > 0, "the cache was asked")
	for p in probes:
		p.queue_redraw()
	await frames(3)
	assert_true(bake.bytes_used() <= bake.budget_bytes)


func test_a_missing_cache_draws_live() -> void:
	assert_true(FcPortraitBake.shared == null)
	var p := Probe.new()
	p.visual = _visual("nocache:1")
	p.size = Vector2(64, 64)
	host.add_child(p)
	await frames(3)
	assert_true(p.is_inside_tree(), "drawn live without a cache")
