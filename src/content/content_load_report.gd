class_name FcContentLoadReport
extends RefCounted
## What the loader did, in a form the screen and the log can both show.
##
## WHY: if the newest release is broken the game quietly uses an older one. That is safe, but
## it must never be silent: the owner would otherwise test against the wrong players and cards.

## The release the pointer named ("" when nothing has been published).
var requested_release_id: String = ""
## The release actually loaded ("" when only the bundled starter, or nothing, loaded).
var loaded_release_id: String = ""
var used_starter: bool = false
## One entry per release that was tried and refused: {"release_id", "reason", "problems"}.
var rejected: Array[Dictionary] = []
var catalog: FcContentCatalog = null


## True when the game is NOT running the release it was asked to run.
func is_degraded() -> bool:
	if requested_release_id.is_empty():
		return false
	return loaded_release_id != requested_release_id


func has_content() -> bool:
	return catalog != null


## One plain-language line for screens and logs.
func summary() -> String:
	if catalog == null:
		return "No content could be loaded (not even the bundled starter content)."
	var base := "Content release %s (version %d)" % [catalog.release_id, catalog.content_version]
	if used_starter:
		base = "Bundled starter content"
	if is_degraded():
		var lead: String = "WARNING: the active release %s was refused" % requested_release_id
		var why := ""
		if not rejected.is_empty():
			why = " (%s)" % str(rejected[0]["reason"])
		return "%s%s; using %s instead." % [lead, why, base]
	if used_starter and requested_release_id.is_empty():
		return "%s: no content release has been published yet." % base
	return base + "."
