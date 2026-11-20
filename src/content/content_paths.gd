class_name FcContentPaths
extends RefCounted
## Where the shared content folder is, for BOTH the game and Creator Studio, so the two
## always agree on the default and on what counts as a usable folder.


## The folder used when nothing has been chosen: Documents/FullCourtContent.
static func default_root() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return docs.path_join("FullCourtContent") if not docs.is_empty() else "user://content"


## Only an absolute folder (or user://) with no ".." parts is accepted.
static func is_valid_root(path: String) -> bool:
	if path.strip_edges().is_empty() or path.contains("\\..") or path.contains("/..") or path.begins_with(".."):
		return false
	return path.begins_with("user://") or path.is_absolute_path()


## The chosen folder if it is valid, otherwise the default. Never fails.
static func effective_root(chosen: String) -> String:
	return chosen if is_valid_root(chosen) else default_root()
