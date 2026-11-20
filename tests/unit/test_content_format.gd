extends FcTestCase
## Manifest, checksums, safe paths and the content validator.

const ID_A := "fcr_00000000000000a1"
const ID_B := "fcr_00000000000000b2"

var defs: FcDefinitionSet
var content: String
var release: String


func before_each() -> void:
	FcContentFixture.wipe()
	defs = FcTestData.defs()
	content = FcContentFixture.ROOT.path_join("draft_content")
	release = FcContentFixture.ROOT.path_join("release_a")
	FcContentFixture.write_sample_content(content)


func after_each() -> void:
	FcContentFixture.wipe()


func _validate() -> FcContentResult:
	return FcContentValidator.validate_release_dir(release, FcVersion.GAME_VERSION, defs)


func test_manifest_round_trips_and_checksum_is_stable() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	var back := FcContentManifest.from_file(release.path_join("manifest.json"))
	assert_true(back.validate().is_empty(), "a built manifest is well formed: %s" % str(back.validate()))
	assert_eq(back.compute_checksum(), m.manifest_checksum, "checksum survives write and read (ints, not floats)")
	for i in 5:
		assert_eq(m.compute_checksum(), m.manifest_checksum, "checksum is stable across repeated serialization")


func test_checksum_excludes_its_own_field_and_changes_with_content() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	var before := m.compute_checksum()
	m.manifest_checksum = "x"
	assert_eq(m.compute_checksum(), before, "the checksum field is not part of its own hash")
	m.content_version = 99
	assert_true(m.compute_checksum() != before, "any other change alters the checksum")


func test_files_hash_raw_bytes_including_art() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	for e in m.files:
		var bytes := FcSafeFile.read_bytes(release.path_join(e["path"]))
		assert_eq(e["sha256"], FcSafeFile.hash_bytes(bytes), "sha256 over the raw bytes of %s" % e["path"])
		assert_eq(int(e["bytes"]), bytes.size(), "size of %s" % e["path"])


func test_a_good_release_validates() -> void:
	FcContentFixture.build_release(content, release, ID_A)
	var r := _validate()
	assert_true(r.is_ok(), "valid release accepted: %s %s" % [r.message, str(r.problems)])
	assert_eq((r.value as FcContentManifest).release_id, ID_A, "manifest returned")


func test_tampered_file_is_rejected() -> void:
	FcContentFixture.build_release(content, release, ID_A)
	FcSafeFile.write_text(release.path_join("players/sample_big.json"), "{}")
	assert_eq(_validate().code, FcContentResult.Code.CORRUPT, "changed file")


func test_missing_asset_is_rejected() -> void:
	FcContentFixture.build_release(content, release, ID_A)
	DirAccess.remove_absolute(release.path_join("art/sample_guard_base.png"))
	assert_eq(_validate().code, FcContentResult.Code.MISSING_ASSET, "missing art")


func test_unlisted_file_is_rejected() -> void:
	FcContentFixture.build_release(content, release, ID_A)
	FcSafeFile.write_text(release.path_join("players/sneaky.json"), "{}")
	assert_eq(_validate().code, FcContentResult.Code.INVALID, "file not in manifest")


func test_altered_manifest_is_rejected() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	m.approved_by = "Somebody Else"
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_eq(_validate().code, FcContentResult.Code.CORRUPT, "manifest changed after sealing")


func test_newer_schema_is_rejected_and_current_loads() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	m.schema_version = FcContentFeatures.SCHEMA_VERSION + 1
	m.seal()
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_eq(_validate().code, FcContentResult.Code.INCOMPATIBLE, "newer schema")
	m.schema_version = FcContentFeatures.MIN_SCHEMA_VERSION
	m.seal()
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_true(_validate().is_ok(), "oldest supported schema still loads")


func test_unknown_feature_and_newer_game_version_fail_closed() -> void:
	var m := FcContentFixture.build_release(content, release, ID_A)
	m.requires_features = ["pack_random_v9"]
	m.seal()
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_eq(_validate().code, FcContentResult.Code.INCOMPATIBLE, "unknown feature")
	m.requires_features = []
	m.min_game_version = "99.0.0"
	m.seal()
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_eq(_validate().code, FcContentResult.Code.INCOMPATIBLE, "needs a newer game")


