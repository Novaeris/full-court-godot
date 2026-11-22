extends FcTestCase
## The sign-in controller (accounts milestone): what it refuses before sending, how it reads each kind of answer, that a session is kept
## in its own file and reloaded, that tokens are renewed in time, and that signing out always works even without a network.

const PATH := "user://test_online_session.json"
const NOW := 1700000000

var ctl: FcOnlineController
var now_value: int


func _jwt_anon() -> String:
	var payload := Marshalls.raw_to_base64(JSON.stringify({"role": "anon"}).to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "eyJhbGciOiJIUzI1NiJ9.%s.sig" % payload


func before_each() -> void:
	DirAccess.remove_absolute(PATH)
	now_value = NOW
	ctl = _make()


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func _make() -> FcOnlineController:
	var c := FcOnlineController.new(FcOnlineConfig.make("https://example-project.supabase.co", _jwt_anon()), PATH)
	c.now = func() -> int: return now_value
	return c


func _ok_answer(token: String = "at") -> Dictionary:
	return {"status": 200, "error": "", "body": {"access_token": token, "refresh_token": "rt", "expires_in": 3600, "user": {"id": "u1", "email": "maya@example.com"}}}


func test_without_a_config_nothing_is_sent_and_the_reason_is_plain() -> void:
	var off := FcOnlineController.new(null, PATH)
	assert_true(not off.is_configured())
	var r := off.begin("sign_in", "a@b.co", "longenough")
	assert_true(not bool(r["ok"]))
	assert_true("not set up" in str(r["message"]))
	var broken := FcOnlineController.new(FcOnlineConfig.make("http://insecure.example", _jwt_anon()), PATH)
	assert_true(not broken.is_configured())
	assert_true("https" in broken.setup_problem())


func test_bad_input_is_refused_before_sending() -> void:
	var r := ctl.begin("sign_in", "not-an-email", "longenough")
	assert_true(not bool(r["ok"]))
	assert_eq(r["message"], "Enter a valid e-mail address.")
	assert_eq(ctl.begin("sign_up", "a@b.co", "short")["message"], "The password needs at least 8 characters.")
	assert_eq(ctl.begin("magic_link", "bad", "")["message"], "Enter a valid e-mail address.")
	assert_true(bool(ctl.begin("magic_link", "a@b.co", "")["ok"]), "a link needs no password")
	assert_true(bool(ctl.begin("sign_in", "a@b.co", "longenough")["ok"]))
	assert_eq(ctl.begin("refresh")["message"], "You are not signed in.")
	assert_true(not bool(ctl.begin("nonsense")["ok"]))


func test_a_successful_sign_in_is_kept_and_reloaded() -> void:
	var done := ctl.finish("sign_in", _ok_answer())
	assert_true(bool(done["ok"]))
	assert_eq(done["message"], "Signed in as maya@example.com.")
	assert_true(ctl.is_signed_in())
	assert_eq(ctl.email(), "maya@example.com")
	assert_true(FileAccess.file_exists(PATH), "the session is saved")
	var later := _make()
	assert_true(later.is_signed_in(), "the next start is still signed in")
	assert_eq(later.session.expires_at, NOW + 3600)


func test_a_failed_sign_in_changes_nothing() -> void:
	var done := ctl.finish("sign_in", {"status": 400, "body": {"error_code": "invalid_credentials"}})
	assert_true(not bool(done["ok"]))
	assert_eq(done["message"], "That e-mail and password do not match.")
	assert_true(not ctl.is_signed_in())
	assert_true(not FileAccess.file_exists(PATH))
	assert_true("Could not reach" in str(ctl.finish("sign_in", {"status": 0, "error": "no answer", "body": {}})["message"]), "offline")


func test_sign_up_may_wait_for_e_mail_confirmation() -> void:
	var done := ctl.finish("sign_up", {"status": 200, "body": {"user": {"id": "u1", "email": "maya@example.com"}}})
	assert_true(bool(done["ok"]))
	assert_true("confirm" in str(done["message"]))
	assert_true(not ctl.is_signed_in(), "no session until the address is confirmed")
	assert_true(bool(ctl.finish("sign_up", _ok_answer())["ok"]) and ctl.is_signed_in(), "with confirmation off the person is signed in at once")


func test_a_sign_in_link_request_reports_success_or_the_problem() -> void:
	assert_eq(ctl.finish("magic_link", {"status": 200, "body": {}})["message"], "Sent. Check your e-mail for the sign-in link.")
	assert_true(not bool(ctl.finish("magic_link", {"status": 429, "body": {}})["ok"]))


func test_the_token_is_renewed_in_time_and_a_dead_refresh_signs_out() -> void:
	ctl.finish("sign_in", _ok_answer("old"))
	assert_true(not ctl.needs_refresh())
	now_value = NOW + 3600 - 30
	assert_true(ctl.needs_refresh(), "inside the margin")
	var req := ctl.begin("refresh")
	assert_true(bool(req["ok"]))
	assert_eq(req["request"]["body"], {"refresh_token": "rt"})
	assert_true(bool(ctl.finish("refresh", _ok_answer("new"))["ok"]))
	assert_eq(ctl.session.access_token, "new")
	assert_eq(ctl.session.expires_at, now_value + 3600)
	var dead := ctl.finish("refresh", {"status": 400, "body": {"error_code": "invalid_grant"}})
	assert_true(not bool(dead["ok"]))
	assert_eq(dead["message"], "Your sign-in expired. Please sign in again.")
	assert_true(not ctl.is_signed_in() and not FileAccess.file_exists(PATH), "signed out and the file removed")


func test_signing_out_works_even_when_the_network_does_not() -> void:
	ctl.finish("sign_in", _ok_answer())
	var req := ctl.begin("sign_out")
	assert_eq(req["request"]["headers"]["Authorization"], "Bearer at")
	var done := ctl.finish("sign_out", {"status": 0, "error": "no answer", "body": {}})
	assert_true(bool(done["ok"]))
	assert_true(not ctl.is_signed_in())
	assert_true(not FileAccess.file_exists(PATH))
	assert_true(not _make().is_signed_in(), "still signed out after a restart")


func test_a_damaged_session_file_means_signed_out() -> void:
	FcSafeFile.write_text(PATH, "{ not json")
	assert_true(not _make().is_signed_in())
