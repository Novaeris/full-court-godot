class_name FcApp
extends Control
## The game's screens: main menu, new league, team choice, and the dashboard
## (overview, standings, schedule, roster, finances, staff, league). Everything
## goes through FcGameController; no game rules live here.
## The screens are built in code. Public methods (show_*, on_*, build_tab) let
## automated tests drive the same paths a player's clicks do.

const AREA_CHOICES := [
	["North America", ["north_america"]], ["Europe", ["europe"]], ["South America", ["south_america"]],
	["Asia", ["asia"]], ["Middle East", ["middle_east"]], ["Oceania", ["oceania"]], ["Africa", ["africa"]],
	["North America + Europe", ["north_america", "europe"]], ["Anywhere in the world", []],
]
const CAP_CHOICES := [["Soft cap with hard limit (recommended)", "soft_cap_with_hard_limit"], ["Hard cap", "hard_cap"], ["No cap (luxury tax only)", "no_cap"]]
const ERA_CHOICES := [["Mid 2010s (default)", "mid_2010s"], ["Early 2010s: slower, mid-range", "early_2010s"], ["Late 2010s: fast, three-point heavy", "late_2010s"]]
const GAMES_CHOICES := [["Short: about 40 games", 40], ["Medium: about 60 games", 60], ["Standard: about 80 games (default)", 80], ["Long: about 100 games", 100]]
const TAB_NAMES := ["Overview", "Standings", "Schedule", "Roster", "Finances", "Staff", "Draft", "Market", "Trades", "Meeting", "History", "News", "League"]

var controller: FcGameController
## The open Career Mode game (null in Owner Mode).
var career: FcCareerController
var _last_career_tab := 0
## The player's most recent games (newest first), shown on the Season tab.
var _career_log: Array = []
var saves := FcSaveManager.new()
## The player's settings (the tutorial is shown once, to a new Owner Mode game).
var preferences := FcPreferences.new()
## The game's sound (Phase 11); screens fire cues through FcAudio.cue.
var audio: FcAudio
## The portrait texture cache (D-059): bounded to 20 MB, emptied when a game is left.
var portrait_bake: FcPortraitBake
## First-run hints (Phase 12).
var hints: FcHints
## Published content (Creator Studio releases, D-042): loaded at start-up; falls back safely and reports why.
var content: FcContentService
## Dynasty Mode: the controller screens use and the screens' shell (built in setup).
var dynasty: FcDynastyController
var online: FcOnlineController   # created by show_online
var dynasty_ui: FcDynastyUi
## The open step of the tutorial (-1 = closed). Kept here because the dashboard is rebuilt often.
var _tutorial_step: int = -1
var _tutorial_steps: Array = []

var _defs := FcDefinitionSet.load_default()
var _data := FcGenerationData.load_default()
var _root: VBoxContainer
var _content: Control
var _pending_state: FcGameState
var _tabs: FcTabPages
## The team the user is talking to in the Trades tab (0 = first other team).
## Set after the warning about expiring contracts; a second press starts the next season.
var _confirm_next_season: bool = false
## The proposal that was selected on the Meeting tab (kept when the screen is rebuilt after lobbying).
## The page of the Finances tab that was open (kept when the screen is rebuilt).
## The open page of the Staff and Trades tabs.
var _last_tab := 0
var _form := {}
## The widgets of the main menu as built by FcMainMenu (mode_cards, save_cards, continue_button); tests and tools read it.
var _menu := {}
var _owner_context: FcOwnerContext = null
## The status line of the current screen. Hidden: messages are shown as toasts (notifier); the text stays here so tests, tools
## and later accessibility features can read the latest message.
var _message: Label
## The shell (docs/UI_POLISH_PLAN.md, Phase 3): the frame with the backdrop, the dialog and toast layers.
var host: FcScreenHost
## UI-only memory (seen cards, browse mode): not a save (D-048). Its file sits next to the preferences file.
var ui_state: FcUiState
## Which screen is showing and where Back goes.
var navigator := FcNavigator.new()
## Desktop or mobile presentation, and how much room there is.
var layout := FcLayoutProfile.new()
## Every message the player sees goes through here (toasts plus a history).
var notifier := FcNotifier.new()
## The active mode skin (resolved) and its key; the theme is rebuilt only when it changes.
var _skin: Dictionary = {}
var _skin_key: String = ""
var _last_mode: String = FcLayoutProfile.DESKTOP


func _ready() -> void:
	setup()
	call_deferred("_maybe_show_startup")
	if OS.get_cmdline_user_args().has("--selftest"):
		call_deferred("_run_self_test")


## The startup logos (Novaeris, then Full Court) over the main menu, which is already built behind them. Only when this node IS the running
## game (not when a tool or a test adds it to a scene), not headless, not in the self-test, and not switched off in Settings.
func _maybe_show_startup() -> void:
	if not is_inside_tree() or get_tree().current_scene != self or not preferences.show_splash or DisplayServer.get_name() == "headless":
		return
	if OS.get_cmdline_user_args().has("--selftest") or OS.get_cmdline_user_args().has("--no-splash") or not FcSplash.can_show():
		return
	var splash := FcSplash.new()
	host.overlay.add_child(splash)
	splash.start()


## `FullCourt.exe -- --selftest` (also headless): plays a small league through a season and an offseason using the
## packaged data files, saves it, prints "SELFTEST OK" or the problem, and quits (exit code 0 or 1). It is how a
## build is checked on the machine it was made for: a missing data file in the export shows up here.
func _run_self_test() -> void:
	var problem := ""
	saves = FcSaveManager.new("user://selftest_saves")
	if not on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "1", "name": "Selftest"}):
		problem = "could not create a league (a data file may be missing from the build)"
	else:
		on_start_game(_pending_state.world.teams.ids()[0])
		controller.sim_playoffs()
		controller.start_next_season()
		controller.sim_playoffs()
		var errors := controller.state.validate()
		if not errors.is_empty():
			problem = "the league is invalid: %s" % errors[0]
		elif not saves.save("selftest", controller.state, "Selftest").is_ok():
			problem = "could not write a save file"
		elif not saves.load_slot("selftest", _defs).is_ok():
			problem = "could not load the save file it just wrote"
	if problem == "":
		problem = _self_test_dynasty()
	FcSafeFile.remove_tree("user://selftest_saves")
	FcSafeFile.remove_tree("user://selftest_dynasty")
	print("SELFTEST OK" if problem == "" else "SELFTEST FAILED: " + problem)
	get_tree().quit(0 if problem == "" else 1)


## Builds the window frame and shows the main menu. Called automatically when the
## node enters the scene; safe to call again (tests call it directly because
## nodes added during a test run may not receive _ready yet).
func setup() -> void:
	if _root != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host = FcScreenHost.new()
	add_child(host)
	_root = host.content
	notifier.stack = host.toasts
	audio = FcAudio.new(preferences)
	add_child(audio)
	FcAudio.current = audio
	portrait_bake = FcPortraitBake.new()
	add_child(portrait_bake)
	if is_inside_tree():
		get_tree().node_added.connect(_on_node_added)   # every button makes the click sound; screens need no code for it
	if ui_state == null:
		ui_state = FcUiState.new(preferences.path.replace("preferences", "ui_state"))
	hints = FcHints.new(ui_state, preferences)
	FcMotion.reduced = preferences.reduce_motion
	layout.mobile_os = OS.has_feature("mobile")
	if layout.mobile_os and get_window() != null:
		var window := get_window()   # phone: size the UI by the screen's density instead of the 1280 px desktop design width
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_factor = FcLayoutProfile.phone_scale(DisplayServer.screen_get_dpi())
	layout.touch_available = DisplayServer.is_touchscreen_available()
	layout.override = preferences.layout_override
	layout.changed.connect(_on_layout_changed)
	resized.connect(func() -> void: layout.update(size))
	FcUiTokens.touch_mode = layout.is_mobile()
	apply_text_size(preferences.text_size)
	content = FcContentService.new(preferences, _defs)
	dynasty = FcDynastyController.new(content, _defs)
	dynasty_ui = FcDynastyUi.new(self, dynasty)
	_register_routes()
	show_main_menu()
	layout.update(size)


## The Dynasty half of the self-test: the bundled content release loads and is playable, a profile is created with the starter collection and a
## legal lineup, a game is played and a pack is opened, and the profile is saved and read back, all in a scratch folder.
func _self_test_dynasty() -> String:
	var ctl := FcDynastyController.new(content, _defs, FcDynastyStore.new("user://selftest_dynasty"))
	if not ctl.catalog.is_playable():
		return "the Dynasty content release is not playable: %s" % ctl.catalog.playable_problem()
	var made := ctl.create_profile("Selftest", "SLF", "f58c29", 7)
	if not made.ok:
		return "could not create a Dynasty profile: %s" % made.message
	if not ctl.lineup_problems().is_empty():
		return "the starter lineup is not legal: %s" % ctl.lineup_problems()[0]
	if not ctl.play_quick_game("easy").ok:
		return "could not play a Dynasty game"
	if not ctl.buy_pack("rookie_pack").ok:
		return "could not open a Dynasty pack"
	var slot: String = ctl.session.slot
	var cards := ctl.profile().unique_owned()
	ctl.close_profile()
	if not ctl.open_profile(slot).ok or ctl.profile().unique_owned() != cards:
		return "the Dynasty profile did not reload intact"
	return ""


func _exit_tree() -> void:
	if audio != null and FcAudio.current == audio:
		FcAudio.current = null


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("silent") and not (node as BaseButton).pressed.is_connected(_on_any_button):
		(node as BaseButton).pressed.connect(_on_any_button)


func _on_any_button() -> void:
	FcAudio.cue("ui_click")


## Sets the text size (0 small, 1 normal, 2 large) for the whole game and remembers the choice.
func apply_text_size(index: int) -> void:
	preferences.text_size = clampi(index, 0, FcUiTheme.SIZES.size() - 1)
	theme = FcUiTheme.build(preferences.text_size, _skin)
	preferences.save_file()


## Starts a new screen: clears the frame, shows the header and returns the (empty) content box. Every screen calls this first.
## `opts` (all optional): id (the screen's name; the fade-in runs only when it differs from the last screen's, so a screen that
## rebuilds itself after an action does not flash), back (a Callable: where Escape, the Android back button and Back go), rebuild (a
## Callable that shows the screen again, used when the window changes between desktop and mobile), skin (a FcModeSkin id) or
## skin_props (a resolved skin, e.g. FcModeSkin.franchise), header ({"kind": "plain" | "wordmark" | "letterhead" | "lower_third", ...}).
func _reset(title: String, opts: Dictionary = {}) -> VBoxContainer:
	_sync_player_ages()
	var animate := navigator.enter(str(opts.get("id", title)), opts.get("back", Callable()), opts.get("rebuild", Callable()))
	_apply_skin(opts.get("skin_props", FcModeSkin.resolve(str(opts.get("skin", FcModeSkin.NEUTRAL)))))
	if animate:
		host.modals.close_all()
	host.set_bottom_bar(null)
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_add_header(title, opts.get("header", {}))
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_content = box
	_message = FcUiTables.label("")
	_message.visible = false   # shown as a toast; kept so the latest message can be read
	_root.add_child(_message)
	var motion := navigator.take_motion()
	if animate:
		host.transition_in(_root, motion)
	return box


