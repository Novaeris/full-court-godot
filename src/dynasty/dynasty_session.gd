class_name FcDynastySession
extends RefCounted
## One open Dynasty profile plus the store it is saved in. `commit()` is the ONE way state changes: it runs a mutation,
## and only if the mutation succeeded AND the save was verified does the change stay. If either fails, the profile is put
## back exactly as it was, so a failed purchase can never consume currency without delivering, and a failed save can never
## leave memory ahead of the disk.

var profile: FcDynastyProfile
var store: FcDynastyStore
var slot: String = ""


func _init(open_profile: FcDynastyProfile, profile_store: FcDynastyStore, slot_name: String) -> void:
	profile = open_profile
	store = profile_store
	slot = slot_name


## `mutator` takes no arguments, changes `profile`, and returns an FcDynastyResult.
func commit(mutator: Callable) -> FcDynastyResult:
	var before := profile.to_dict()
	var result: FcDynastyResult = mutator.call()
	if result == null:
		result = FcDynastyResult.failure("internal", "The operation returned nothing.")
	if not result.ok:
		profile = FcDynastyProfile.from_dict(before)
		return result
	var saved := store.save(slot, profile)
	if not saved.ok:
		profile = FcDynastyProfile.from_dict(before)
		return FcDynastyResult.failure("save_failed", "Nothing was changed because the game could not be saved: %s" % saved.message)
	return result
