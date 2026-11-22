class_name FcContentValidator
extends RefCounted
## Checks content before it is published (drafts) and before it is trusted (releases).
##
## WHY: published definitions decide who the players and cards ARE, so nothing is
## believed until it checks out: well-formed, every file present with a matching
## checksum, every path safe, every cross-reference resolvable, no floats.
## All problems are collected (the owner sees the whole list, not only the first).

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const POSITIONS := FcPosition.PLAYABLE
const ID_PATTERN := "^[a-z0-9_]{1,48}$"
const MAX_TEXT := 200


## Problems in a draft's content folder (no manifest yet). Empty = ready to publish.
## `definitions` is the shared attribute catalog set; when null attribute names are not checked.
static func draft_problems(content_dir: String, definitions: FcDefinitionSet = null) -> Array[String]:
	var errors: Array[String] = []
	var paths := FcSafeFile.list_files(content_dir)
	for p in paths:
		if FcContentManifest.kind_for_path(p).is_empty():
			errors.append("file '%s' is not in an allowed folder or has an unsupported type" % p)
	if paths.is_empty():
		errors.append("the draft has no content files")
	var allowed: Array[String] = []
	for p in paths:
		if not FcContentManifest.kind_for_path(p).is_empty():
			allowed.append(p)
	errors.append_array(check_definitions(content_dir, allowed, definitions)["problems"])
	return errors


## Full check of a release folder as the game sees it. On success `value` is the manifest.
static func validate_release_dir(release_dir: String, game_version: String,
		definitions: FcDefinitionSet = null) -> FcContentResult:
	var manifest_path := release_dir.path_join(FcContentManifest.FILE_NAME)
	if not FileAccess.file_exists(manifest_path):
		return FcContentResult.failure(FcContentResult.Code.NOT_FOUND, "the release has no manifest")
	var manifest := FcContentManifest.from_file(manifest_path)
	if manifest == null:
		return FcContentResult.failure(FcContentResult.Code.CORRUPT, "the release manifest cannot be read")
	var structure := manifest.validate()
	if not structure.is_empty():
		return FcContentResult.failure(FcContentResult.Code.INVALID, "the release manifest is not valid", structure)
	if manifest.compute_checksum() != manifest.manifest_checksum:
		return FcContentResult.failure(FcContentResult.Code.CORRUPT,
			"the release manifest was altered (checksum mismatch)")
	var compat := manifest.compatibility_problems(game_version)
	if not compat.is_empty():
		return FcContentResult.failure(FcContentResult.Code.INCOMPATIBLE,
			"the release is not compatible with this game", compat)
	var listed := {}
	var missing: Array[String] = []
	var damaged: Array[String] = []
	for e in manifest.files:
		var p: String = e["path"]
		listed[p] = true
		var full := release_dir.path_join(p)
		if not FileAccess.file_exists(full):
			missing.append("file '%s' is missing" % p)
			continue
		if FileAccess.get_file_as_bytes(full).size() != int(e["bytes"]) or FcSafeFile.hash_file(full) != e["sha256"]:
			damaged.append("file '%s' does not match its checksum" % p)
	if not missing.is_empty():
		return FcContentResult.failure(FcContentResult.Code.MISSING_ASSET, "the release is missing files", missing)
	if not damaged.is_empty():
		return FcContentResult.failure(FcContentResult.Code.CORRUPT, "the release files are damaged", damaged)
	var extra: Array[String] = []
	for p in FcSafeFile.list_files(release_dir):
		if p != FcContentManifest.FILE_NAME and not listed.has(p):
			extra.append("file '%s' is not listed in the manifest" % p)
	if not extra.is_empty():
		return FcContentResult.failure(FcContentResult.Code.INVALID, "the release has unlisted files", extra)
	var paths: Array[String] = []
	for e in manifest.files:
		paths.append(e["path"])
	var checked := check_definitions(release_dir, paths, definitions)
	if not checked["problems"].is_empty():
		return FcContentResult.failure(FcContentResult.Code.INVALID,
			"the release definitions are not valid", checked["problems"])
	var ok := FcContentResult.success(manifest)
	return ok


