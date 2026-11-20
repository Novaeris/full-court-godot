class_name FcContentStore
extends RefCounted
## Where content releases live. This is only the seam: the local folder implementation
## (FcLocalContentStore) is the one that exists. A remote store could later implement the
## same few methods without the publisher or loader changing.
##
## Rules every store must keep: a release id is written once and never changed;
## a release is verified before it can become active; changing the active release
## only moves a pointer.


func root_dir() -> String:
	return ""


## All release ids present, sorted.
func list_release_ids() -> Array[String]:
	return []


func has_release(_release_id: String) -> bool:
	return false


## Folder holding the release's files (read-only to everyone but the store).
func release_dir(_release_id: String) -> String:
	return ""


## The release's manifest, or null when missing or unreadable.
func read_manifest(_release_id: String) -> FcContentManifest:
	return null


## A fresh empty working folder for building a release. Never read by the game.
func new_staging_dir(_release_id: String) -> String:
	return ""


## Verifies the staged release and adds it as an immutable release. Refuses an existing id.
func commit_release(_staging_dir: String, _release_id: String) -> FcContentResult:
	return _unsupported()


## The id the pointer names ("" when none). `value` carries the id.
func read_active() -> FcContentResult:
	return _unsupported()


## Makes an existing, verified release the active one.
func set_active(_release_id: String) -> FcContentResult:
	return _unsupported()


func _unsupported() -> FcContentResult:
	return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "this content store cannot do that")