func _add_header(title: String, header: Dictionary) -> void:
	match str(header.get("kind", "plain")):
		"wordmark":
			_root.add_child(FcUiTables.label(title, FcUiTokens.TYPE_DISPLAY_XL, true))
			var tagline := FcUiTables.label(str(header.get("tagline", "")), FcUiTokens.TYPE_BODY)
			tagline.theme_type_variation = "MutedLabel"
			tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_root.add_child(tagline)
		"none":
			pass   # the screen draws its own header (the main menu shows the logo)
		"letterhead":
			var letterhead := FcLetterhead.new()
			letterhead.setup(title, str(header.get("subtitle", "")), str(header.get("abbr", "")), str(header.get("primary", "")), str(header.get("secondary", "")), header.get("team", {}))
			_root.add_child(letterhead)
		"lower_third":
			var third := FcLowerThird.new(title, str(header.get("subtitle", "")))
			third.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_root.add_child(third)
			third.play_in()
		_:
			_root.add_child(FcUiTables.label(title, 28, true))


## Switches the mode skin (theme, backdrop). The theme is rebuilt only when the skin or the touch layout really changed.
func _apply_skin(skin: Dictionary) -> void:
	var key := "%s|%s|%s" % [skin.get("id", ""), str(skin.get("accent", "")), FcUiTokens.touch_mode]
	if key == _skin_key:
		return
	_skin_key = key
	_skin = skin
	theme = FcUiTheme.build(preferences.text_size, skin)
	host.set_skin(skin)


## Shows a message to the player as a toast. The kind is guessed from the words; use notify() when you know it.
func _say(text: String) -> void:
	if _message != null:
		_message.text = text
	notifier.say(text)


## A message of a known kind (FcToast.Kind): the Dynasty screens know whether an action succeeded.
func notify(kind: FcToast.Kind, text: String) -> void:
	if _message != null:
		_message.text = text
	match kind:
		FcToast.Kind.SUCCESS:
			notifier.success(text)
		FcToast.Kind.WARNING:
			notifier.warning(text)
		FcToast.Kind.ERROR:
			notifier.error(text)
		_:
			notifier.info(text)


# --- layout, back handling, long actions ---------------------------------------------------------------------------

func _on_layout_changed(profile: FcLayoutProfile) -> void:
	FcUiTokens.touch_mode = profile.is_mobile()
	if layout.mobile_os:
		host.set_safe_margins(FcLayoutProfile.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), get_window().content_scale_factor))
	if profile.mode != _last_mode:
		_last_mode = profile.mode
		_skin_key = ""   # the theme depends on the touch target size, so build it again
		if navigator.can_rebuild():
			call_deferred("_rebuild_screen")   # after this frame; dropped automatically if the app is gone


func _rebuild_screen() -> void:
	navigator.rebuild()


## Goes back one screen (Escape, the Android back button): closes the top dialog first, then runs the screen's Back action.
## Returns false when there is nothing to go back to.
func go_back() -> bool:
	if host.modals.count() > 0:
		host.modals.top().close(false)
		return true
	var went := navigator.go_back()
	if went:
		FcAudio.cue("ui_back")
	return went


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and go_back():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not go_back():
		get_tree().quit()


## Runs a slow action (a month of games, a whole season) behind a loading overlay: the overlay is drawn first, then the work runs.
func run_with_loading(message: String, work: Callable) -> void:
	if not is_inside_tree():
		work.call()
		return
	var overlay := FcLoadingOverlay.show_on(host.overlay, message)
	await get_tree().process_frame
	work.call()
	if is_instance_valid(overlay):
		overlay.dismiss()


## Asks before leaving a game in progress for the main menu (Escape on a dashboard or hub).
func _confirm_leave_to_menu() -> void:
	host.modals.confirm("Return to the main menu?", "Anything you have not saved will be lost.", show_main_menu, false, "Main menu")


# --- main menu -----------------------------------------------------------------

func show_main_menu() -> void:
	host.modals.close_all()
	if portrait_bake != null:
		portrait_bake.clear()   # leaving a game: its pictures are not needed any more
	var box := _reset("FULL COURT", {"id": "menu", "rebuild": show_main_menu, "skin_props": FcModeSkin.resolve(FcModeSkin.NEUTRAL, {"background": "arena"}), "header": {"kind": "none"}})
	var slots := saves.list_slots()
	# the dropdown is kept (not shown): Load, Delete and Continue read the chosen save from it, so those methods and their tests keep working
	var picker := FcDropdown.new()
	var names: Array = []
	for m in slots:
		names.append(m.slot_id)
	picker.set_items(names)
	_form["slot"] = picker
	var actions := {"open_owner": show_new_league, "open_career": show_career_home, "open_dynasty": show_dynasty_home, "continue_latest": on_continue,
		"load": func(slot_id: String) -> void: _load_slot(slot_id),
		"delete": func(slot_id: String) -> void:
			_select_slot(slot_id)
			request_delete_selected(),
		"select": _select_slot, "settings": show_settings, "credits": show_credits, "online": func() -> void: show_online(), "quit": func() -> void: get_tree().quit(),
		"sound_on": not preferences.audio_muted, "set_sound": func(on: bool) -> void:
			preferences.audio_muted = not on
			preferences.save_file()
			if audio != null:
				audio.apply_settings()}
	if OS.has_feature("editor") or OS.get_cmdline_user_args().has("--gallery"):
		actions["gallery"] = show_gallery
	var compact := FcUiTokens.touch_mode or (size.x > 0.0 and size.x < 700.0)
	_menu = FcMainMenu.build(box, slots, actions, {"compact": compact, "content_warning": content.report.summary() if content != null and content.report.is_degraded() else ""})


## Makes `slot_id` the chosen save (the one Load, Delete and the cards act on).
func _select_slot(slot_id: String) -> void:
	var picker: FcDropdown = _form.get("slot")
	if picker == null:
		return
	for i in picker.item_count:
		if picker.get_item_text(i) == slot_id:
			picker.selected = i
			return


## Settings: text size, reduced motion, the layout (desktop or mobile), the tutorial, and where the content lives.
func show_settings() -> void:
	var box := _reset("Settings", {"id": "settings", "back": show_main_menu, "rebuild": show_settings})
	var display := FcPanel.new("Display", FcPanel.Variant.SURFACE)
	display.add(FcUiTables.label("Text size", FcUiTokens.TYPE_SMALL))
	var sizes := FcChoiceGroup.new()
	sizes.set_options([["0", "Small"], ["1", "Normal"], ["2", "Large"]], str(preferences.text_size))
	sizes.selected.connect(func(id: String) -> void:
		apply_text_size(int(id))
		show_settings())   # rebuild so headings and labels pick up the new size at once
	display.add(sizes)
	display.add(FcToggle.make("Reduce motion", preferences.reduce_motion, func(on: bool) -> void:
		preferences.reduce_motion = on
		preferences.save_file()
		FcMotion.reduced = on))
	display.add(FcToggle.make("Show the startup logos", preferences.show_splash, func(on: bool) -> void:
		preferences.show_splash = on
		preferences.save_file()))
	display.add(FcToggle.make("Cinematic pack opening (off: quick reveal)", preferences.pack_reveal_style == "cinematic", func(on: bool) -> void:
		preferences.pack_reveal_style = "cinematic" if on else "quick"
		preferences.save_file()))
	display.add(FcUiTables.label("Layout", FcUiTokens.TYPE_SMALL))
	var layouts := FcChoiceGroup.new()
	layouts.set_options([["auto", "Automatic"], ["desktop", "Desktop"], ["mobile", "Mobile"]], preferences.layout_override)
	layouts.selected.connect(func(id: String) -> void:
		preferences.layout_override = id
		preferences.save_file()
		layout.override = id
		layout.update(size))
	display.add(layouts)
	var hint := FcUiTables.label("Automatic follows your device: phones and small touch windows use the mobile layout. Owner Mode and Career Mode are designed for desktop screens.", FcUiTokens.TYPE_SMALL)
	hint.theme_type_variation = "MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display.add(hint)
	box.add_child(display)
	box.add_child(_sound_panel())
	var tips := FcPanel.new("Hints", FcPanel.Variant.SURFACE)
	tips.add(FcToggle.make("Show first-time hints", preferences.hints_enabled, func(on: bool) -> void:
		preferences.hints_enabled = on
		preferences.save_file()))
	var again := FcButton.make("Show the hints again", FcButton.Variant.SECONDARY, func() -> void:
		hints.reset()
		preferences.hints_enabled = true
		preferences.save_file()
		notify(FcToast.Kind.SUCCESS, "The hints will show again."))
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tips.add(again)
	box.add_child(tips)
	var help := FcPanel.new("Help", FcPanel.Variant.SURFACE)
	var replay := FcButton.make("Replay the tutorial next game", FcButton.Variant.SECONDARY, func() -> void:
		preferences.reset_tutorial()
		notify(FcToast.Kind.INFO, "The tutorial will open when you start your next Owner Mode game."))
	replay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help.add(replay)
	box.add_child(help)
	var data := FcPanel.new("Content", FcPanel.Variant.SURFACE)
	var path := FcUiTables.label("Content folder: %s" % ProjectSettings.globalize_path(preferences.effective_content_root()), FcUiTokens.TYPE_SMALL)
	path.theme_type_variation = "MutedLabel"
	path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	data.add(path)
	box.add_child(data)
	var back := FcButton.make("Back", FcButton.Variant.SECONDARY, show_main_menu, "chevron-left")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(back)