## Reads every listed definition file and checks it. Returns
## {"problems": Array[String], "defs": {kind: {id: Dictionary}}}.
static func check_definitions(dir: String, paths: Array[String], definitions: FcDefinitionSet = null) -> Dictionary:
	var errors: Array[String] = []
	var defs := {"player": {}, "card": {}, "pack": {}, "challenge": {}, "seasonal": {}, "set": {}, "support": {}}
	var path_set := {}
	for p in paths:
		path_set[p] = true
	for p in paths:
		var kind := FcContentManifest.kind_for_path(p)
		if kind.is_empty() or kind == "art":
			continue
		var data = FcSafeFile.read_json_object(dir.path_join(p))
		if data == null:
			errors.append("%s: not a readable JSON object" % p)
			continue
		var id_field: String = FcContentFeatures.ID_FIELDS[kind]
		var id := str(data.get(id_field, ""))
		var id_re := RegEx.new()
		id_re.compile(ID_PATTERN)
		if id_re.search(id) == null:
			errors.append("%s: %s must be 1-48 lowercase letters, digits or underscores" % [p, id_field])
			continue
		if p.get_file().get_basename() != id:
			errors.append("%s: the file name must match its %s ('%s')" % [p, id_field, id])
		if defs[kind].has(id):
			errors.append("%s: duplicate %s '%s'" % [p, id_field, id])
			continue
		_check_common(p, data, errors)
		defs[kind][id] = data
	for id in defs["player"]:
		_check_player("players/%s.json" % id, defs["player"][id], definitions, errors)
		FcDynastyContentRules.check_player("players/%s.json" % id, defs["player"][id], definitions, errors)
	for id in defs["card"]:
		_check_card("cards/%s.json" % id, defs["card"][id], defs["player"], path_set, errors)
		FcDynastyContentRules.check_card("cards/%s.json" % id, defs["card"][id], definitions, errors)
	for id in defs["pack"]:
		_check_pack("packs/%s.json" % id, defs["pack"][id], defs["card"], errors)
		FcDynastyContentRules.check_pack("packs/%s.json" % id, defs["pack"][id], defs["card"], errors)
	for id in defs["challenge"]:
		FcDynastyContentRules.check_challenge("challenges/%s.json" % id, defs["challenge"][id], defs["card"], defs["pack"], errors)
	for id in defs["seasonal"]:
		FcDynastyContentRules.check_season("seasonal/%s.json" % id, defs["seasonal"][id], defs["card"], defs["pack"], defs["challenge"], errors)
	for id in defs["set"]:
		FcDynastyContentRules.check_set("sets/%s.json" % id, defs["set"][id], defs["card"], defs["pack"], errors)
	FcDynastyContentRules.check_set_membership(defs["set"], defs["pack"], errors)
	for id in defs["support"]:
		FcDynastyContentRules.check_support("support/%s.json" % id, defs["support"][id], defs["card"], defs["pack"], errors)
	_check_lineup_coverage(defs, errors)
	return {"problems": errors, "defs": defs}


## A release with enough different players for a team (13 or more) must also be able to field a legal starting lineup. Smaller
## releases stay publishable (a release may legitimately carry little or no Dynasty content), and the game catalog still refuses to
## treat them as playable. Uses the same rule as the game (FcDynastyContentRules.lineup_problem).
static func _check_lineup_coverage(defs: Dictionary, errors: Array[String]) -> void:
	var players: Array = []
	var seen := {}
	for id in defs["card"]:
		var pid := str(defs["card"][id].get("player_id", ""))
		if pid == "" or seen.has(pid) or not defs["player"].has(pid):
			continue
		seen[pid] = true
		var p: Dictionary = defs["player"][pid]
		players.append({"player_id": pid, "position": str(p.get("position", "")), "secondary": str(p.get("secondary_position", ""))})
	if players.size() >= FcDynastyContentRules.MIN_PLAYABLE_PLAYERS:
		var problem := FcDynastyContentRules.lineup_problem(players)
		if problem != "":
			errors.append("release: " + problem)