func test_unsafe_paths_are_rejected() -> void:
	for bad in ["../x.json", "/etc/x.json", "players/../../x.json", "C:/x.json", "players\\x.json", "", ".", "a//b", "players/x.json."]:
		assert_true(not FcSafeFile.is_safe_relative_path(bad), "unsafe: '%s'" % bad)
	assert_true(FcSafeFile.is_safe_relative_path("art/a.png"), "plain relative path is fine")
	var m := FcContentFixture.build_release(content, release, ID_A)
	m.files.append({"path": "../outside.json", "kind": "player", "bytes": 1, "sha256": "0".repeat(64)})
	m.seal()
	FcSafeFile.write_text(release.path_join("manifest.json"), m.text())
	assert_eq(_validate().code, FcContentResult.Code.INVALID, "a manifest path escaping the release")


func test_card_art_must_stay_inside_the_art_folder() -> void:
	FcSafeFile.write_text(content.path_join("cards/sample_big_base.json"), JSON.stringify({
		"card_id": "sample_big_base", "player_id": "sample_big", "title": "Sample Big",
		"rarity": "rare", "revision": 1, "art": "../../secret.png"}))
	var problems := FcContentValidator.draft_problems(content, defs)
	assert_true(str(problems).contains("safe path"), "escaping art reference reported: %s" % str(problems))


func test_definition_problems_are_all_reported() -> void:
	FcSafeFile.write_text(content.path_join("cards/orphan.json"), JSON.stringify({
		"card_id": "orphan", "player_id": "nobody", "title": "X", "rarity": "mythic", "revision": 0}))
	FcSafeFile.write_text(content.path_join("packs/bad_pack.json"), JSON.stringify({
		"pack_id": "bad_pack", "name": "Bad", "card_ids": ["ghost"]}))
	FcSafeFile.write_text(content.path_join("players/wrong_name.json"), JSON.stringify({
		"player_id": "other_id", "display_name": "P", "position": "XX", "attributes": {"made_up": 150}}))
	FcSafeFile.write_text(content.path_join("support/decimals.json"), JSON.stringify({
		"support_id": "decimals", "rate": 0.5}))
	var text := str(FcContentValidator.draft_problems(content, defs))
	for fragment in ["is not a player", "rarity must", "revision must", "ghost", "file name must match",
			"position must", "unknown attribute", "0 to 100", "decimal number"]:
		assert_true(text.contains(fragment), "reports '%s'" % fragment)


func test_unsupported_file_locations_are_reported() -> void:
	FcSafeFile.write_text(content.path_join("scripts/evil.gd"), "extends Node")
	FcSafeFile.write_text(content.path_join("players/deep/x.json"), "{}")
	var text := str(FcContentValidator.draft_problems(content, defs))
	assert_true(text.contains("scripts/evil.gd") and text.contains("players/deep/x.json"), "bad locations: %s" % text)


func test_card_identity_and_revision_rules() -> void:
	var old := {"c1": {"card_id": "c1", "player_id": "p1", "title": "A", "rarity": "common", "revision": 1}}
	var same := old.duplicate(true)
	assert_true(FcContentValidator.revision_problems(same, old).is_empty(), "unchanged card is fine")
	var edited := old.duplicate(true)
	edited["c1"]["title"] = "B"
	assert_true(not FcContentValidator.revision_problems(edited, old).is_empty(), "same revision, new content: rejected")
	edited["c1"]["revision"] = 2
	assert_true(FcContentValidator.revision_problems(edited, old).is_empty(), "higher revision allows the change")
	edited["c1"]["revision"] = 0
	assert_true(not FcContentValidator.revision_problems(edited, old).is_empty(), "revision cannot go backwards")
	var moved := old.duplicate(true)
	moved["c1"]["player_id"] = "p2"
	moved["c1"]["revision"] = 5
	assert_true(not FcContentValidator.revision_problems(moved, old).is_empty(), "a card keeps its player forever")
	assert_true(FcContentValidator.revision_problems(old, {}).is_empty(), "new cards are fine")


func test_version_compare() -> void:
	assert_eq(FcSafeFile.compare_versions("0.1.0", "0.1.0"), 0, "equal")
	assert_eq(FcSafeFile.compare_versions("0.2.0", "0.10.0"), -1, "numeric, not text, order")
	assert_eq(FcSafeFile.compare_versions("1.0.0", "0.9.9"), 1, "major wins")