## The Sound panel of Settings: a mute switch, a volume for everything and for each kind of sound, the phone vibration toggle and a
## test button. Changes apply at once and are saved in preferences.cfg (the game is fully playable with the sound off).
func _sound_panel() -> Control:
	var panel := FcPanel.new("Sound", FcPanel.Variant.SURFACE)
	panel.add(FcToggle.make("Mute everything", preferences.audio_muted, func(on: bool) -> void:
		preferences.audio_muted = on
		_save_audio_settings()))
	for entry in [["Master volume", "audio_master"], ["Interface sounds", "audio_ui"], ["Effects (cards, packs, games)", "audio_sfx"], ["Crowd and arena (game replays)", "audio_crowd"], ["Arena ambience (game replays)", "audio_ambience"], ["Commentary (voice, when one is installed)", "audio_commentary"], ["Stadium announcer", "audio_announcer"], ["Music", "audio_music"]]:
		panel.add(FcUiTables.label(entry[0], FcUiTokens.TYPE_SMALL))
		var slider := FcSlider.new(0, 100, 5, "%")
		slider.set_value_silent(float(preferences.get(entry[1])))
		slider.value_changed.connect(func(v: float) -> void:
			preferences.set(entry[1], int(v))
			_save_audio_settings())
		panel.add(slider)
	panel.add(FcToggle.make("Sound captions in game replays", preferences.sound_captions, func(on: bool) -> void:
		preferences.sound_captions = on
		_save_audio_settings()))
	panel.add(FcToggle.make("Broadcast music in game replays", preferences.broadcast_music, func(on: bool) -> void:
		preferences.broadcast_music = on
		_save_audio_settings()))
	panel.add(FcToggle.make("Vibration on phones", preferences.haptics, func(on: bool) -> void:
		preferences.haptics = on
		_save_audio_settings()))
	var test := FcButton.make("Play a test sound", FcButton.Variant.SECONDARY, func() -> void: FcAudio.cue("reward"))
	test.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.add(test)
	var note := FcUiTables.label("Sounds and the optional broadcast music are made by the game itself. Commentary is shown as captions; a voice can be added later.", FcUiTokens.TYPE_SMALL)
	note.theme_type_variation = "MutedLabel"
	panel.add(note)
	return panel


func _save_audio_settings() -> void:
	preferences.save_file()
	if audio != null:
		audio.apply_settings()


## Deleting a save cannot be undone, so the Delete button asks first (the dialog starts on Cancel).
func request_delete_selected() -> void:
	var picker: FcDropdown = _form.get("slot")
	if picker == null or picker.item_count == 0:
		return
	var slot := picker.get_item_text(picker.selected)
	host.modals.confirm("Delete this save?", "'%s' will be deleted for good." % slot, on_delete_selected, true, "Delete")


## The development-only Component Gallery (every design token and kit component; see docs/UI_POLISH_PLAN.md). Leaving it puts the
## player's own text size, motion and layout settings back, because the gallery changes them to show each variant.
func show_gallery() -> void:
	var box := _reset("Component gallery", {"id": "gallery", "back": show_main_menu})
	var gallery := FcComponentGallery.new()
	gallery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery.closed.connect(func() -> void:
		FcUiTokens.touch_mode = layout.is_mobile()
		FcMotion.reduced = preferences.reduce_motion
		_skin_key = ""
		apply_text_size(preferences.text_size)
		show_main_menu())
	box.add_child(gallery)
	_form["gallery"] = gallery


## Career Mode's home: create a player (or continue from the saved games list on the main menu). Progression, the
## calendar and games come in later phases (docs/CAREER_MODE_PLAN.md); this screen says so plainly.
func show_career_home() -> void:
	var box := _reset("Career Mode", {"id": "career_home", "skin": FcModeSkin.BROADCAST, "back": show_main_menu, "rebuild": show_career_home})
	var panel := FcPanel.new("Your career", FcPanel.Variant.RAISED)
	panel.set_accent(FcModeSkin.resolve(FcModeSkin.BROADCAST)["accent"])
	panel.custom_minimum_size.x = 360
	var text := FcUiTables.label("Create one player (name, body, position, strengths) and take them through a career of about 20 seasons: scouting and the draft, decisions, contracts, relationships, rivalries, sponsorships and a legacy. You reach your potential by choosing which skills to raise.", FcUiTokens.TYPE_BODY)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add(text)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	row.add_child(FcButton.make("Create a player", FcButton.Variant.PRIMARY, show_career_creator, "plus"))
	row.add_child(FcButton.make("Back to the main menu", FcButton.Variant.SECONDARY, show_main_menu, "chevron-left"))
	panel.add(row)
	box.add_child(panel)


## The player creator (FcCareerCreator). A valid build makes the player and opens the Career Hub.
func show_career_creator() -> void:
	var box := _reset("Career Mode: create your player", {"id": "career_creator", "skin": FcModeSkin.BROADCAST, "back": show_career_home, "rebuild": show_career_creator})
	var creator_hint := hints.card("career_creator")
	if creator_hint != null:
		box.add_child(creator_hint)
	var creator := FcCareerCreator.new(_defs)
	creator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator.create_requested.connect(on_create_career)
	var scroll := ScrollContainer.new()   # the whole form scrolls, so the buttons stay reachable in a small window
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(creator)
	box.add_child(scroll)
	creator.build()   # safe to call twice; makes sure the form exists even when _ready has not run yet
	_form["career_creator"] = creator
	box.add_child(FcUiTables.button("Back", show_career_home))


## Creates the career from a validated build, saves it to slot career_1 and shows the hub. Returns false (and says why) if the
## build is not valid.
func on_create_career(spec: Dictionary, seed_value: int = -1) -> bool:
	var seed_number := seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	var made := FcCareerController.new_career(spec, seed_number)
	if made.has("errors"):
		_say("Cannot create this player: " + "; ".join(made["errors"]))
		return false
	career = made["controller"]
	var saved := career.save(saves)
	show_career_hub()
	_say("Player created." if saved.is_ok() else "Player created, but the save failed: " + saved.message)
	return true


## The Career Hub: the player's card, development (points, training) and skills (badges). The calendar and games come next.
func show_career_hub() -> void:
	var card := career.card()
	var box := _reset("%s   #%d" % [card["name"], card["jersey"]], {"id": "career_hub", "skin": FcModeSkin.BROADCAST, "back": _confirm_leave_to_menu,
		"header": {"kind": "lower_third", "subtitle": "%s   %s   Age %d" % [card["position"], card["archetype"], card["age"]]}})
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var progress := career.progress()
	var view_model := FcPlayerPresentation.from_career(career)
	body.add_child(FcCareerHub.hero(card, progress, view_model, func() -> void: FcPlayerProfile.open_modal(self, FcPlayerPresentation.from_career(career))))
	var career_hint := hints.card("career_hub")
	if career_hint != null:
		body.add_child(career_hint)
	var tabs := FcTabPages.new()
	tabs.add_page(_career_card_tab(card), "Card")
	tabs.add_page(_career_season_tab(), "Season")
	tabs.add_page(_career_develop_tab(card, progress), "Develop")
	tabs.add_page(_career_skills_tab(progress), "Skills")
	tabs.add_page(_career_story_tab(), "Story")
	tabs.custom_minimum_size.y = 380   # the tabs keep a usable height; the whole hub scrolls when the window is short
	tabs.current_tab = clampi(_last_career_tab, 0, 4)
	tabs.tab_changed.connect(func(i): _last_career_tab = i)
	body.add_child(tabs)
	body.add_child(FcUiTables.label("Career id %s. Saved to slot career_1; load it from the main menu." % card["profile_id"], 14))
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Save", func():
		var r := career.save(saves)
		_say("Saved." if r.is_ok() else "Save failed: " + r.message)))
	row.add_child(FcUiTables.button("Main Menu", show_main_menu))
	body.add_child(row)
	var hub_scroll := ScrollContainer.new()   # the hero, the hint, the tabs and the buttons scroll together in a short window
	hub_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hub_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_scroll.add_child(body)
	box.add_child(hub_scroll)


## The game-day preview of the career team's next game. "Play this game" plays up to it and opens its summary and replay.
func on_career_game_day() -> void:
	var model := FcGameDay.for_owner(career.game())
	if model.is_empty():
		_say("There is no regular-season game left to preview.")
		return
	FcGameDay.open(self, model, career.state.world, play_career_game_day)


func play_career_game_day() -> void:
	var days := career.game().days_to_next_user_game()
	if days <= 0:
		return
	var result := on_career_play(days)
	if result["ok"] and not _career_log.is_empty():
		FcPostGame.open(self, FcPostGame.for_career(career, _career_log[0]))


## Plays days for the career player and keeps the newest results for the Season tab.
func on_career_play(days: int) -> Dictionary:
	var result := career.advance_days(days)
	if result["ok"]:
		for game in result["games"]:
			_career_log.push_front(game)
		_career_log = _career_log.slice(0, 12)
	show_career_hub()
	if result["ok"]:
		var xp := 0
		var levels := 0
		for game in result["games"]:
			xp += int(game["xp"])
			levels += int(game.get("levels_gained", 0))
		if levels > 0:
			notifier.achievement("Level up! You are now level %d." % int(career.progress()["level"]), "level_up")
		_say("%d game%s played, +%d XP." % [result["games"].size(), "" if result["games"].size() == 1 else "s", xp])
	else:
		_say(str(result.get("reason", "")))
	return result


func on_career_finish_season() -> Dictionary:
	var result := career.finish_season()
	if result.get("contract_pending", false):
		show_career_hub()
		_say("Your season is done. Your contract ends: settle the talks to move on.")
		return result
	if result["ok"]:
		for game in result["games"]:
			_career_log.push_front(game)
		_career_log = _career_log.slice(0, 12)
	show_career_hub()
	if result["ok"]:
		var s: Dictionary = result["summary"]
		_say("Season %d finished: %d games, %.1f points a game. %s %s" % [s["year"], s["games"], s["points"], result["milestone"], "You have retired: your career is complete." if career.is_retired() else "The new season has begun."])
	return result


