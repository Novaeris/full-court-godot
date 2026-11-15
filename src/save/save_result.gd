class_name FcSaveResult
extends RefCounted
## Outcome of a save-system operation. Check is_ok() first; `message` explains
## failures in plain language (suitable for showing to the player).

enum Code {
	OK,
	INVALID_SLOT,
	NOT_FOUND,
	CORRUPT,
	UNSUPPORTED_VERSION,
	MIGRATION_FAILED,
	WRITE_FAILED,
}

var code: int = Code.OK
var message: String = ""
## "" normally; "temp" or "backup" if the main file was unusable and an older
## or interrupted copy was loaded instead. The UI should tell the player.
var recovered_from: String = ""
## Non-fatal problems (e.g. data integrity warnings after loading).
var warnings: Array[String] = []
## Set by a successful load.
var state: FcGameState = null
## Set by a successful save or load.
var metadata: FcSaveMetadata = null


func is_ok() -> bool:
	return code == Code.OK


static func failure(failure_code: int, text: String) -> FcSaveResult:
	var r := FcSaveResult.new()
	r.code = failure_code
	r.message = text
	return r
