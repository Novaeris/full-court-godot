class_name FcContentFixture
extends RefCounted
## Sample content for the content-publishing tests. Not real game content: the names are invented
## test strings, written into scratch folders under user://.

const ROOT := "user://test_content"


static func wipe(path: String = ROOT) -> void:
	FcSafeFile.remove_tree(path)


## Writes a small valid draft: 2 players, 2 cards (one with art), 1 pack.
static func write_sample_content(dir: String, suffix: String = "") -> void:
	FcSafeFile.make_dir(dir)
	_json(dir, "players/sample_guard.json", {
		"player_id": "sample_guard", "display_name": "Sample Guard%s" % suffix, "position": "PG",
		"attributes": {"three_point": 80, "ball_handling": 75},
	})
	_json(dir, "players/sample_big.json", {
		"player_id": "sample_big", "display_name": "Sample Big", "position": "C",
		"attributes": {"rebounding": 85, "interior_defense": 78},
	})
	_json(dir, "cards/sample_guard_base.json", {
		"card_id": "sample_guard_base", "player_id": "sample_guard", "title": "Sample Guard",
		"rarity": "common", "revision": 1, "art": "art/sample_guard_base.png",
		"requires_features": ["card_rarity_v1"],
	})
	_json(dir, "cards/sample_big_base.json", {
		"card_id": "sample_big_base", "player_id": "sample_big", "title": "Sample Big",
		"rarity": "rare", "revision": 1,
	})
	_json(dir, "packs/starter_pack.json", {
		"pack_id": "starter_pack", "name": "Starter Pack",
		"card_ids": ["sample_guard_base", "sample_big_base"], "requires_features": ["pack_fixed_v1"],
	})
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.8))
	FcSafeFile.write_bytes(dir.path_join("art/sample_guard_base.png"), img.save_png_to_buffer())


static func _json(dir: String, rel: String, data: Dictionary) -> void:
	FcSafeFile.write_text(dir.path_join(rel), JSON.stringify(data, "\t", true))


## Builds a sealed release folder from a content folder by hand (independent of the publisher).
static func build_release(content_dir: String, release_dir: String, release_id: String,
		previous: String = "", content_version: int = 1) -> FcContentManifest:
	var m := FcContentManifest.new()
	m.release_id = release_id
	m.content_version = content_version
	m.previous_release_id = previous
	m.published_at = 1700000000 + content_version
	m.published_by = "Tester"
	m.approved_by = "Tester"
	m.approval_note = "fixture"
	for p in FcSafeFile.list_files(content_dir):
		FcSafeFile.copy_file(content_dir.path_join(p), release_dir.path_join(p))
		m.files.append({
			"path": p, "kind": FcContentManifest.kind_for_path(p),
			"bytes": FcSafeFile.read_bytes(content_dir.path_join(p)).size(),
			"sha256": FcSafeFile.hash_file(content_dir.path_join(p)),
		})
	m.seal()
	FcSafeFile.write_text(release_dir.path_join(FcContentManifest.FILE_NAME), m.text())
	return m