func _career_season_tab() -> Control:
	var box := VBoxContainer.new()
	if career.is_retired():
		box.add_child(FcUiTables.label("Your career is over: you retired after %d seasons. Your legacy is below." % career.profile().history.size(), 18, true))
		box.add_child(FcCareerStory.legacy_page(career.legacy(), true))
		box.add_child(_career_history_table())
		return box
	if not career.is_signed():
		box.add_child(FcUiTables.label("You do not have a team yet. Choose one, or let the draft decide.", 16, true))
		var outlook := career.draft_outlook()
		box.add_child(FcUiTables.label("Scouting report: overall %d, potential %d. Projected pick %d of %d, to %s. %s" % [outlook["overall"], outlook["potential"], outlook["pick"], outlook["picks"], career.state.world.team_display_name(outlook["team_id"]), outlook["note"]], 15))
		var row := HBoxContainer.new()
		var picker := FcDropdown.new()
		for tid in career.state.world.teams.ids():
			picker.add_item(career.state.world.team_display_name(tid))
			picker.set_item_metadata(picker.item_count - 1, tid)
		picker.tooltip_text = "Pick the team you want to sign a rookie contract with."
		row.add_child(picker)
		row.add_child(FcUiTables.button("Sign with this team", func():
			var r := career.join_team(picker.get_item_metadata(picker.selected))
			_say(r["reason"])
			show_career_hub()))
		row.add_child(FcUiTables.button("Let the draft decide", func():
			var r2 := career.join_team(career.draft_team())
			_say(r2["reason"])
			show_career_hub()))
		box.add_child(row)
		return box
	if career.profile().potential_banner_pending:
		var banner := PanelContainer.new()
		var banner_box := VBoxContainer.new()
		banner.add_child(banner_box)
		var title := FcUiTables.label("MAX POTENTIAL REACHED", 26, true)
		title.add_theme_color_override("font_color", FcUiTheme.ACCENT)
		banner_box.add_child(title)
		var story := FcUiTables.label("You've reached your ceiling. Your hard work has unlocked everything your natural potential had to offer. Now it's time to build your legacy.", 16)
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size = Vector2(400, 0)
		banner_box.add_child(story)
		banner_box.add_child(FcUiTables.label("Reward: XP, a skill point and currency. Your points stay banked; keep playing, keep your rating up and chase records, titles and your legacy.", 14))
		banner_box.add_child(FcUiTables.button("Continue my career", func():
			career.dismiss_potential_banner()
			show_career_hub()))
		box.add_child(banner)
	var offer := career.contract_offer()
	if not offer.is_empty():
		var talks := PanelContainer.new()
		var inner_talks := VBoxContainer.new()
		talks.add_child(inner_talks)
		inner_talks.add_child(FcUiTables.label("Contract talks with %s" % offer["team"], 18, true))
		var terms := FcUiTables.label("Your contract ends. The team offers $%.2fM a year for %d years (market value for you: $%.2fM). With your agent (%s) and your reputation you can push up to $%.2fM. Or let it run out and go to free agency: the league's teams decide, and you may land somewhere else." % [
			offer["salary"] / 1e6, offer["years"], offer["market_ask"] / 1e6, offer["agent"], offer["max_salary"] / 1e6], 15)
		terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		terms.custom_minimum_size = Vector2(400, 0)
		inner_talks.add_child(terms)
		var talk_row := HBoxContainer.new()
		talk_row.add_child(FcUiTables.button("Accept the offer", func():
			var r := career.answer_contract("accept")
			_say(r["reason"])
			on_career_finish_season()))
		var counter := SpinBox.new()
		counter.min_value = 0.1
		counter.max_value = 100
		counter.step = 0.05
		counter.value = offer["max_salary"] / 1e6
		counter.tooltip_text = "The yearly salary you ask for, in millions. The team refuses anything above its ceiling."
		talk_row.add_child(counter)
		talk_row.add_child(FcUiTables.button("Ask for this salary ($M)", func():
			var r2 := career.answer_contract("counter", roundi(counter.value * 1e6 / 10000.0) * 10000)
			_say(r2["reason"])
			if r2["ok"]:
				on_career_finish_season()
			else:
				show_career_hub()))
		talk_row.add_child(FcUiTables.button("Let it run out (free agency)", func():
			var r3 := career.answer_contract("expire")
			_say(r3["reason"])
			on_career_finish_season()))
		inner_talks.add_child(talk_row)
		box.add_child(talks)
	var pending := career.pending_event()
	if not pending.is_empty():
		var card := PanelContainer.new()
		var inner := VBoxContainer.new()
		card.add_child(inner)
		inner.add_child(FcUiTables.label("A decision: " + pending["title"], 18, true))
		var story := FcUiTables.label(pending["text"], 15)
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size = Vector2(400, 0)
		inner.add_child(story)
		var choices := HBoxContainer.new()
		for choice in pending["choices"]:
			var button := FcUiTables.button(choice["label"], func():
				var r := career.answer_event(choice["key"])
				_say(r["reason"])
				show_career_hub())
			button.tooltip_text = choice["note"]
			choices.add_child(button)
		inner.add_child(choices)
		inner.add_child(FcUiTables.label("Hover a choice to see exactly what it does. You must decide before you play on.", 13))
		box.add_child(card)
	var g := career.game()
	var next := career.next_game()
	box.add_child(FcUiTables.label("%s    Season %d-%02d" % [career.state.world.team_display_name(career.state.user_team_id), career.state.current_season, (career.state.current_season + 1) % 100], 16, true))
	if next.is_empty():
		box.add_child(FcUiTables.label("No regular-season game left. Finish the season to move on.", 14))
	else:
		box.add_child(FcUiTables.label("Next game: %s %s on %s" % ["vs" if next["home"] else "at", next["opponent"], next["date"]], 15))
	box.add_child(_career_role_row())
	var buttons := HBoxContainer.new()
	var done: bool = g.phase() == FcGameController.PHASE_COMPLETE
	var preview := FcUiTables.button("Game day", on_career_game_day)
	preview.disabled = done or next.is_empty()
	buttons.add_child(preview)
	var day := FcUiTables.button("Play next day", func(): on_career_play(1))
	day.disabled = done
	buttons.add_child(day)
	var week := FcUiTables.button("Play next week", func(): on_career_play(7))
	week.disabled = done
	buttons.add_child(week)
	var finish := FcUiTables.button("Finish the season", on_career_finish_season)
	finish.tooltip_text = "Plays everything left, records your season, and runs the league offseason into the next season."
	buttons.add_child(finish)
	box.add_child(buttons)
	var rel := career.relationships()
	var rel_label := FcUiTables.label("Coach: %s (%d)    Teammates: %s (%d)    Reputation %d    Currency %d" % [rel["coach_label"], rel["coach_trust"], rel["chemistry_label"], rel["chemistry"], career.profile().reputation, career.profile().currency], 14)
	rel_label.tooltip_text = "The coach trusts players who are among his best and who play; teammates bond over winning and community work. Trust changes what role you can ask for and how hard you can bargain; a close team earns a development point each season."
	box.add_child(rel_label)
	var rival := career.rival()
	if not rival.is_empty():
		box.add_child(FcUiTables.label("Rival: %s (%s, overall %d)    Head to head: %d-%d" % [rival["name"], rival["team"], rival["overall"], rival["wins"], rival["losses"]], 14))
	var line := career.season_line()
	if int(line.get("games", 0)) > 0:
		box.add_child(FcUiTables.label("This season: %d games, %.1f points, %.1f rebounds, %.1f assists, %.1f minutes a game" % [line["games"], line["points"], line["rebounds"], line["assists"], line["minutes"]], 15))
	var rows: Array = []
	for game in _career_log:
		var l: Dictionary = game["line"]
		var duel_text := ""
		if game.has("duel"):
			duel_text = "Duel %s vs %s (%d pts)" % ["won" if game["duel"]["won"] else "lost", game["duel"]["rival"], game["duel"]["rival_points"]]
		rows.append([game["opponent"], "W" if game["won"] else "L", game["score"], "%d" % l["minutes"], l["points"], l["rebounds"], l["assists"], "+%d" % game["xp"], ", ".join(game["milestones"]).replace("_", " ") + (" " if duel_text != "" and not game["milestones"].is_empty() else "") + duel_text])
	box.add_child(FcUiTables.label("Recent games", 16, true))
	if not _career_log.is_empty():
		box.add_child(_career_game_picker())
	box.add_child(FcTable.from_strings(["Opponent", "", "Score", "Min", "Pts", "Reb", "Ast", "XP", "Milestones"], rows, [0, 30, 70, 40, 40, 40, 40, 50, 0]))
	box.add_child(FcUiTables.label("Career history", 16, true))
	box.add_child(_career_history_table())
	box.add_child(_career_storylines())
	return box


## The league's latest storylines (dynasties, upsets, records, retirements, rivalries), worked out from the history the league keeps.
func _career_storylines() -> Control:
	var box := VBoxContainer.new()
	box.name = "LeagueStorylines"
	box.add_child(FcUiTables.label("League storylines", FcUiTokens.TYPE_H3, true))
	var game := career.game()
	if game == null:
		return box
	var items := FcStorylines.new(career.state.world, game.league_id, career.state.current_season).recent(5)
	if items.is_empty():
		box.add_child(FcUiTables.label("Nothing yet: storylines appear as seasons are completed.", FcUiTokens.TYPE_BODY))
	for item in items:
		var line := FcUiTables.label("%d-%02d  %s" % [item["year"], (int(item["year"]) + 1) % 100, item["headline"]], FcUiTokens.TYPE_BODY)
		line.tooltip_text = str(item["text"])
		box.add_child(line)
	return box


## Pick one of the recent games, then open its summary or its replay.
func _career_game_picker() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	var items: Array = []
	for i in _career_log.size():
		var game: Dictionary = _career_log[i]
		items.append(["%s  %s %s" % [game["opponent"], "W" if game["won"] else "L", game["score"]], i])
	var picker := FcDropdown.make(items, 0)
	picker.name = "GamePicker"
	row.add_child(picker)
	row.add_child(FcButton.make("Game summary", FcButton.Variant.SECONDARY, func() -> void: FcPostGame.open(self, FcPostGame.for_career(career, _career_log[int(picker.value())]))))
	var watch := FcButton.make("Watch replay", FcButton.Variant.PRIMARY, func() -> void:
		var built := FcReplay.for_career(career, _career_log[int(picker.value())])
		if built.is_empty():
			_say("No replay was kept for that game.")
		else:
			FcReplay.open(self, built))
	watch.name = "WatchReplayButton"
	row.add_child(watch)
	return row


func _career_history_table() -> Control:
	var history: Array = []
	for h in career.profile().history:
		history.append(["%d-%02d" % [h["year"], (int(h["year"]) + 1) % 100], career.state.world.team_display_name(int(h["team_id"])), h["games"], "%.1f" % h["points"], "%.1f" % h["rebounds"], "%.1f" % h["assists"], "%d-%d" % [h["wins"], h["losses"]]])
	return FcTable.from_strings(["Season", "Team", "GP", "PPG", "RPG", "APG", "Team record"], history, [80, 0, 50, 60, 60, 60, 100])


