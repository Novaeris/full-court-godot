class_name FcScriptErrorLogger
extends Logger
## Catches the runtime SCRIPT errors Godot reports while a test runs (a method called on null, a bad cast, an invalid index...). Godot
## aborts the function that raised one, so a test that hits it silently skips every assertion after that point; the runners use this to
## count such a test as FAILED instead of passed. It is registered with OS.add_logger (Godot 4.5 and later).
## Only ERROR_TYPE_SCRIPT counts: push_error calls and engine messages (for example "popup not inside the tree") are common in the
## game's own code paths and are NOT failures; they are tallied separately in `other_errors` so the runner can report the number.

var script_errors: Array[String] = []
var other_errors: int = 0
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	if error_type == ErrorType.ERROR_TYPE_SCRIPT:
		script_errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
	elif error_type == ErrorType.ERROR_TYPE_ERROR:
		other_errors += 1
	_mutex.unlock()


## Returns the script errors recorded since the last call and clears them.
func take() -> Array[String]:
	_mutex.lock()
	var out := script_errors.duplicate()
	script_errors.clear()
	_mutex.unlock()
	return out


## Installs a logger and returns it, or null on an engine without the Logger class (the runners then say that script errors cannot be detected).
static func install() -> FcScriptErrorLogger:
	if not ClassDB.class_exists("Logger"):
		return null
	var logger := FcScriptErrorLogger.new()
	OS.add_logger(logger)
	return logger
