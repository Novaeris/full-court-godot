class_name FcSupabaseAuth
extends RefCounted
## Sign-in with Supabase Auth (D-066), written as PURE request builders and response readers so it can be tested without a network:
## a builder returns a plain request {method, url, headers, body}; something else (FcOnlineHttp) sends it; `read_session` / `read_error`
## turn the answer into an FcOnlineSession or a plain-language message. Supabase sends the sign-in e-mails (through Resend, set up in the
## Supabase dashboard), so the game never sees a password reset or confirmation e-mail itself.
##
## Identity (WHO this is) comes from Supabase; authority (what the game allows) stays with the game server (D-065). A request signed in
## here proves a person, it never states a balance or a result.

const MIN_PASSWORD := 8


static func sign_up(config: FcOnlineConfig, email: String, password: String) -> Dictionary:
	return _post(config, "/auth/v1/signup", {"email": email.strip_edges(), "password": password})


static func sign_in(config: FcOnlineConfig, email: String, password: String) -> Dictionary:
	return _post(config, "/auth/v1/token?grant_type=password", {"email": email.strip_edges(), "password": password})


static func refresh(config: FcOnlineConfig, refresh_token: String) -> Dictionary:
	return _post(config, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token})


## Asks Supabase to e-mail a one-time sign-in code or link (no password to remember).
static func send_magic_link(config: FcOnlineConfig, email: String) -> Dictionary:
	return _post(config, "/auth/v1/otp", {"email": email.strip_edges(), "create_user": true})


static func sign_out(config: FcOnlineConfig, session: FcOnlineSession) -> Dictionary:
	var r := _post(config, "/auth/v1/logout", {})
	r["headers"]["Authorization"] = "Bearer %s" % session.access_token
	return r


## A request for any other Supabase service, acting as the signed-in person (the server's row rules decide what they may touch).
static func authed(config: FcOnlineConfig, session: FcOnlineSession, method: String, path: String, body: Dictionary = {}) -> Dictionary:
	var r := _post(config, path, body)
	r["method"] = method
	r["headers"]["Authorization"] = "Bearer %s" % session.access_token
	return r


## Problems with an e-mail and password before anything is sent (empty = fine). The server checks again.
static func credential_problems(email: String, password: String) -> Array[String]:
	var errors: Array[String] = []
	var e := email.strip_edges()
	var at := e.find("@")
	if at < 1 or e.find(".", at) < at + 2 or e.contains(" ") or e.ends_with("."):
		errors.append("enter a valid e-mail address")
	if password.length() < MIN_PASSWORD:
		errors.append("the password needs at least %d characters" % MIN_PASSWORD)
	return errors


## The session in a sign-in / refresh answer, or null when the answer has none (sign-up with e-mail confirmation on has no session yet).
## `now` is the current unix time, used to turn "expires in N seconds" into a fixed moment.
static func read_session(response: Dictionary, now: int) -> FcOnlineSession:
	var body: Dictionary = response.get("body", {}) if response.get("body") is Dictionary else {}
	if int(response.get("status", 0)) < 200 or int(response.get("status", 0)) >= 300 or not body.has("access_token"):
		return null
	var user: Dictionary = body.get("user", {}) if body.get("user") is Dictionary else {}
	var s := FcOnlineSession.new()
	s.user_id = str(user.get("id", ""))
	s.email = str(user.get("email", ""))
	s.access_token = str(body["access_token"])
	s.refresh_token = str(body.get("refresh_token", ""))
	s.expires_at = now + int(body.get("expires_in", 3600))
	return s if s.user_id != "" else null


## A plain-language message for a failed answer ("" when the answer is a success).
static func read_error(response: Dictionary) -> String:
	var status := int(response.get("status", 0))
	if str(response.get("error", "")) != "":
		return "Could not reach the online service: %s" % str(response["error"])
	if status >= 200 and status < 300:
		return ""
	var body: Dictionary = response.get("body", {}) if response.get("body") is Dictionary else {}
	var code := str(body.get("error_code", body.get("error", "")))
	match code:
		"invalid_credentials", "invalid_grant":
			return "That e-mail and password do not match."
		"user_already_exists", "email_exists":
			return "There is already an account with that e-mail."
		"weak_password":
			return "That password is too weak."
		"over_request_rate_limit", "over_email_send_rate_limit":
			return "Too many tries: wait a minute and try again."
		"email_not_confirmed":
			return "Check your e-mail and confirm your address first."
	if status == 429:
		return "Too many tries: wait a minute and try again."
	if status >= 500:
		return "The online service is having trouble. Try again later."
	var detail := str(body.get("msg", body.get("error_description", "")))
	return detail if detail != "" else "The online service refused the request (%d)." % status


static func _post(config: FcOnlineConfig, path: String, body: Dictionary) -> Dictionary:
	return {"method": "POST", "url": config.url + path, "headers": {"apikey": config.anon_key, "Content-Type": "application/json"}, "body": body}
