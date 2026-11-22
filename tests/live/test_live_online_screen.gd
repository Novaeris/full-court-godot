extends FcLiveTestCase
## The Online screen in a real scene: with no config it only explains setup, with a config it offers sign-in and a failed request (an
## address nothing listens on) comes back as a plain message, and the screen fits a phone-width window. The menu has the Online button.

const PREFS := "user://test_preferences_live_online.cfg"
const SESSION := "user://test_online_session_live.json"

var app: FcApp


func before_each() -> void:
	super.before_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(SESSION)
	FcOnlineHttp.timeout_seconds = 1.0   # a closed address would otherwise take 15 seconds to give up
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_live_online")
	# Isolate from the developer's real files: FcApp would otherwise read user://online_config.json and user://online_session.json,
	# so on a machine that is set up for online (or signed in) the "no config" test failed and a test could touch the real session.
	app.online = FcOnlineController.new(null, SESSION)
	host.add_child(app)
	app.setup()


func after_each() -> void:
	FcOnlineHttp.timeout_seconds = 15.0
	super.after_each()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(SESSION)
	DirAccess.remove_absolute("user://test_ui_state_live_online.cfg")
	FcSafeFile.remove_tree("user://test_saves_live_online")


func _jwt_anon() -> String:
	var payload := Marshalls.raw_to_base64(JSON.stringify({"role": "anon"}).to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "eyJhbGciOiJIUzI1NiJ9.%s.sig" % payload


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _all_text(root: Node) -> String:
	var out := ""
	for n in root.find_children("*", "Label", true, false):
		out += (n as Label).text + "\n"
	return out


func test_the_menu_has_an_online_button_that_opens_the_screen() -> void:
	app.show_main_menu()
	await frames(2)
	var button := _find(app, "OnlineButton") as Button
	assert_true(button != null, "an Online button in the footer")
	button.pressed.emit()
	await frames(2)
	assert_true("Online is not set up" in _all_text(app) or "set up" in _all_text(app), "without a config the screen explains setup")
	assert_true(_find(app, "SignIn") == null, "no sign-in form without a config")


func test_a_configured_screen_shows_the_form_and_an_unreachable_service_gives_a_plain_message() -> void:
	app.online = FcOnlineController.new(FcOnlineConfig.make("https://127.0.0.1:9", _jwt_anon()), SESSION)
	app.show_online()
	await frames(2)
	var email := _find(app, "Email") as LineEdit
	var password := _find(app, "Password") as LineEdit
	assert_true(email != null and password != null and password.secret, "the password field hides what is typed")
	email.text = "maya@example.com"
	password.text = "longenough"
	(_find(app, "SignIn") as Button).pressed.emit()
	# The busy state is set synchronously when the request starts (online_screen.gd _run) and cleared when the answer arrives. Check it
	# right away: on a fast machine or CI a refused connection can answer within two frames, so waiting first made this test timing-sensitive
	# (it failed on GitHub Actions run 45046140970 while passing locally).
	assert_true((_find(app, "Busy") as Control).visible and (_find(app, "SignIn") as Button).disabled, "a working line and disabled buttons while waiting")
	await frames(2)
	for i in 100:   # up to ~5 real seconds for the timeout to come back
		await seconds(0.05)
		if "Could not reach" in _all_text(app):
			break
	assert_true("Could not reach" in _all_text(app), "a plain message, not a crash")
	assert_true(not app.online.is_signed_in())


func test_bad_input_is_explained_without_sending() -> void:
	app.online = FcOnlineController.new(FcOnlineConfig.make("https://127.0.0.1:9", _jwt_anon()), SESSION)
	app.show_online()
	await frames(2)
	(_find(app, "SignIn") as Button).pressed.emit()
	await frames(2)
	assert_true("valid e-mail" in _all_text(app))


func test_signed_in_shows_the_address_and_sign_out_works() -> void:
	app.online = FcOnlineController.new(FcOnlineConfig.make("https://127.0.0.1:9", _jwt_anon()), SESSION)
	app.online.finish("sign_in", {"status": 200, "body": {"access_token": "at", "refresh_token": "rt", "expires_in": 3600, "user": {"id": "u1", "email": "maya@example.com"}}})
	app.show_online()
	await frames(2)
	assert_true("maya@example.com" in _all_text(app))
	(_find(app, "SignOut") as Button).pressed.emit()
	for i in 100:
		await seconds(0.05)
		if not app.online.is_signed_in():
			break
	await frames(2)
	assert_true(not app.online.is_signed_in(), "signed out even though the service is unreachable")
	assert_true(_find(app, "SignIn") != null, "the sign-in form is back")


func test_the_screen_fits_a_phone_width_window() -> void:
	app.online = FcOnlineController.new(FcOnlineConfig.make("https://127.0.0.1:9", _jwt_anon()), SESSION)
	app.show_online()
	host.size = Vector2(360, 640)
	app.size = Vector2(360, 640)
	await frames(3)
	for scroll in app.find_children("*", "ScrollContainer", true, false):
		var sc := scroll as ScrollContainer
		var content := sc.get_child(0) as Control
		assert_true(content.get_combined_minimum_size().x <= sc.size.x + 1.0, "no sideways scrolling at 360 px (%s)" % str(content.get_combined_minimum_size().x))
