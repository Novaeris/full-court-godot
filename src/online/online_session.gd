class_name FcOnlineSession
extends RefCounted
## A signed-in person as Supabase describes them: who they are (`user_id`, `email`) and the short-lived tokens that prove it. The access
## token expires (usually after an hour) and is renewed with the refresh token. Only whole seconds are stored (CLAUDE.md rule 6).
## Tokens are secrets: keep them out of logs, and store them only in `user://`, never in a save the player might share.

var user_id: String = ""
var email: String = ""
var access_token: String = ""
var refresh_token: String = ""
## Unix seconds at which the access token stops working.
var expires_at: int = 0


func is_signed_in() -> bool:
	return user_id != "" and access_token != ""


## True when the token is expired or will be within `margin` seconds, so callers renew it BEFORE a request fails.
func needs_refresh(now: int, margin: int = 60) -> bool:
	return now + margin >= expires_at


func to_dict() -> Dictionary:
	return {"user_id": user_id, "email": email, "access_token": access_token, "refresh_token": refresh_token, "expires_at": expires_at}


static func from_dict(d: Dictionary) -> FcOnlineSession:
	var s := FcOnlineSession.new()
	s.user_id = str(d.get("user_id", ""))
	s.email = str(d.get("email", ""))
	s.access_token = str(d.get("access_token", ""))
	s.refresh_token = str(d.get("refresh_token", ""))
	s.expires_at = int(d.get("expires_at", 0))
	return s