## The role request: the coach may refuse what the player has not earned.
func _career_role_row() -> Control:
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.label("Role"))
	var role := FcDropdown.new()
	for entry in [["Coach decides", "auto"], ["Starter", "starter"], ["Bench", "bench"]]:
		role.add_item(entry[0])
		role.set_item_metadata(role.item_count - 1, entry[1])
	role.selected = ["auto", "starter", "bench"].find(career.profile().role)
	role.tooltip_text = "Ask to start or to come off the bench. The coach refuses a start you have not earned."
	row.add_child(role)
	row.add_child(FcUiTables.label("  Minutes"))
	var minutes := FcDropdown.new()
	for entry in [["Fewer", -1], ["Normal", 0], ["More", 1]]:
		minutes.add_item(entry[0])
		minutes.set_item_metadata(minutes.item_count - 1, entry[1])
	minutes.selected = career.profile().minutes_pref + 1
	minutes.tooltip_text = "Playing more needs some reputation."
	row.add_child(minutes)
	row.add_child(FcUiTables.label("  Style"))
	var usage := FcDropdown.new()
	for entry in [["Pass first", -1], ["Balanced", 0], ["Shoot first", 1]]:
		usage.add_item(entry[0])
		usage.set_item_metadata(usage.item_count - 1, entry[1])
	usage.selected = career.profile().usage_pref + 1
	usage.tooltip_text = "How often you are the one who shoots. Shooting first needs some reputation."
	row.add_child(usage)
	row.add_child(FcUiTables.button("Ask the coach", func():
		var r := career.set_role(role.get_item_metadata(role.selected), minutes.get_item_metadata(minutes.selected), usage.get_item_metadata(usage.selected))
		_say(r["reason"])
		show_career_hub()))
	return row


## The story: public image and headlines, the legacy so far, and the career timeline.
func _career_story_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "CareerStoryTab"
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	box.add_child(FcCareerStory.public_image(career.profile()))
	var summary := career.legacy()
	if not summary.is_empty():
		box.add_child(FcCareerStory.legacy_page(summary, career.is_retired()))
	box.add_child(FcCareerStory.timeline(career.profile()))
	return box


func _career_card_tab(card: Dictionary) -> Control:
	return FcCareerHub.card_tab(card)


