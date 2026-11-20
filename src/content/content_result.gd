class_name FcContentResult
extends RefCounted
## Outcome of a content operation (publish, load, rollback...). Check is_ok() first.
## `message` is plain language suitable for showing to the owner or player.

enum Code {
	OK,
	NOT_FOUND,
	CORRUPT,
	INVALID,
	INCOMPATIBLE,
	MISSING_ASSET,
	UNSAFE_PATH,
	NOT_APPROVED,
	ALREADY_EXISTS,
	WRITE_FAILED,
}

var code: int = Code.OK
var message: String = ""
## Every individual problem found (validation reports list them all, not just the first).
var problems: Array[String] = []
## Whatever the operation produced (a manifest, a release id...).
var value: Variant = null


func is_ok() -> bool:
	return code == Code.OK


static func failure(failure_code: int, text: String, found_problems: Array[String] = []) -> FcContentResult:
	var r := FcContentResult.new()
	r.code = failure_code
	r.message = text
	r.problems = found_problems
	return r


static func success(result_value: Variant = null) -> FcContentResult:
	var r := FcContentResult.new()
	r.value = result_value
	return r
