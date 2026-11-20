class_name FcDraftWorkspace
extends RefCounted
## The private place where Creator Studio keeps content being worked on.
##
## Layout: <drafts_dir>/<draft_id>/draft.json  and  <drafts_dir>/<draft_id>/content/ (same
## folders as a release: players/, cards/, packs/..., art/). The game never reads drafts.
##
## IMPORTANT: this class only creates, edits and checks drafts. It has no way to publish:
## it never touches a content store, the publisher or approvals, and a test enforces that.

var drafts_dir: String
var definitions: FcDefinitionSet = null


func _init(directory: String, attribute_definitions: FcDefinitionSet = null) -> void:
	drafts_dir = directory
	definitions = attribute_definitions


static func is_valid_draft_id(id: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]{1,40}$")
	return re.search(id) != null


## Creates an empty draft and returns its id ("" if the name gives no usable id or it cannot be written).
func create_draft(display_name: String, created_at: int = 0) -> String:
	var base := display_name.strip_edges().to_lower()
	var slug := ""
	for c in base:
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	slug = slug.substr(0, 32).strip_edges()
	if slug.replace("_", "").is_empty():
		return ""
	var id := slug
	var n := 2
	while DirAccess.dir_exists_absolute(drafts_dir.path_join(id)):
		id = "%s_%d" % [slug, n]
		n += 1
	var meta := {"draft_id": id, "name": display_name.strip_edges(), "created_at": created_at}
	if not FcSafeFile.write_text(drafts_dir.path_join(id).path_join("draft.json"), JSON.stringify(meta, "\t", true)):
		return ""
	FcSafeFile.make_dir(content_dir(id))
	return id


## Draft summaries: [{"draft_id", "name", "created_at"}], sorted by id.
func list_drafts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(drafts_dir)
	if dir == null:
		return out
	var names := Array(dir.get_directories())
	names.sort()
	for d in names:
		var meta = FcSafeFile.read_json_object(drafts_dir.path_join(d).path_join("draft.json"))
		if meta != null and is_valid_draft_id(d):
			out.append({"draft_id": d, "name": str(meta.get("name", d)),
				"created_at": FcContentManifest._as_int(meta.get("created_at"), 0)})
	return out


func has_draft(draft_id: String) -> bool:
	return is_valid_draft_id(draft_id) and DirAccess.dir_exists_absolute(drafts_dir.path_join(draft_id))


func content_dir(draft_id: String) -> String:
	return drafts_dir.path_join(draft_id).path_join("content")


## Saves one definition file (players/x.json ...). Only allowed locations are accepted.
func save_definition(draft_id: String, rel_path: String, data: Dictionary) -> FcContentResult:
	var kind := FcContentManifest.kind_for_path(rel_path)
	if not has_draft(draft_id):
		return FcContentResult.failure(FcContentResult.Code.NOT_FOUND, "no such draft")
	if kind.is_empty() or kind == "art":
		return FcContentResult.failure(FcContentResult.Code.UNSAFE_PATH, "'%s' is not a definition location" % rel_path)
	if not FcSafeFile.write_text(content_dir(draft_id).path_join(rel_path), JSON.stringify(data, "\t", true)):
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not save")
	return FcContentResult.success(rel_path)


## Adds artwork (raw image bytes) under art/.
func save_art(draft_id: String, rel_path: String, bytes: PackedByteArray) -> FcContentResult:
	if not has_draft(draft_id):
		return FcContentResult.failure(FcContentResult.Code.NOT_FOUND, "no such draft")
	if FcContentManifest.kind_for_path(rel_path) != "art":
		return FcContentResult.failure(FcContentResult.Code.UNSAFE_PATH, "'%s' is not an art location" % rel_path)
	if not FcSafeFile.write_bytes(content_dir(draft_id).path_join(rel_path), bytes):
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not save")
	return FcContentResult.success(rel_path)


func delete_file(draft_id: String, rel_path: String) -> bool:
	if not has_draft(draft_id) or FcContentManifest.kind_for_path(rel_path).is_empty():
		return false
	return DirAccess.remove_absolute(content_dir(draft_id).path_join(rel_path)) == OK


func delete_draft(draft_id: String) -> void:
	if has_draft(draft_id):
		FcSafeFile.remove_tree(drafts_dir.path_join(draft_id))


## Checks the draft. Success means "ready to ask for approval"; nothing is published.
func validate(draft_id: String) -> FcContentResult:
	if not has_draft(draft_id):
		return FcContentResult.failure(FcContentResult.Code.NOT_FOUND, "no such draft")
	var problems := FcContentValidator.draft_problems(content_dir(draft_id), definitions)
	if problems.is_empty():
		return FcContentResult.success(FcSafeFile.hash_tree(content_dir(draft_id)))
	return FcContentResult.failure(FcContentResult.Code.INVALID, "the draft has problems", problems)
