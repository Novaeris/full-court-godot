extends FcLiveTestCase
## The portrait bake cache (prototype): a figure is drawn once into a texture, the same picture is reused, anything that changes the picture
## makes a new one, the cache is bounded, and the baked picture really contains the figure.


func after_each() -> void:
	FcPlayerFigure.hd_enabled = false
	super.after_each()


func _visual(key: String, age: int = 0, primary: String = "#1F3A5F") -> Dictionary:
	var v := FcPlayerVisual.resolve(FcPlayerPresentation.subject(key, "Bake Test", {"name": "T", "abbreviation": "TTT", "primary": primary, "secondary": "#C8A951"}, 7))
	if age > 0:
		v["age"] = age
	return v


func test_the_same_picture_is_reused_and_a_changed_one_is_new() -> void:
	var bake := FcPortraitBake.new()
	host.add_child(bake)
	var a := bake.texture_for(_visual("bake:1"), Vector2i(96, 96))
	var again := bake.texture_for(_visual("bake:1"), Vector2i(96, 96))
	assert_true(a == again, "the same player at the same size is one picture")
	assert_eq(bake.stats["hits"], 1)
	bake.texture_for(_visual("bake:1", 31), Vector2i(96, 96))
	bake.texture_for(_visual("bake:1", 0, "#7A1F2B"), Vector2i(96, 96))
	bake.texture_for(_visual("bake:1"), Vector2i(64, 64))
	bake.texture_for(_visual("bake:1"), Vector2i(96, 96), "head")
	assert_eq(bake.size(), 5, "a new age, new colours, a new size and a new crop each make a new picture")


func test_the_cache_is_bounded() -> void:
	var bake := FcPortraitBake.new()
	bake.max_entries = 12
	host.add_child(bake)
	for i in 30:
		bake.texture_for(_visual("bounded:%d" % i), Vector2i(32, 32))
	assert_eq(bake.size(), 12, "only the most recent pictures are kept")
	assert_eq(bake.stats["evicted"], 18)


func test_a_baked_picture_contains_the_figure() -> void:
	FcPlayerFigure.hd_enabled = true
	var bake := FcPortraitBake.new()
	host.add_child(bake)
	var tex := bake.texture_for(_visual("bake:pixels"), Vector2i(128, 128))
	await frames(4)
	var image := tex.get_image()
	if image == null:
		print("NOTE: the headless renderer cannot read pixels; this check runs in the windowed sheet (tools/portrait_sheet.gd job 'baked')")
		return
	assert_eq(image.get_size(), Vector2i(128, 128))
	var opaque := 0
	for y in range(0, 128, 4):
		for x in range(0, 128, 4):
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_true(opaque > 300, "the figure covers much of the picture (%d of 1024 samples)" % opaque)
	var corner := image.get_pixel(1, 1)
	assert_true(corner.a < 0.1, "and the background stays transparent")


func test_the_cache_key_changes_with_the_figure_switch() -> void:
	var v := _visual("bake:switch")
	var off := FcPortraitBake.cache_key(v, Vector2i(64, 64), "bust")
	FcPlayerFigure.hd_enabled = true
	assert_true(off != FcPortraitBake.cache_key(v, Vector2i(64, 64), "bust"), "the shipped and the HD pictures never share an entry")
