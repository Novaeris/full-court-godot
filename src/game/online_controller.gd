class_name FcOnlineController
extends RefCounted
## The one API the sign-in screen uses (screens never call FcSupabaseAuth directly). It holds the online config and the signed-in session
## and is split so nothing here waits on the network: `begin(...)` returns the request to send (or a plain-language problem), the SCREEN
## sends it with FcOnlineHttp and awaits the answer, then `finish(...)` reads the answer, keeps or clears the session and says what to
## show. That keeps every rule testable without a server. Online is optional: with no config file the game simply plays offline.
##
## The session (tokens are secrets) is kept in `user://online_session.json`, never inside a save the player might share.

const SESSION_FILE := "user://online_session.json"

var config: FcOnlineConfig
var session: FcOnlineSession = FcOnlineSession.new()
var _session_path: String
## Returns the current unix time in whole seconds. Tests replace it.
var now: Callable = func() -> int: return int(Time.get_unix_time_from_system())


func _init(online_config: FcOnlineConfig = null, session_path: String = SESSION_FILE) -> void:
	config = online_config
	_session_path = session_path
	_load_session()


## Whether a usable config exists (so online features can be offered).
func is_configured() -> bool:
	return config != null and config.validate().is_empty()


## Why online is not available, in plain language ("" when it is).
func setup_problem() -> String:
	if config == null:
		return "Online play is not set up on this computer yet. Put your project's address and public key in %s." % ProjectSettings.globalize_path(FcOnlineConfig.FILE)
	var problems := config.validate()
	return "" if problems.is_empty() else "The online settings are not usable: %s." % problems[0]


func is_signed_in() -> bool:
	return session.is_signed_in()


func email() -> String:
	return session.email


## Whether the token should be renewed before the next online request.
func needs_refresh() -> bool:
	return is_signed_in() and session.refresh_token != "" and session.needs_refresh(int(now.call()))


## Step one of an action: `kind` is sign_in, sign_up, magic_link, refresh or sign_out. Returns {"ok", "message", "request"}; when ok is
## false there is nothing to send and `message` says why.
func begin(kind: String, user_email: String = "", password: String = "") -> Dictionary:
	if not is_configured():
		return {"ok": false, "message": setup_problem(), "request": {}}
	match kind:
		"sign_in", "sign_up":
			var problems := FcSupabaseAuth.credential_problems(user_email, password)
			if not problems.is_empty():
				return {"ok": false, "message": _sentence(problems[0]), "request": {}}
			var req := FcSupabaseAuth.sign_in(config, user_email, password) if kind == "sign_in" else FcSupabaseAuth.sign_up(config, user_email, password)
			return {"ok": true, "message": "", "request": req}
		"magic_link":
			var only_email := FcSupabaseAuth.credential_problems(user_email, "x".repeat(FcSupabaseAuth.MIN_PASSWORD))
			if not only_email.is_empty():
				return {"ok": false, "message": _sentence(only_email[0]), "request": {}}
			return {"ok": true, "message": "", "request": FcSupabaseAuth.send_magic_link(config, user_email)}
		"refresh":
			if session.refresh_token == "":
				return {"ok": false, "message": "You are not signed in.", "request": {}}
			return {"ok": true, "message": "", "request": FcSupabaseAuth.refresh(config, session.refresh_token)}
		"sign_out":
			return {"ok": true, "message": "", "request": FcSupabaseAuth.sign_out(config, session)}
	return {"ok": false, "message": "Unknown action.", "request": {}}


## Step two: reads the answer to the request `begin` produced. Returns {"ok", "message"} for the screen to show.
func finish(kind: String, response: Dictionary) -> Dictionary:
	if kind == "sign_out":
		sign_out_locally()   # always: a failed network call must never leave someone stuck signed in
		return {"ok": true, "message": "You are signed out."}
	var failure := FcSupabaseAuth.read_error(response)
	match kind:
		"sign_in", "sign_up", "refresh":
			if failure != "":
				if kind == "refresh" and int(response.get("status", 0)) in [400, 401]:
					sign_out_locally()   # the refresh token is no longer valid: sign in again
					return {"ok": false, "message": "Your sign-in expired. Please sign in again."}
				return {"ok": false, "message": failure}
			var s := FcSupabaseAuth.read_session(response, int(now.call()))
			if s == null:
				if kind == "sign_up":
					return {"ok": true, "message": "Account created. Check your e-mail to confirm your address, then sign in."}
				return {"ok": false, "message": "The online service gave an unexpected answer."}
			session = s
			_save_session()
			return {"ok": true, "message": "Signed in as %s." % s.email}
		"magic_link":
			if failure != "":
				return {"ok": false, "message": failure}
			return {"ok": true, "message": "Sent. Check your e-mail for the sign-in link."}
	return {"ok": false, "message": "Unknown action."}


## Forgets the session on this computer (does not depend on the network).
func sign_out_locally() -> void:
	session = FcOnlineSession.new()
	if FileAccess.file_exists(_session_path):
		DirAccess.remove_absolute(_session_path)


func _save_session() -> void:
	FcSafeFile.write_text(_session_path, JSON.stringify(session.to_dict()))


func _load_session() -> void:
	if not FileAccess.file_exists(_session_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(_session_path)) == OK and json.data is Dictionary:
		session = FcOnlineSession.from_dict(json.data)


## "enter a valid e-mail address" -> "Enter a valid e-mail address."
static func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) + "."
