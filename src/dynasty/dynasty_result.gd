class_name FcDynastyResult
extends RefCounted
## What a Dynasty domain operation returns: success or a plain-language failure, never an exception.
## `code` is a stable short word tests and screens can branch on; `message` is for the player.

var ok: bool = true
var code: String = ""
var message: String = ""
## Operation-specific output (e.g. the cards a pack awarded).
var data: Dictionary = {}


static func success(payload: Dictionary = {}) -> FcDynastyResult:
	var r := FcDynastyResult.new()
	r.data = payload
	return r


static func failure(failure_code: String, text: String) -> FcDynastyResult:
	var r := FcDynastyResult.new()
	r.ok = false
	r.code = failure_code
	r.message = text
	return r
