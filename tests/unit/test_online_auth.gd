extends FcTestCase
## Sign-in foundations (accounts milestone, D-066): the online config and its service-role-key guard, the Supabase Auth request
## builders, reading a session or an error out of an answer, and session expiry. All pure: nothing here touches a network.

const NOW := 1700000000


## A fake JWT whose payload carries the given role (header and signature are not read).
func _jwt(role: String) -> String:
	var payload := Marshalls.raw_to_base64(JSON.stringify({"role": role, "iss": "supabase"}).to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "eyJhbGciOiJIUzI1NiJ9.%s.sig" % payload


func _config() -> FcOnlineConfig:
	return FcOnlineConfig.make("https://example-project.supabase.co/", _jwt("anon"))


func test_a_good_config_is_accepted_and_a_service_role_key_is_refused() -> void:
	var c := _config()
	assert_eq(c.url, "https://example-project.supabase.co", "the trailing slash is dropped")
	assert_eq(c.validate(), [])
	assert_eq(FcOnlineConfig.role_of(_jwt("anon")), "anon")
	var dangerous := FcOnlineConfig.make("https://example-project.supabase.co", _jwt("service_role"))
	var problems := dangerous.validate()
	assert_eq(problems.size(), 1)
	assert_true("service-role" in problems[0], "the dangerous key is named and refused")
	assert_true(not FcOnlineConfig.make("http://plain.example", _jwt("anon")).validate().is_empty(), "https is required")
	assert_true(not FcOnlineConfig.make("https://example-project.supabase.co", "").validate().is_empty(), "a key is required")
	assert_eq(FcOnlineConfig.role_of("not-a-jwt"), "", "garbage is not a role")
	assert_eq(FcOnlineConfig.make("https://example-project.supabase.co", "sb_publishable_abc123").validate(), [], "the new public key format is accepted")
	var new_secret := FcOnlineConfig.make("https://example-project.supabase.co", "sb_secret_abc123").validate()
	assert_eq(new_secret.size(), 1, "the new secret key format is refused")
	assert_true(FcOnlineConfig.is_secret_key("sb_secret_x") and not FcOnlineConfig.is_secret_key("sb_publishable_x"))


func test_the_config_file_is_optional() -> void:
	assert_eq(FcOnlineConfig.load_file("user://definitely_missing_online_config.json"), null, "no file: the game stays offline")
	var path := "user://test_online_config.json"
	FcSafeFile.write_text(path, JSON.stringify({"url": "https://p.supabase.co", "anon_key": _jwt("anon")}))
	var c := FcOnlineConfig.load_file(path)
	assert_true(c != null and c.validate().is_empty())
	FcSafeFile.write_text(path, "{ not json")
	assert_eq(FcOnlineConfig.load_file(path), null, "an unreadable file is treated as absent")
	DirAccess.remove_absolute(path)


func test_requests_carry_the_public_key_and_never_a_session_by_default() -> void:
	var c := _config()
	var r := FcSupabaseAuth.sign_in(c, " maya@example.com ", "correct horse")
	assert_eq(r["method"], "POST")
	assert_eq(r["url"], "https://example-project.supabase.co/auth/v1/token?grant_type=password")
	assert_eq(r["headers"]["apikey"], c.anon_key)
	assert_true(not r["headers"].has("Authorization"), "signing in sends no token")
	assert_eq(r["body"], {"email": "maya@example.com", "password": "correct horse"}, "the e-mail is trimmed")
	assert_eq(FcSupabaseAuth.sign_up(c, "a@b.co", "longenough")["url"], "https://example-project.supabase.co/auth/v1/signup")
	assert_eq(FcSupabaseAuth.refresh(c, "rt")["body"], {"refresh_token": "rt"})
	assert_eq(FcSupabaseAuth.send_magic_link(c, "a@b.co")["body"], {"email": "a@b.co", "create_user": true})


func test_requests_for_a_signed_in_person_carry_their_token() -> void:
	var c := _config()
	var s := FcOnlineSession.from_dict({"user_id": "u1", "access_token": "tok", "expires_at": NOW + 3600})
	assert_eq(FcSupabaseAuth.sign_out(c, s)["headers"]["Authorization"], "Bearer tok")
	var q := FcSupabaseAuth.authed(c, s, "GET", "/rest/v1/profiles?select=*")
	assert_eq(q["method"], "GET")
	assert_eq(q["headers"]["Authorization"], "Bearer tok")
	assert_eq(q["headers"]["apikey"], c.anon_key, "the public key is still sent")


func test_credentials_are_checked_before_sending() -> void:
	assert_eq(FcSupabaseAuth.credential_problems("maya@example.com", "longenough"), [])
	assert_eq(FcSupabaseAuth.credential_problems("mayaexample.com", "longenough").size(), 1, "no @")
	assert_eq(FcSupabaseAuth.credential_problems("maya@example", "longenough").size(), 1, "no dot after the @")
	assert_eq(FcSupabaseAuth.credential_problems("ma ya@example.com", "longenough").size(), 1, "a space")
	assert_eq(FcSupabaseAuth.credential_problems("maya@example.com", "short").size(), 1, "short password")
	assert_eq(FcSupabaseAuth.credential_problems("", "").size(), 2, "both reported")


func test_a_sign_in_answer_becomes_a_session_with_a_fixed_expiry() -> void:
	var answer := {"status": 200, "error": "", "body": {"access_token": "at", "refresh_token": "rt", "expires_in": 3600,
		"user": {"id": "11111111-aaaa", "email": "maya@example.com"}}}
	var s := FcSupabaseAuth.read_session(answer, NOW)
	assert_true(s != null and s.is_signed_in())
	assert_eq([s.user_id, s.email, s.access_token, s.refresh_token, s.expires_at], ["11111111-aaaa", "maya@example.com", "at", "rt", NOW + 3600])
	assert_eq(FcSupabaseAuth.read_error(answer), "")
	assert_eq(FcOnlineSession.from_dict(s.to_dict()).to_dict(), s.to_dict(), "a session saves and loads unchanged")


func test_answers_without_a_session_give_none() -> void:
	assert_eq(FcSupabaseAuth.read_session({"status": 400, "body": {"error_code": "invalid_credentials"}}, NOW), null)
	assert_eq(FcSupabaseAuth.read_session({"status": 200, "body": {"user": {"id": "u"}}}, NOW), null, "sign-up awaiting e-mail confirmation has no session yet")
	assert_eq(FcSupabaseAuth.read_session({"status": 200, "body": {"access_token": "at"}}, NOW), null, "no user id")
	assert_eq(FcSupabaseAuth.read_session({"status": 0, "error": "no answer", "body": {}}, NOW), null)


func test_errors_are_plain_language() -> void:
	assert_eq(FcSupabaseAuth.read_error({"status": 400, "body": {"error_code": "invalid_credentials"}}), "That e-mail and password do not match.")
	assert_eq(FcSupabaseAuth.read_error({"status": 422, "body": {"error_code": "user_already_exists"}}), "There is already an account with that e-mail.")
	assert_eq(FcSupabaseAuth.read_error({"status": 422, "body": {"error_code": "weak_password"}}), "That password is too weak.")
	assert_eq(FcSupabaseAuth.read_error({"status": 429, "body": {}}), "Too many tries: wait a minute and try again.")
	assert_eq(FcSupabaseAuth.read_error({"status": 503, "body": {}}), "The online service is having trouble. Try again later.")
	assert_true("Could not reach" in FcSupabaseAuth.read_error({"status": 0, "error": "no answer (code 2)", "body": {}}), "offline")
	assert_eq(FcSupabaseAuth.read_error({"status": 400, "body": {"msg": "Something odd"}}), "Something odd", "an unknown error keeps the server's words")
	assert_eq(FcSupabaseAuth.read_error({"status": 418, "body": {}}), "The online service refused the request (418).")


func test_a_token_is_renewed_before_it_expires() -> void:
	var s := FcOnlineSession.from_dict({"user_id": "u", "access_token": "t", "expires_at": NOW + 3600})
	assert_true(not s.needs_refresh(NOW), "an hour left")
	assert_true(not s.needs_refresh(NOW + 3500), "100 seconds left is still fine")
	assert_true(s.needs_refresh(NOW + 3541), "inside the 60 second margin")
	assert_true(s.needs_refresh(NOW + 4000), "already expired")
	assert_true(not FcOnlineSession.new().is_signed_in())