func _career_develop_tab(_card: Dictionary, progress: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var view := career.development_view()
	var pot: Dictionary = view["progress"]
	var head := FcUiTables.label("Overall %d of your %d potential%s    Development points: %d" % [pot["overall"], pot["potential"], "  (at your ceiling)" if pot["at_potential"] else "  (%d to go)" % pot["to_go"], progress["development_points"]], 17, true)
	head.tooltip_text = "Potential is the highest overall you can reach. You get there by choosing which skills to raise: skills that count more in overall give more per point."
	box.add_child(head)
	var bar := FcProgress.new(FcProgress.Variant.GOLD)
	bar.set_progress(float(pot["fraction"]) * 100.0, 100.0)
	bar.custom_minimum_size = Vector2(300, 14)
	bar.tooltip_text = "%d of your %d potential" % [pot["overall"], pot["potential"]]
	box.add_child(bar)
	var best: Dictionary = view["best"]
	if not best.is_empty():
		var hint := "Best next upgrade: %s (+%.2f overall for %d point%s)%s" % [best["name"], best["gain"], best["cost"], "" if best["cost"] == 1 else "s", "" if best["affordable"] else ". You need more points for it."]
		box.add_child(FcUiTables.label(hint, 15))
	else:
		box.add_child(FcUiTables.label("Nothing more can be raised right now. Keep your points: age will lower your rating and you can spend them to hold it.", 15))
	var train_row := HBoxContainer.new()
	var train_button := FcUiTables.button("Train (%d sessions left this season)" % progress["training_left"], func():
		var r := career.train()
		_say(r["reason"])
		show_career_hub())
	train_button.tooltip_text = "A training session gives XP. Each season has a few, and each is worth a little less than the last: training is a choice, not a grind."
	train_row.add_child(train_button)
	box.add_child(train_row)
	var intro := FcUiTables.label("Raise the skills that matter for the player you want to be. Each row shows the cost and exactly what the upgrade does to your overall; a blocked row says why. You do not have to raise everything: a few strong skills can take you to your potential.", 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(400, 0)
	box.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	for h in ["Skill", "Now / most", "Cost", "Overall +", "", "Why not"]:
		grid.add_child(FcUiTables.label(h, 14, true))
	for row in view["rows"]:
		grid.add_child(FcUiTables.label(row["name"]))
		grid.add_child(FcUiTables.label("%d / %d" % [row["value"], row["ceiling"]]))
		grid.add_child(FcUiTables.label("%d" % row["cost"]))
		grid.add_child(FcUiTables.label("%+.2f" % row["gain"] if row["blocked"] in ["", "points"] else "-"))
		var key: String = row["key"]
		var raise := FcUiTables.button("+1", func():
			var r := career.raise_attribute(key)
			_say(r["reason"])
			show_career_hub())
		raise.disabled = not row["ok"]
		raise.tooltip_text = row["reason"]
		grid.add_child(raise)
		var why := FcUiTables.label("" if row["ok"] else row["reason"], 13)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(260, 0)
		grid.add_child(why)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	box.add_child(scroll)
	box.add_child(_career_business_row())
	return box


## Sponsors and looks: the money side of the career (currency buys looks only, never ability).
func _career_business_row() -> Control:
	var box := VBoxContainer.new()
	var deal: Dictionary = career.profile().sponsor_deal
	if not deal.is_empty():
		var current := HBoxContainer.new()
		current.add_child(FcUiTables.label("Sponsor: %s, %d currency a season, %d season%s left%s" % [deal["sponsor"], deal["amount"], deal["years_left"], "" if deal["years_left"] == 1 else "s", " (bold brand: costs reputation each season)" if deal["edge"] == "bold" else ""]))
		current.add_child(FcUiTables.button("End the deal", func():
			_say(career.drop_sponsor()["reason"])
			show_career_hub()))
		box.add_child(current)
	else:
		var offers := career.sponsor_offers()
		if offers.is_empty():
			box.add_child(FcUiTables.label("No sponsor knows you yet: build some reputation first (5 or more).", 14))
		else:
			var row := HBoxContainer.new()
			row.add_child(FcUiTables.label("Sponsor offers:"))
			for offer in offers:
				var button := FcUiTables.button("%s: %d a season x %d%s" % [offer["sponsor"], offer["amount"], offer["years"], " (bold)" if offer["edge"] == "bold" else ""], func():
					_say(career.sign_sponsor(offer["sponsor"])["reason"])
					show_career_hub())
				button.tooltip_text = "A bold brand pays 60% more but its image costs you 1 reputation and 1 chemistry every season." if offer["edge"] == "bold" else "A steady deal with no downside."
				row.add_child(button)
			box.add_child(row)
	var look := HBoxContainer.new()
	look.add_child(FcUiTables.label("New look (%d currency, you have %d):" % [FcCareerRules.COSMETIC_COST, career.profile().currency]))
	var part := FcDropdown.new()
	var appearance: Dictionary = FcBuildRules.rules()["appearance"]
	for key in appearance:
		part.add_item(str(key).replace("_", " "))
		part.set_item_metadata(part.item_count - 1, key)
	var option := FcDropdown.new()
	var fill := func():
		option.clear()
		for o in appearance[part.get_item_metadata(part.selected)]:
			option.add_item(str(o).replace("_", " "))
			option.set_item_metadata(option.item_count - 1, o)
	part.item_selected.connect(func(_i): fill.call())
	fill.call()
	look.add_child(part)
	look.add_child(option)
	look.add_child(FcUiTables.button("Buy", func():
		_say(career.change_appearance(part.get_item_metadata(part.selected), option.get_item_metadata(option.selected))["reason"])
		show_career_hub()))
	box.add_child(look)
	return box


func _career_skills_tab(progress: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var intro := FcUiTables.label("Badges reward a playstyle with a small, capped bonus in the simulation. They need a level, attribute minimums and sometimes another badge, and cost skill points. You can equip up to %d." % int(FcBuildRules.rules()["max_badges_equipped"]), 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(400, 0)
	box.add_child(intro)
	var rows: Array = []
	for b in career.badge_list():
		rows.append([b["name"], b["tree"].capitalize(), b["cost"], "Equipped" if b["equipped"] else ("Owned" if b["owned"] else (b["problem"] if b["problem"] != "" else "Ready to unlock")), b["description"]])
	box.add_child(FcTable.from_strings(["Badge", "Tree", "Cost", "Status", "What it does"], rows, [170, 100, 50, 300, 0]))
	var pick := FcDropdown.new()
	for b in career.badge_list():
		pick.add_item(b["name"])
		pick.set_item_metadata(pick.item_count - 1, b["key"])
	pick.tooltip_text = "Choose a badge, then unlock it or equip it."
	var actions := HBoxContainer.new()
	actions.add_child(pick)
	actions.add_child(FcUiTables.button("Unlock", func():
		var r := career.unlock_badge(pick.get_item_metadata(pick.selected))
		_say(r["reason"])
		show_career_hub()))
	actions.add_child(FcUiTables.button("Equip", func():
		var r2 := career.equip_badge(pick.get_item_metadata(pick.selected), true)
		_say(r2["reason"])
		show_career_hub()))
	actions.add_child(FcUiTables.button("Unequip", func():
		var r3 := career.equip_badge(pick.get_item_metadata(pick.selected), false)
		_say(r3["reason"])
		show_career_hub()))
	box.add_child(actions)
	return box


## Dynasty Mode's home: choose or create a Dynasty team (the screens live in src/ui/dynasty).
func show_dynasty_home() -> void:
	dynasty.refresh_content()
	dynasty_ui.show_entry()


## The Credits screen (it replaced About): the Full Court and Novaeris logos, the version, what the game is built with and its licences,
## and shortcuts to the folders with logs and saves, so a player can send a log when something goes wrong.
func show_credits() -> void:
	var box := _reset("Credits", {"id": "about", "back": show_main_menu, "rebuild": show_credits})
	FcCredits.build(box, {"back": show_main_menu,
		"open_logs": func() -> void: OS.shell_open(ProjectSettings.globalize_path("user://logs")),
		"open_saves": func() -> void: OS.shell_open(ProjectSettings.globalize_path("user://")),
		"open_content": func() -> void:
			FcSafeFile.make_dir(preferences.effective_content_root())
			OS.shell_open(ProjectSettings.globalize_path(preferences.effective_content_root()))},
		content.report.summary() if content != null else "")


## The Online screen (optional sign-in, D-066). `message` is the result of the last action. Online is created on first use so an offline-only
## player never touches the config or session files.
func show_online(message: String = "") -> void:
	if online == null:
		online = FcOnlineController.new(FcOnlineConfig.load_file())
	var box := _reset("Online", {"id": "online", "back": show_main_menu, "rebuild": show_online})
	FcOnlineScreen.build(box, online, {"back": show_main_menu, "host": self, "refresh": func(text: String) -> void: show_online(text)}, message)


## Kept under its old name: tests, tools and older code call it.
func show_about() -> void:
	show_credits()


func on_continue() -> void:
	var slots := saves.list_slots()
	if not slots.is_empty():
		_load_slot(slots[0].slot_id)


func on_load_selected() -> void:
	var picker: OptionButton = _form.get("slot")
	if picker != null and picker.item_count > 0:
		_load_slot(picker.get_item_text(picker.selected))


func on_delete_selected() -> void:
	var picker: OptionButton = _form.get("slot")
	if picker != null and picker.item_count > 0:
		saves.delete_slot(picker.get_item_text(picker.selected))
		show_main_menu()


func _load_slot(slot_id: String) -> void:
	var result := saves.load_slot(slot_id, _defs)
	if not result.is_ok():
		_say("Could not load: " + result.message)
		return
	if result.state.mode == FcGameState.MODE_CAREER:
		career = FcCareerController.resume(result.state)
		if career == null:
			_say("That career save has no player in it.")
			return
		show_career_hub()
		if result.recovered_from != "":
			_say("The save was damaged; an older copy (%s) was loaded." % result.recovered_from)
		return
	controller = FcGameController.resume(result.state)
	show_dashboard()
	if result.recovered_from != "":
		_say("The save was damaged; an older copy (%s) was loaded." % result.recovered_from)


# --- new league -------------------------------------------------------------------

func show_new_league() -> void:
	var box := _reset("New League", {"id": "new_league", "skin": FcModeSkin.FRANCHISE, "back": show_main_menu, "rebuild": show_new_league})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	_form["name"] = _line_edit(grid, "League name", "Full Court League")
	_form["areas"] = _options(grid, "Where the teams are from", AREA_CHOICES.map(func(a): return a[0]))
	var counts := FcLeagueStructure.valid_team_counts()
	var counts_text: Array = counts.map(func(c): return "%d teams" % c)
	_form["teams"] = _options(grid, "Number of teams", counts_text)
	_form["teams"].selected = counts.find(30)
	_form["structure"] = _options(grid, "Conferences and divisions", [])
	_form["cap"] = _options(grid, "Salary cap", CAP_CHOICES.map(func(a): return a[0]))
	_form["era"] = _options(grid, "Style of play", ERA_CHOICES.map(func(a): return a[0]))
	_form["games"] = _options(grid, "Season length (30-team league)", GAMES_CHOICES.map(func(a): return a[0]))
	_form["games"].selected = 2
	_form["lottery"] = _options(grid, "Draft lottery", ["On (worst teams are favoured but not guaranteed)", "Off (worst record picks first)"])
	_form["mode"] = _options(grid, "Game mode", ["Owner Mode", "Spectator (watch the league, no owner controls)"])
	_form["seed"] = _line_edit(grid, "Random seed (same seed = same league)", str(randi() % 100000))
	(_form["teams"] as OptionButton).item_selected.connect(func(_i): _fill_structures())
	_fill_structures()
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Create League", on_create_league))
	row.add_child(FcUiTables.button("Back", show_main_menu))
	box.add_child(row)


func _line_edit(grid: GridContainer, title: String, value: String) -> LineEdit:
	grid.add_child(FcUiTables.label(title))
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(320, 0)
	grid.add_child(e)
	return e


func _options(grid: GridContainer, title: String, items: Array) -> OptionButton:
	grid.add_child(FcUiTables.label(title))
	var o := FcDropdown.new()
	for i in items:
		o.add_item(str(i))
	grid.add_child(o)
	return o


func _fill_structures() -> void:
	var counts := FcLeagueStructure.valid_team_counts()
	var teams := counts[(_form["teams"] as OptionButton).selected]
	var o: OptionButton = _form["structure"]
	o.clear()
	for s in FcLeagueStructure.valid_structures(teams):
		o.add_item("%d conference%s x %d division%s of %d teams" % [
			s["conferences"], "" if s["conferences"] == 1 else "s",
			s["divisions_per_conference"], "" if s["divisions_per_conference"] == 1 else "s", s["teams_per_division"]])
		o.set_item_metadata(o.item_count - 1, s)
	o.selected = 0


## Builds the league from the form (or from `overrides`, used by tests) and moves to team choice.
func on_create_league(overrides: Dictionary = {}) -> bool:
	var cfg := FcGenerationConfig.load_default(_data)
	var counts := FcLeagueStructure.valid_team_counts()
	cfg.league_name = (_form["name"] as LineEdit).text if overrides.is_empty() else str(overrides.get("name", cfg.league_name))
	if overrides.is_empty():
		cfg.areas = _to_strings(AREA_CHOICES[(_form["areas"] as OptionButton).selected][1])
		cfg.team_count = counts[(_form["teams"] as OptionButton).selected]
		var structure: Dictionary = (_form["structure"] as OptionButton).get_item_metadata((_form["structure"] as OptionButton).selected)
		cfg.conference_count = structure["conferences"]
		cfg.divisions_per_conference = structure["divisions_per_conference"]
		cfg.cap_preset = CAP_CHOICES[(_form["cap"] as OptionButton).selected][1]
		cfg.sim_era = ERA_CHOICES[(_form["era"] as OptionButton).selected][1]
		cfg.target_games = GAMES_CHOICES[(_form["games"] as OptionButton).selected][1]
		cfg.draft_lottery = (_form["lottery"] as OptionButton).selected == 0
	else:
		cfg.areas = _to_strings(overrides.get("areas", cfg.areas))
		cfg.team_count = int(overrides.get("teams", cfg.team_count))
		cfg.conference_count = int(overrides.get("conferences", cfg.conference_count))
		cfg.divisions_per_conference = int(overrides.get("divisions", cfg.divisions_per_conference))
		cfg.free_agent_count = int(overrides.get("free_agents", cfg.free_agent_count))
	var generator := FcWorldGenerator.new(_data, _defs, cfg)
	var problems := generator.validate()
	if not problems.is_empty():
		_say("Cannot create this league: " + "; ".join(problems))
		return false
	var seed_text := (_form["seed"] as LineEdit).text if overrides.is_empty() else str(overrides.get("seed", "1"))
	var seed_value := int(seed_text) if seed_text.is_valid_int() else hash(seed_text)
	var mode := FcGameState.MODE_OWNER
	if overrides.is_empty() and (_form["mode"] as OptionButton).selected == 1:
		mode = FcGameState.MODE_SPECTATOR
	elif not overrides.is_empty():
		mode = str(overrides.get("mode", mode))
	_pending_state = generator.new_game_state(seed_value, mode, 0)
	show_team_choice()
	return true


func _to_strings(source) -> Array[String]:
	var out: Array[String] = []
	for s in source:
		out.append(str(s))
	return out


# --- choosing a team -----------------------------------------------------------------

func show_team_choice() -> void:
	var box := _reset("Choose Your Team", {"id": "team_choice", "skin": FcModeSkin.FRANCHISE, "back": show_new_league})
	var w := _pending_state.world
	var rows: Array = []
	var ratings := FcPlayerRatings.load_default()
	var looks := {}
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var b: FcTeamBusiness = w.businesses.get_by_id(t.id)
		var best := 0.0
		for pid in t.roster.player_ids:
			best = maxf(best, ratings.overall(w.players.get_by_id(pid)))
		looks[t.id] = FcTeamLook.resolve(FcTeamLook.subject_for_team(w, t))
		rows.append({"id": t.id, "team": t.identity.display_name(city.name), "country": city.country, "pop": city.population, "payroll": w.payroll_of_team(t.id, 2026), "best": roundi(best), "fans": b.fan_interest})
	box.add_child(FcUiTables.label("Pick the franchise you will own. Big markets earn more; small markets are harder but rewarding."))
	var advice := FcUiTables.label("New to the game? Choose a team with a high fan interest and a good best player: a short tutorial will open when you start. You cannot be fired, and you can change teams later.")
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice.custom_minimum_size = Vector2(300, 0)
	box.add_child(advice)
	var table := FcTable.new([
		{"key": "team", "title": "Team", "kind": "custom", "fill": true, "make": func() -> Control: return FcTeamChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcTeamChip).setup(looks[int(row["id"])], str(row["team"]), 28, false)},
		{"key": "country", "title": "Country", "width": 150},
		{"key": "pop", "title": "Metro pop.", "width": 100, "kind": "number", "format": func(v) -> String: return "%.1fM" % (float(v) / 1e6)},
		{"key": "payroll", "title": "Payroll", "width": 96, "kind": "number", "format": func(v) -> String: return FcUiTables.money(int(v))},
		{"key": "best", "title": "Best player", "width": 100, "kind": "rating", "align": "center"},
		{"key": "fans", "title": "Fan interest", "width": 100, "kind": "bar", "max": 100}], rows, {"row_height": 40, "max_rows": 10})
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 40 * 11
	box.add_child(table)
	_form["team_table"] = table
	var row := HBoxContainer.new()
	row.add_child(FcButton.make("Start Game With Selected Team", FcButton.Variant.PRIMARY, func() -> void: on_start_game(_selected_team_id())))
	row.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, show_new_league))
	box.add_child(row)


func _selected_team_id() -> int:
	var table: FcTable = _form.get("team_table")
	if table.selected_id == null:
		return int(table.rows[0]["id"])
	return int(table.selected_id)


func on_start_game(team_id: int) -> void:
	_pending_state.user_team_id = team_id
	controller = FcGameController.resume(_pending_state)
	_pending_state = null
	if controller.state.mode == FcGameState.MODE_OWNER and not preferences.tutorial_done:
		_tutorial_step = 0
	show_dashboard()


# --- the first-time tutorial ---------------------------------------------------------------

## The steps of the tutorial: [{"title", "tab", "text"}] (data/tutorial.json).
func tutorial_steps() -> Array:
	if _tutorial_steps.is_empty():
		var file := FileAccess.open("res://data/tutorial.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_tutorial_steps = parsed.get("steps", [])
	return _tutorial_steps


## Opens the tutorial at its first step (the Help button).
func start_tutorial() -> void:
	_tutorial_step = 0
	_show_tutorial_tab()
	show_dashboard()


## Moves the tutorial by `delta` steps; past the last step it closes and is remembered as seen.
func tutorial_move(delta: int) -> void:
	if _tutorial_step < 0:
		return
	_tutorial_step = maxi(0, _tutorial_step + delta)
	if _tutorial_step >= tutorial_steps().size():
		close_tutorial()
		return
	_show_tutorial_tab()
	show_dashboard()


## Closes the tutorial and remembers that it has been seen, so it does not open again by itself.
func close_tutorial() -> void:
	_tutorial_step = -1
	preferences.mark_tutorial_done()
	if controller != null:
		show_dashboard()


func tutorial_open() -> bool:
	return _tutorial_step >= 0


func _show_tutorial_tab() -> void:
	var steps := tutorial_steps()
	if _tutorial_step >= 0 and _tutorial_step < steps.size():
		var index := TAB_NAMES.find(str(steps[_tutorial_step]["tab"]))
		if index >= 0:
			_last_tab = index


func _tutorial_panel() -> Control:
	var steps := tutorial_steps()
	var step: Dictionary = steps[_tutorial_step]
	var panel := PanelContainer.new()
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	inner.add_child(FcUiTables.label("Tutorial %d of %d: %s" % [_tutorial_step + 1, steps.size(), step["title"]], 18, true))
	var body := FcUiTables.label(str(step["text"]), 15)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(300, 0)
	inner.add_child(body)
	var buttons := HBoxContainer.new()
	if _tutorial_step > 0:
		buttons.add_child(FcUiTables.button("Back", func(): tutorial_move(-1)))
	var last := _tutorial_step == steps.size() - 1
	buttons.add_child(FcUiTables.button("Finish the tutorial" if last else "Next", func(): tutorial_move(1)))
	buttons.add_child(FcUiTables.button("Skip the tutorial", close_tutorial))
	inner.add_child(buttons)
	return panel


# --- dashboard ---------------------------------------------------------------------------

## The full screens reachable through the navigator's back stack (D-077). The Owner dashboard is the root of the Owner stack.
func _register_routes() -> void:
	navigator.register("dashboard", func(_args: Dictionary) -> void: show_dashboard())
	navigator.register("player", func(args: Dictionary) -> void: show_player_page(int(args.get("id", 0))))


## A player's full-page profile (D-077 M4): the dossier at full width, reached from the roster, the HQ and anywhere a player is named.
## Back returns to the screen it was opened from (the navigator's stack). The quick-look dialog (FcPlayerProfile.open_modal) stays for
## places where leaving the screen would lose the player's work (the draft board, a trade being built).
func show_player_page(player_id: int) -> void:
	var w := controller.state.world
	var vm := FcPlayerPresentation.from_player(w, player_id, controller.state.current_season, controller.league_id)
	if vm.is_empty():
		_say("That player no longer exists.")
		return
	var team: FcTeam = w.teams.get_by_id(controller.state.user_team_id)
	var box := _reset(str(vm["name"]), {"id": "player:%d" % player_id, "skin_props": FcModeSkin.franchise(team.branding.primary_color if team != null else ""),
		"back": navigator.stack_back(), "header": {"kind": "none"}})
	var bar := HBoxContainer.new()
	bar.add_child(FcButton.make("Back", FcButton.Variant.GHOST, func() -> void: go_back(), "chevron-left"))
	box.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var profile := FcPlayerProfile.new().setup(vm, layout.is_mobile())
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.name = "PlayerPage"
	scroll.add_child(profile)
	box.add_child(scroll)


func show_dashboard() -> void:
	navigator.set_root("dashboard")
	var s := controller.season()
	var team: FcTeam = controller.state.world.teams.get_by_id(controller.state.user_team_id)
	var primary: String = team.branding.primary_color if team != null else ""
	var box := _reset(_team_name(controller.state.user_team_id), {"id": "dashboard", "skin_props": FcModeSkin.franchise(primary), "back": _confirm_leave_to_menu,
		"header": {"kind": "none"}})
	var phase := controller.phase()
	var phase_text: String = {"regular_season": "Regular season", "playoffs": "Playoffs", "season_complete": "Season complete", "offseason": "Offseason: free agency is open to you first", "draft": "The draft", "meeting": "The owners are meeting", "expansion": "Expansion draft: choose your protected players"}[phase]
	var mode_text := "Owner" if controller.state.mode == FcGameState.MODE_OWNER else "Spectator"
	# the franchise hero: crest, name, the season and date, and the record at a glance (D-077 M3)
	var record := controller.user_record()
	var pills: Array = [{"label": "Record", "value": "%d-%d" % [record["wins"], record["losses"]]}, {"label": "Rank", "value": "#%d" % record["rank"]}]
	if str(record["streak"]) != "-":
		pills.append({"label": "Streak", "value": str(record["streak"])})
	var hero := FcTeamHeader.new().setup({"look": FcTeamLook.resolve(FcTeamLook.subject_for_team(controller.state.world, team)) if team != null else {},
		"name": _team_name(controller.state.user_team_id), "eyebrow": "Franchise headquarters  ·  %s" % mode_text,
		"subtitle": "Season %d-%02d  ·  %s  ·  %s" % [s.year, (s.year + 1) % 100, controller.state.current_date.to_iso(), phase_text], "pills": pills})
	hero.custom_minimum_size.y = 120
	hero.name = "FranchiseHeader"
	box.add_child(hero)
	var info := FcUiTables.label("%s    Season %d-%02d    %s    Mode: %s" % [controller.state.current_date.to_iso(), s.year, (s.year + 1) % 100, phase_text, mode_text], FcUiTokens.TYPE_SMALL)
	info.theme_type_variation = "MutedLabel"
	box.add_child(info)
	var actions := HFlowContainer.new()   # wraps onto a second line instead of forcing the window wider (Large text at 800 px, D6)
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	actions.name = "AdvanceBar"
	match phase:
		FcGameController.PHASE_REGULAR:
			if controller.next_user_game() != null:
				actions.add_child(FcButton.make("Game day", FcButton.Variant.PRIMARY, on_game_day))
			actions.add_child(FcUiTables.button("Next Day", func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Next Week", func(): on_advance(7)))
			actions.add_child(FcUiTables.button("Next Month", func(): run_with_loading("Playing a month of games...", func(): on_advance(30))))
			actions.add_child(FcUiTables.button("To End of Regular Season", func(): run_with_loading("Simulating the regular season...", on_sim_regular)))
		FcGameController.PHASE_PLAYOFFS:
			actions.add_child(FcButton.make("Next Playoff Day", FcButton.Variant.PRIMARY, func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Play All Playoffs", func(): run_with_loading("Playing the playoffs...", on_sim_playoffs)))
		FcGameController.PHASE_MEETING:
			actions.add_child(FcButton.make("Close the meeting and count the votes", FcButton.Variant.PRIMARY, on_close_meeting))
		FcGameController.PHASE_EXPANSION:
			actions.add_child(FcButton.make("Run the expansion draft", FcButton.Variant.PRIMARY, on_run_expansion))
		FcGameController.PHASE_DRAFT:
			actions.add_child(FcButton.make("Let the staff finish the draft", FcButton.Variant.PRIMARY, func(): run_with_loading("Running the draft...", on_draft_auto)))
		FcGameController.PHASE_OFFSEASON:
			actions.add_child(FcButton.make("Finish Offseason and Start Next Season", FcButton.Variant.PRIMARY, func(): run_with_loading("Starting the next season...", on_next_season)))
		_:
			if controller.state.mode == FcGameState.MODE_OWNER:
				actions.add_child(FcButton.make("Begin Offseason (draft, contracts, free agency)", FcButton.Variant.PRIMARY, on_next_season))
			else:
				actions.add_child(FcButton.make("Start Next Season (offseason)", FcButton.Variant.PRIMARY, on_next_season))
	actions.add_child(FcUiTables.button("Save", on_save))
	if controller.state.mode == FcGameState.MODE_OWNER:
		actions.add_child(FcUiTables.button("Help", start_tutorial))
	actions.add_child(FcUiTables.button("Main Menu", show_main_menu))
	box.add_child(actions)
	if _tutorial_step >= 0 and _tutorial_step < tutorial_steps().size():
		box.add_child(_tutorial_panel())
	_tabs = FcTabPages.new()
	for name in TAB_NAMES:
		var page := build_tab(name)
		_tabs.add_page(page if page is ScrollContainer else _scrollable(page), name)   # a tall tab scrolls instead of running off a short window
	box.add_child(_tabs)
	_tabs.current_tab = clampi(_last_tab, 0, TAB_NAMES.size() - 1)
	_tabs.tab_changed.connect(func(i): _last_tab = i)


func on_advance(days: int) -> void:
	controller.advance_days(days)
	show_dashboard()


## The game-day preview of the user's next game (Owner). "Play this game" plays up to it and opens its summary and replay.
func on_game_day() -> void:
	var model := FcGameDay.for_owner(controller)
	if model.is_empty():
		_say("There is no regular-season game left to preview.")
		return
	FcGameDay.open(self, model, controller.state.world, play_owner_game_day)


func play_owner_game_day() -> void:
	var game := controller.next_user_game()
	if game == null:
		return
	var day := game.day
	controller.advance_days(controller.days_to_next_user_game())
	show_dashboard()
	for entry in controller.season().recent_boxes:
		if int(entry["day"]) == day and int(entry["series"]) == 0:
			FcPostGame.open(self, FcPostGame.for_owner(controller, entry["box"], entry.get("events", {})))


func on_sim_regular() -> void:
	controller.sim_regular_season()
	show_dashboard()


func on_sim_playoffs() -> void:
	controller.sim_playoffs()
	show_dashboard()
	var champion := controller.season().champion_id
	_say("Champions: %s" % _team_name(champion))
	if champion == controller.state.user_team_id:
		FcCelebration.show_on(host.overlay, "Champions!", _team_name(champion))


## One button, three jobs. Owner Mode: first press (season over) warns about players whose
## contracts end, then begins the offseason (draft and re-signing done, free agency open to
## you); the next press lets the AI teams sign players and starts the new season.
## Spectator mode: one press does everything.
func on_next_season() -> void:
	if controller.state.mode == FcGameState.MODE_OWNER and controller.state.offseason_stage == 0 and not controller.meeting_held() and controller.open_meeting():
		controller.autosave(saves)
		_last_tab = FcApp.TAB_NAMES.find("Meeting")
		show_dashboard()
		_say("The league owners are meeting. Look through the proposals on the Meeting tab, vote on the ones you care about, then close the meeting. Press the button again afterwards to begin the offseason.")
		return
	if controller.state.mode == FcGameState.MODE_OWNER and controller.state.offseason_stage == 0 and controller.phase() != FcGameController.PHASE_PLAYOFFS and controller.phase() != FcGameController.PHASE_REGULAR and not _confirm_next_season:
		var leaving := controller.expiring_players().filter(func(e): return not e["agreed"])
		var leaving_staff := controller.expiring_staff().filter(func(e): return not e["agreed"])
		if not leaving.is_empty() or not leaving_staff.is_empty():
			var names: Array[String] = []
			for e in leaving:
				names.append(e["player"].identity.full_name())
			for e in leaving_staff:
				names.append("%s (%s)" % [e["member"].identity.full_name(), FcStaffRole.display_name(e["role"])])
			_confirm_next_season = true
			_say("These contracts end and they will LEAVE unless you extend them (players on the Roster tab, staff on the Staff tab): %s. Press Start Next Season again to let them go." % ", ".join(names))
			return
	_confirm_next_season = false
	if controller.state.mode == FcGameState.MODE_OWNER and controller.state.offseason_stage == 0:
		var first := controller.begin_offseason()
		controller.autosave(saves)
		_last_tab = FcApp.TAB_NAMES.find("Draft")
		show_dashboard()
		var gm_notes := " ".join(controller.gm_log())
		if controller.phase() == FcGameController.PHASE_DRAFT:
			_say("Offseason: %d players retired. The draft has begun: scout the board on the Draft tab and pick when it is your turn. %s" % [first["retired"], gm_notes])
		else:
			_last_tab = FcApp.TAB_NAMES.find("Market")
			show_dashboard()
			_say("Offseason: %d players retired. The draft is done and the free-agency window is open. %s" % [first["retired"], gm_notes])
		return
	var report := controller.start_next_season()
	controller.autosave(saves)
	show_dashboard()
	_say("New season. The AI teams signed %d free agents." % report["signed"] if not report.has("retired") else "New season. Offseason: %d retired, %d drafted, %d free agents signed, %d re-signed." % [report["retired"], report["drafted"], report["signed"], report["re_signed"]])


## Counts the votes of the owners' meeting and shows what the league decided.
func on_close_meeting() -> void:
	var results := controller.close_meeting()
	var lines: Array[String] = []
	for r in results:
		lines.append("%s: %s (%d for, %d against, %d needed)" % [r["title"], "PASSED" if r["enacted"] else "failed", r["yes"], r["no"], r["needed"]])
	controller.autosave(saves)
	_last_tab = FcApp.TAB_NAMES.find("Meeting")
	show_dashboard()
	_say("Meeting closed. " + " | ".join(lines))


## Runs the approved expansion's draft and tells the owner what it cost.
func on_run_expansion() -> void:
	var result := controller.run_expansion_draft()
	controller.autosave(saves)
	_last_tab = FcApp.TAB_NAMES.find("Meeting")
	show_dashboard()
	var lost: Array[String] = []
	for entry in result.get("lost", []):
		lost.append("%s (to %s)" % [controller.state.world.player_name(entry[0]), _team_name(entry[1])])
	_say("The league now has %d teams. %s Every existing owner received an expansion fee of %s. Press Begin Offseason to continue." % [result.get("size", 0), ("You lost " + ", ".join(lost) + ".") if not lost.is_empty() else "None of your players was taken.", FcUiTables.money(result.get("fee_each", 0))])


## The staff finishes the draft for the user; the free-agency window opens.
func on_draft_auto() -> void:
	controller.draft_auto_rest()
	controller.autosave(saves)
	_last_tab = FcApp.TAB_NAMES.find("Market")
	show_dashboard()
	_say("The draft is over. Sign free agents on the Market tab before the AI teams do, then finish the offseason.")


func on_save() -> void:
	var result := saves.save("slot_1", controller.state, _team_name(controller.state.user_team_id))
	_say("Saved to slot_1." if result.is_ok() else "Save failed: " + result.message)


func _team_name(team_id: int) -> String:
	var w := controller.state.world if controller != null else _pending_state.world
	var t: FcTeam = w.teams.get_by_id(team_id)
	if t == null:
		return "-"
	return t.identity.display_name(w.cities.get_by_id(t.city_id).name)


## What the Owner tabs in src/ui/owner need from the app (the controller and the few things only the app can do). Rebuilt when the game changes.
func _owner_ctx() -> FcOwnerContext:
	if _owner_context == null or _owner_context.controller != controller:
		_owner_context = FcOwnerContext.new(controller, _say, show_dashboard,
			func(entry: Dictionary) -> void: FcPostGame.open(self, FcPostGame.for_owner(controller, entry["box"], entry.get("events", {}))),
			func(player_id: int) -> void: navigator.open("player", {"id": player_id}))
		_owner_context.after_draft = _after_draft_action
		_owner_context.open_tonight = func() -> void: FcTonight.open(self, controller)
		_owner_context.open_game = func(_game_id: int) -> void: on_game_day()
	return _owner_context


## Builds one tab's content. Public so tests can open every tab.
func build_tab(tab_name: String) -> Control:
	match tab_name:
		"Overview": return _scrollable(_tab_overview())
		"Standings": return _tab_standings()
		"Schedule": return _tab_schedule()
		"Roster": return _tab_roster()
		"Finances": return FcOwnerFinances.build(_owner_ctx())
		"Staff": return FcOwnerStaff.build(_owner_ctx())
		"Draft": return FcOwnerDraft.build(_owner_ctx())
		"Meeting": return FcOwnerMeetingTab.build(_owner_ctx())
		"Market": return FcOwnerMarket.build(_owner_ctx())
		"Trades": return FcOwnerTrades.build(_owner_ctx())
		"History": return _tab_history()
		"News": return FcOwnerNews.build(_owner_ctx())
	return FcOwnerLeague.build(_owner_ctx())


# --- tabs ----------------------------------------------------------------------------------

## The Hall of Fame and single-season records.
## The History tab: the franchise's story, retired numbers, rivalries, storylines and the Hall of Fame (see FcOwnerHistory).
func _tab_history() -> Control:
	return FcOwnerHistory.build(_owner_ctx(), func() -> Control: return FcOwnerRecords.build(_owner_ctx()))


## After a pick: back to the offseason window if the draft ended, otherwise refresh the board.
func _after_draft_action() -> void:
	var message := _message.text if _message != null else ""
	if controller.phase() == FcGameController.PHASE_OFFSEASON:
		controller.autosave(saves)
		_last_tab = FcApp.TAB_NAMES.find("Market")
		show_dashboard()
		_say(message + " The draft is over: sign free agents on the Market tab before the AI teams do, then finish the offseason.")
		return
	show_dashboard()
	_say(message)


## Wraps a long page so it can be scrolled instead of running off the bottom of the window.
func _scrollable(content: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _tab_overview() -> Control:
	return FcOwnerOverview.build(_owner_ctx())


func _tab_standings() -> Control:
	return FcOwnerStandings.build(_owner_ctx())


func _tab_schedule() -> Control:
	return FcOwnerSchedule.build(_owner_ctx())


## The stored box score entry ({day, series, box}) of a recently played game of the owner's team, or {}.
func _stored_box(day: int, series: int) -> Dictionary:
	for entry in controller.season().recent_boxes:
		if int(entry["day"]) == day and int(entry["series"]) == series:
			return entry
	return {}


## The box score of a recently played game of the owner's team as text, or "" if none is stored.
func box_score_text(day: int, series: int) -> String:
	for entry in controller.season().recent_boxes:
		if int(entry["day"]) == day and int(entry["series"]) == series:
			var box := FcBoxScore.from_dict(entry["box"])
			var by_period := ""
			for side in 2:
				var parts: Array = []
				for v in box.period_scores[side]:
					parts.append(str(v))
				by_period += "%s: %s\n" % [box.abbreviations[side], "  ".join(parts)]
			return "%s\n%s\n%s\n\n%s" % [box.summary(), by_period, box.table(0), box.table(1)]
	return ""


## A full profile of one player as text: bio, body, ratings, personality, tendencies,
## contract and career statistics.
func player_profile_text(player_id: int) -> String:
	var w := controller.state.world
	var p: FcPlayer = w.players.get_by_id(player_id)
	if p == null:
		return ""
	var year := controller.state.current_season
	var lines: Array[String] = []
	lines.append("%s    %s    age %d    %d cm, %d kg    %s" % [p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(year, 7, 1)), p.physical.height_cm, p.physical.weight_kg, p.identity.country])
	var team := w.team_of_player(player_id)
	lines.append("Team: %s    Overall %d    Potential %d    Peak age %d" % [w.team_display_name(team.id) if team != null else "free agent", roundi(FcPlayerRatings.load_default().overall(p)), p.development.potential, p.development.peak_age])
	if p.games_out > 0:
		lines.append("OUT %d games: %s" % [p.games_out, p.injury])
	var c := w.active_contract_of(player_id)
	if c != null:
		lines.append("Contract: %s a year through %d (%d years left)" % [FcUiTables.money(c.salary_for(year)), c.end_season(), maxi(0, c.end_season() - year + 1)])
	for catalog_pair in [["Basketball ratings", w.definitions.attributes, p.attributes], ["Personality", w.definitions.personality, p.personality], ["Tendencies", w.definitions.tendencies, p.tendencies]]:
		lines.append("")
		lines.append(catalog_pair[0])
		var catalog: FcAttributeCatalog = catalog_pair[1]
		var values: FcAttributeSet = catalog_pair[2]
		var line := ""
		var count := 0
		for key in catalog.keys():
			line += "%-24s %3d    " % [catalog.get_def(key).display_name, values.get_value(key)]
			count += 1
			if count % 3 == 0:
				lines.append("  " + line)
				line = ""
		if line != "":
			lines.append("  " + line)
	lines.append("")
	lines.append("Career")
	lines.append("  %-8s %-6s %4s %5s %5s %5s %5s" % ["Season", "Team", "GP", "MPG", "PPG", "RPG", "APG"])
	for row in w.careers.get(player_id, []):
		var t: FcTeam = w.teams.get_by_id(row[1])
		var gp: int = maxi(1, row[2])
		lines.append("  %-8s %-6s %4d %5.1f %5.1f %5.1f %5.1f" % ["%d-%02d" % [row[0], (row[0] + 1) % 100], t.identity.abbreviation if t != null else "?", row[2], row[3] / 60.0 / gp, float(row[4]) / gp, float(row[11] + row[12]) / gp, float(row[13]) / gp])
	var totals := w.career_totals(player_id)
	if totals["seasons"] > 0:
		lines.append("  Career: %d games, %d points, %d rebounds, %d assists" % [totals["gp"], totals["points"], totals["rebounds"], totals["ast"]])
	return "\n".join(lines)


func _show_text_popup(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.min_size = Vector2i(900, 600)
	var scroll := ScrollContainer.new()
	var label := Label.new()
	label.text = text
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	label.add_theme_font_override("font", font)
	scroll.add_child(label)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()


func _tab_roster() -> Control:
	return FcOwnerRoster.build(_owner_ctx())


func _player_name(player_id: int) -> String:
	var p: FcPlayer = controller.state.world.players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"


## Faces age with the game: every screen is built with the current date of the running game as the date ages are counted from (UI only; no game data is read or written).
func _sync_player_ages() -> void:
	var state: FcGameState = null
	if career != null and career.state != null:
		state = career.state
	elif controller != null and controller.state != null:
		state = controller.state
	FcPlayerPresentation.reference_date = state.current_date if state != null else null