## The card identity rules between a release and the one before it (empty = fine):
## a card_id keeps its player; changing a card needs a higher revision; the same
## revision must mean the same definition.
static func revision_problems(new_cards: Dictionary, previous_cards: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for id in previous_cards:
		if not new_cards.has(id):
			continue
		var old: Dictionary = previous_cards[id]
		var new: Dictionary = new_cards[id]
		var old_rev := _int_or(old.get("revision"), 1)
		var new_rev := _int_or(new.get("revision"), 1)
		if str(old.get("player_id", "")) != str(new.get("player_id", "")):
			errors.append("card '%s' changed its player; a card keeps its player forever (make a new card_id)" % id)
		if new_rev < old_rev:
			errors.append("card '%s' went back from revision %d to %d" % [id, old_rev, new_rev])
		elif new_rev == old_rev and FcSafeFile.canonical_text(_normalized(old)) != FcSafeFile.canonical_text(_normalized(new)):
			errors.append("card '%s' changed without a higher revision (still %d)" % [id, new_rev])
	return errors


static func _check_common(path: String, data: Dictionary, errors: Array[String]) -> void:
	if _has_fraction(data):
		errors.append("%s: contains a decimal number; use whole numbers only" % path)
	var feats = data.get("requires_features", [])
	if not (feats is Array):
		errors.append("%s: requires_features must be a list" % path)
	else:
		for f in feats:
			if not FcContentFeatures.is_supported(str(f)):
				errors.append("%s: needs the unsupported feature '%s'" % [path, str(f)])
	for key in ["name", "display_name", "title"]:
		if data.has(key) and (str(data[key]).strip_edges().is_empty() or str(data[key]).length() > MAX_TEXT):
			errors.append("%s: %s must be 1-%d characters" % [path, key, MAX_TEXT])


static func _check_player(path: String, data: Dictionary, definitions: FcDefinitionSet, errors: Array[String]) -> void:
	if str(data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s: display_name is required" % path)
	if not POSITIONS.has(str(data.get("position", ""))):
		errors.append("%s: position must be one of %s" % [path, ", ".join(POSITIONS)])
	var attrs = data.get("attributes", null)
	if not (attrs is Dictionary) or attrs.is_empty():
		errors.append("%s: attributes are required" % path)
		return
	for key in attrs:
		if definitions != null and not definitions.attributes.has_key(str(key)):
			errors.append("%s: unknown attribute '%s'" % [path, str(key)])
		var v := _int_or(attrs[key], -1)
		if v < 0 or v > 100:
			errors.append("%s: attribute '%s' must be a whole number from 0 to 100" % [path, str(key)])


static func _check_card(path: String, data: Dictionary, players: Dictionary, path_set: Dictionary,
		errors: Array[String]) -> void:
	if str(data.get("title", "")).strip_edges().is_empty():
		errors.append("%s: title is required" % path)
	if not players.has(str(data.get("player_id", ""))):
		errors.append("%s: player_id '%s' is not a player in this release" % [path, str(data.get("player_id", ""))])
	if not RARITIES.has(str(data.get("rarity", ""))):
		errors.append("%s: rarity must be one of %s" % [path, ", ".join(RARITIES)])
	if _int_or(data.get("revision"), 0) < 1:
		errors.append("%s: revision must be a whole number of at least 1" % path)
	if data.has("art"):
		var art := str(data["art"])
		if not FcSafeFile.is_safe_relative_path(art) or FcContentManifest.kind_for_path(art) != "art":
			errors.append("%s: art '%s' is not a safe path inside the art folder" % [path, art])
		elif not path_set.has(art):
			errors.append("%s: art file '%s' is not part of this content" % [path, art])


static func _check_pack(path: String, data: Dictionary, cards: Dictionary, errors: Array[String]) -> void:
	if str(data.get("name", "")).strip_edges().is_empty():
		errors.append("%s: name is required" % path)
	var ids = data.get("card_ids", null)
	if not (ids is Array) or ids.is_empty():
		errors.append("%s: card_ids must be a non-empty list" % path)
		return
	for cid in ids:
		if not cards.has(str(cid)):
			errors.append("%s: card '%s' is not a card in this release" % [path, str(cid)])


## True if any number anywhere inside has a fractional part.
static func _has_fraction(value: Variant) -> bool:
	if value is float:
		return not is_equal_approx(value, floorf(value))
	if value is Dictionary:
		for k in value:
			if _has_fraction(value[k]):
				return true
	elif value is Array:
		for v in value:
			if _has_fraction(v):
				return true
	return false


static func _int_or(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	return fallback


## Whole-number floats become ints so a parsed file compares equal to a freshly written one.
static func _normalized(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	if value is Dictionary:
		var d := {}
		for k in value:
			d[k] = _normalized(value[k])
		return d
	if value is Array:
		var a := []
		for v in value:
			a.append(_normalized(v))
		return a
	return value
