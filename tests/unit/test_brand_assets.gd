extends FcTestCase
## The brand asset set (D-057, docs/ASSET_SPEC.md): every file the manifest names exists, lockups are really transparent,
## icons and the boot splash have the sizes the platforms need, and no resized copy is larger than its master.

const MANIFEST := "res://data/ui/brand.json"


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _image(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path("res://" + path))


func test_manifest_loads_and_has_both_brands() -> void:
	var m := _manifest()
	assert_true(not m.is_empty(), "brand.json must parse")
	var brands := {}
	for id in m.get("assets", {}):
		brands[str(m["assets"][id]["brand"])] = true
	assert_true(brands.has("full_court") and brands.has("novaeris"), "both logos are described")


func test_every_named_file_exists_and_loads() -> void:
	var m := _manifest()
	for id in m.get("assets", {}):
		var a: Dictionary = m["assets"][id]
		assert_true(_image(a["file"]) != null, "%s loads" % id)
		for w in a.get("sizes", {}):
			assert_true(_image(a["sizes"][w]) != null, "%s at %s loads" % [id, w])
	assert_true(FileAccess.file_exists("res://" + str(m.get("windows_icon", ""))), "the Windows icon exists")


func test_transparent_assets_have_clear_corners_and_visible_content() -> void:
	var m := _manifest()
	for id in m.get("assets", {}):
		var a: Dictionary = m["assets"][id]
		if not a.get("transparent", false):
			continue
		var img := _image(a["file"])
		if img == null:
			continue
		assert_true(img.detect_alpha() != Image.ALPHA_NONE, "%s has an alpha channel" % id)
		for p in [Vector2i(0, 0), Vector2i(img.get_width() - 1, 0), Vector2i(0, img.get_height() - 1), Vector2i(img.get_width() - 1, img.get_height() - 1)]:
			assert_true(img.get_pixelv(p).a < 0.2, "%s corner %s is see-through" % [id, str(p)])
		var opaque := 0
		for i in 400:
			var x := (i * 7919) % img.get_width()
			var y := (i * 104729) % img.get_height()
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
		assert_true(opaque > 8, "%s has visible content" % id)


func test_resized_copies_are_never_larger_than_the_master() -> void:
	var m := _manifest()
	for id in m.get("assets", {}):
		var a: Dictionary = m["assets"][id]
		var master := _image(a["file"])
		if master == null:
			continue
		for w in a.get("sizes", {}):
			var copy := _image(a["sizes"][w])
			if copy != null:
				assert_true(copy.get_width() <= master.get_width(), "%s %s is not an upscale" % [id, w])
				assert_eq(copy.get_width(), int(w), "%s copy has the width in its name" % id)


func test_icons_and_splash_have_the_platform_sizes() -> void:
	var m := _manifest()
	for id in m.get("icons", {}):
		var spec: Dictionary = m["icons"][id]
		var img := _image(spec["file"])
		assert_true(img != null, "%s loads" % id)
		if img != null:
			assert_eq(img.get_width(), int(spec["w"]), "%s width" % id)
			assert_eq(img.get_height(), int(spec["h"]), "%s height" % id)
	var splash: Dictionary = m.get("boot_splash", {})
	var s := _image(str(splash.get("file", "")))
	assert_true(s != null, "boot splash loads")
	if s != null:
		assert_eq(s.get_width(), 1280)
		assert_eq(s.get_height(), 720)
		assert_true(s.get_pixel(2, 2).is_equal_approx(Color("0B1020")), "the splash background is the brand navy")


func test_source_banners_are_kept_out_of_the_game_import() -> void:
	assert_true(FileAccess.file_exists("res://assets/brand/source/.gdignore"), "source banners must not be imported or exported")
