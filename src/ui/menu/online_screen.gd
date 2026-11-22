class_name FcOnlineScreen
extends RefCounted
## The Online screen: sign in, create an account, ask for an e-mailed sign-in link, or sign out. Online is OPTIONAL: when no config file
## exists the screen only explains how to set it up and the game keeps working offline. The screen never calls Supabase itself: it asks
## FcOnlineController for a request, sends it with FcOnlineHttp (the only network code) and hands the answer back to the controller.
##
## `actions`: back (Callable), host (a Node in the tree that can run the request), refresh (Callable that rebuilds this screen, called after
## an answer so the new state shows). `message` is the line shown at the top (the result of the last action).

static func build(box: VBoxContainer, ctl: FcOnlineController, actions: Dictionary, message: String = "") -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	scroll.add_child(page)
	box.add_child(scroll)

	if message != "":
		var line := FcPanel.new("", FcPanel.Variant.RAISED)
		line.add(_wrapped(message, FcUiTokens.TYPE_BODY))
		page.add_child(line)

	if not ctl.is_configured():
		var setup := FcPanel.new("Online is not set up", FcPanel.Variant.SURFACE)
		setup.add(_wrapped(ctl.setup_problem(), FcUiTokens.TYPE_BODY))
		setup.add(_wrapped("Everything else in Full Court works without it. This is only needed for online play with others.", FcUiTokens.TYPE_SMALL, true))
		page.add_child(setup)
	elif ctl.is_signed_in():
		_signed_in(page, ctl, actions)
	else:
		_signed_out(page, ctl, actions)
	page.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, actions["back"], "chevron-left"))


## While a request is out, the buttons are off and a "working" line is shown (a dead connection can take 15 seconds to give up).
static func _set_busy(page_root: Node, busy: bool) -> void:
	var status := page_root.find_child("Busy", true, false) as Control
	if status != null:
		status.visible = busy
	for b_name in ["SignIn", "SignUp", "MagicLink", "SignOut"]:
		var b := page_root.find_child(b_name, true, false) as Button
		if b != null:
			b.disabled = busy


static func _signed_in(page: VBoxContainer, ctl: FcOnlineController, actions: Dictionary) -> void:
	var panel := FcPanel.new("Signed in", FcPanel.Variant.SURFACE)
	panel.add(_wrapped("You are signed in as %s." % ctl.email(), FcUiTokens.TYPE_BODY))
	panel.add(_wrapped("Online play (leagues with friends, team games and Dynasty) is still being built. Signing in is ready for it.", FcUiTokens.TYPE_SMALL, true))
	panel.add(_busy_label())
	var out := FcButton.make("Sign out", FcButton.Variant.SECONDARY, func() -> void: await _run(ctl, actions, "sign_out", "", ""))
	out.name = "SignOut"
	panel.add(out)
	page.add_child(panel)


static func _signed_out(page: VBoxContainer, ctl: FcOnlineController, actions: Dictionary) -> void:
	var panel := FcPanel.new("Sign in or create an account", FcPanel.Variant.SURFACE)
	panel.add(FcUiTables.label("E-mail", FcUiTokens.TYPE_SMALL))
	var email := LineEdit.new()
	email.name = "Email"
	email.placeholder_text = "you@example.com"
	email.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add(email)
	panel.add(FcUiTables.label("Password (at least %d characters)" % FcSupabaseAuth.MIN_PASSWORD, FcUiTokens.TYPE_SMALL))
	var password := LineEdit.new()
	password.name = "Password"
	password.secret = true
	password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add(password)
	panel.add(_busy_label())
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	var sign_in := FcButton.make("Sign in", FcButton.Variant.PRIMARY, func() -> void: await _run(ctl, actions, "sign_in", email.text, password.text))
	sign_in.name = "SignIn"
	buttons.add_child(sign_in)
	var sign_up := FcButton.make("Create account", FcButton.Variant.SECONDARY, func() -> void: await _run(ctl, actions, "sign_up", email.text, password.text))
	sign_up.name = "SignUp"
	buttons.add_child(sign_up)
	var link := FcButton.make("E-mail me a sign-in link", FcButton.Variant.GHOST, func() -> void: await _run(ctl, actions, "magic_link", email.text, ""))
	link.name = "MagicLink"
	buttons.add_child(link)
	panel.add(buttons)
	panel.add(_wrapped("Your password is sent only to the online service and is never saved by the game.", FcUiTokens.TYPE_SMALL, true))
	page.add_child(panel)


## Builds the request, sends it, gives the answer to the controller and rebuilds the screen with the result.
static func _run(ctl: FcOnlineController, actions: Dictionary, kind: String, email: String, password: String) -> void:
	var begun := ctl.begin(kind, email, password)
	if not bool(begun["ok"]):
		actions["refresh"].call(str(begun["message"]))
		return
	var host: Node = actions["host"]
	_set_busy(host, true)
	var response: Dictionary = await FcOnlineHttp.send(host, begun["request"])
	if not is_instance_valid(host) or not host.is_inside_tree():
		return   # the player left the screen while waiting
	_set_busy(host, false)
	var done := ctl.finish(kind, response)
	actions["refresh"].call(str(done["message"]))


static func _busy_label() -> Label:
	var label := _wrapped("Contacting the online service...", FcUiTokens.TYPE_SMALL, true)
	label.name = "Busy"
	label.visible = false
	return label


static func _wrapped(text: String, size: int, muted: bool = false) -> Label:
	var label := FcUiTables.label(text, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted:
		label.theme_type_variation = "MutedLabel"
	return label
