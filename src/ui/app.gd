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
## Published content (Creator Studio releases, D-042): loaded at start-up; falls back safely and reports why.
var content: FcContentService
## Dynasty Mode: the controller screens use and the screens' shell (built in setup).
var dynasty: FcDynastyController
var dynasty_ui: FcDynastyUi
## The open step of the tutorial (-1 = closed). Kept here because the dashboard is rebuilt often.
var _tutorial_step: int = -1
var _tutorial_steps: Array = []

var _defs := FcDefinitionSet.load_default()
var _data := FcGenerationData.load_default()
var _root: VBoxContainer
var _content: Control
var _pending_state: FcGameState
var _tabs: TabContainer
## The team the user is talking to in the Trades tab (0 = first other team).
var _trade_partner: int = 0
## Set after the warning about expiring contracts; a second press starts the next season.
var _confirm_next_season: bool = false
## The proposal that was selected on the Meeting tab (kept when the screen is rebuilt after lobbying).
var _last_meeting_item: int = 0
## The page of the Finances tab that was open (kept when the screen is rebuilt).
var _last_finance_page: int = 0
## The open page of the Staff and Trades tabs.
var _last_staff_page: int = 0
var _last_trade_page: int = -1
var _last_tab := 0
var _form := {}
## The status line of the current screen. Hidden: messages are shown as toasts (notifier); the text stays here so tests, tools
## and later accessibility features can read the latest message.
var _message: Label
## The shell (docs/UI_POLISH_PLAN.md, Phase 3): the frame with the backdrop, the dialog and toast layers.
var host: FcScreenHost
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
	if OS.get_cmdline_user_args().has("--selftest"):
		call_deferred("_run_self_test")


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
	FcMotion.reduced = preferences.reduce_motion
	layout.mobile_os = OS.has_feature("mobile")
	layout.touch_available = DisplayServer.is_touchscreen_available()
	layout.override = preferences.layout_override
	layout.changed.connect(_on_layout_changed)
	resized.connect(func() -> void: layout.update(size))
	FcUiTokens.touch_mode = layout.is_mobile()
	apply_text_size(preferences.text_size)
	content = FcContentService.new(preferences, _defs)
	dynasty = FcDynastyController.new(content, _defs)
	dynasty_ui = FcDynastyUi.new(self, dynasty)
	show_main_menu()
	layout.update(size)


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
	if animate:
		host.transition_in(_root)
	return box


func _add_header(title: String, header: Dictionary) -> void:
	match str(header.get("kind", "plain")):
		"wordmark":
			_root.add_child(FcUiTables.label(title, FcUiTokens.TYPE_DISPLAY_XL, true))
			var tagline := FcUiTables.label(str(header.get("tagline", "")), FcUiTokens.TYPE_BODY)
			tagline.theme_type_variation = "MutedLabel"
			tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_root.add_child(tagline)
		"letterhead":
			var letterhead := FcLetterhead.new()
			letterhead.setup(title, str(header.get("subtitle", "")), str(header.get("abbr", "")), str(header.get("primary", "")), str(header.get("secondary", "")))
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
		host.set_safe_margins(FcLayoutProfile.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size()))
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
	return navigator.go_back()


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
	var box := _reset("FULL COURT", {"id": "menu", "rebuild": show_main_menu, "header": {"kind": "wordmark", "tagline": "Basketball management simulation. Choose how you want to play."}})
	if content != null and content.report.is_degraded():
		var warn := FcUiTables.label(content.report.summary(), FcUiTokens.TYPE_SMALL)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(warn)
	var modes := HFlowContainer.new()
	modes.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	modes.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	for entry in [
			["Owner Mode", "Run every part of a franchise for up to 50 seasons: money, people, players, the draft, the league's rules.", show_new_league, "Available", FcModeSkin.FRANCHISE, FcStatusChip.Tone.INFO],
			["Career Mode", "Create one player and take them through a career. Draft, contracts, teams, rivalries.", show_career_home, "Playable", FcModeSkin.BROADCAST, FcStatusChip.Tone.SUCCESS],
			["Dynasty Mode", "Collect fictional player cards, open packs, build a 13-player roster and compete in challenges and tournaments.", show_dynasty_home, "Playable", FcModeSkin.COLLECTIBLE, FcStatusChip.Tone.SUCCESS]]:
		var card := FcPanel.new("", FcPanel.Variant.RAISED)
		card.set_accent(FcModeSkin.resolve(entry[4])["accent"])
		card.custom_minimum_size.x = 260
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add(FcStatusChip.make(entry[3], entry[5]))
		card.add(FcUiTables.label(entry[0], FcUiTokens.TYPE_H1, true))
		var blurb := FcUiTables.label(entry[1], FcUiTokens.TYPE_SMALL + 1)
		blurb.theme_type_variation = "MutedLabel"
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add(blurb)
		card.add(FcButton.make(entry[0], FcButton.Variant.PRIMARY, entry[2]))
		modes.add_child(card)
	box.add_child(modes)
	var slots := saves.list_slots()
	if not slots.is_empty():
		box.add_child(FcButton.make("Continue (latest save)", FcButton.Variant.SECONDARY, on_continue))
		box.add_child(FcUiTables.label("Saved games", FcUiTokens.TYPE_H3, true))
		var rows: Array = []
		for m in slots:
			rows.append([m.slot_id, m.label, m.team_name, "%d-%02d" % [m.season, (m.season + 1) % 100], m.mode, m.saved_at, "ok" if m.readable else "damaged"])
		var table := FcDataTable.build(["Slot", "Name", "Team", "Season", "Mode", "Saved", "Status"], rows, [])
		if table is Tree:
			table.custom_minimum_size.y = mini(rows.size(), 5) * 30 + 36
		box.add_child(table)
		var row := HFlowContainer.new()
		var picker := FcDropdown.new()
		var names: Array = []
		for m in slots:
			names.append(m.slot_id)
		picker.set_items(names)
		_form["slot"] = picker
		row.add_child(picker)
		row.add_child(FcButton.make("Load", FcButton.Variant.SECONDARY, on_load_selected))
		row.add_child(FcButton.make("Delete", FcButton.Variant.DESTRUCTIVE, request_delete_selected))
		box.add_child(row)
	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	footer.add_child(FcButton.make("Settings", FcButton.Variant.GHOST, show_settings, "settings"))
	footer.add_child(FcButton.make("About, licenses and logs", FcButton.Variant.GHOST, show_about, "info"))
	if OS.has_feature("editor") or OS.get_cmdline_user_args().has("--gallery"):
		footer.add_child(FcButton.make("Component gallery (development only)", FcButton.Variant.GHOST, show_gallery, "layers"))
	footer.add_child(FcButton.make("Quit", FcButton.Variant.GHOST, func(): get_tree().quit()))
	box.add_child(footer)


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
	var text := FcUiTables.label("Create one player (name, body, position, strengths) and take them through a career of about 20 seasons: scouting and the draft, decisions, contracts, relationships, rivalries, sponsorships and a legacy. You reach your potential by choosing which skills to raise.

See docs/CAREER_MODE_PLAN.md.", 16)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(400, 0)
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Create a player", show_career_creator))
	row.add_child(FcUiTables.button("Back to the main menu", show_main_menu))
	box.add_child(row)


## The player creator (FcCareerCreator). A valid build makes the player and opens the Career Hub.
func show_career_creator() -> void:
	var box := _reset("Career Mode: create your player", {"id": "career_creator", "skin": FcModeSkin.BROADCAST, "back": show_career_home, "rebuild": show_career_creator})
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
	box.add_child(FcUiTables.label("%s%s   %s   Age %d   %d cm, %d kg, wingspan %d cm   Team: %s" % [
		card["position"], "/" + card["secondary"] if card["secondary"] != "" else "", card["archetype"], card["age"],
		card["height_cm"], card["weight_kg"], card["wingspan_cm"], card["team"]], 16))
	var progress := career.progress()
	box.add_child(FcUiTables.label("Overall %d    Potential %d (your ceiling)    Level %d    XP %d (%d of %d to the next level)    Development points %d    Skill points %d" % [
		card["overall"], card["potential"], progress["level"], progress["xp"], progress["into_level"], progress["needed"], progress["development_points"], progress["skill_points"]], 17, true))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_tab := _career_card_tab(card)
	card_tab.name = "Card"
	tabs.add_child(card_tab)
	var season_tab := _career_season_tab()
	season_tab.name = "Season"
	tabs.add_child(season_tab)
	var develop_tab := _career_develop_tab(card, progress)
	develop_tab.name = "Develop"
	tabs.add_child(develop_tab)
	var skills_tab := _career_skills_tab(progress)
	skills_tab.name = "Skills"
	tabs.add_child(skills_tab)
	tabs.current_tab = clampi(_last_career_tab, 0, 3)
	tabs.tab_changed.connect(func(i): _last_career_tab = i)
	box.add_child(tabs)
	box.add_child(FcUiTables.label("Career id %s. Saved to slot career_1; load it from the main menu. The calendar and games arrive in the next phase." % card["profile_id"], 14))
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Save", func():
		var r := career.save(saves)
		_say("Saved." if r.is_ok() else "Save failed: " + r.message)))
	row.add_child(FcUiTables.button("Main Menu", show_main_menu))
	box.add_child(row)


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
		for game in result["games"]:
			xp += int(game["xp"])
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
		box.add_child(_career_history_table())
		return box
	if not career.is_signed():
		box.add_child(FcUiTables.label("You do not have a team yet. Choose one, or let the draft decide.", 16, true))
		var outlook := career.draft_outlook()
		box.add_child(FcUiTables.label("Scouting report: overall %d, potential %d. Projected pick %d of %d, to %s. %s" % [outlook["overall"], outlook["potential"], outlook["pick"], outlook["picks"], career.state.world.team_display_name(outlook["team_id"]), outlook["note"]], 15))
		var row := HBoxContainer.new()
		var picker := OptionButton.new()
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
	box.add_child(FcUiTables.table(["Opponent", "", "Score", "Min", "Pts", "Reb", "Ast", "XP", "Milestones"], rows, [0, 30, 70, 40, 40, 40, 40, 50, 0]))
	box.add_child(FcUiTables.label("Career history", 16, true))
	box.add_child(_career_history_table())
	return box


func _career_history_table() -> Control:
	var history: Array = []
	for h in career.profile().history:
		history.append(["%d-%02d" % [h["year"], (int(h["year"]) + 1) % 100], career.state.world.team_display_name(int(h["team_id"])), h["games"], "%.1f" % h["points"], "%.1f" % h["rebounds"], "%.1f" % h["assists"], "%d-%d" % [h["wins"], h["losses"]]])
	return FcUiTables.table(["Season", "Team", "GP", "PPG", "RPG", "APG", "Team record"], history, [80, 0, 50, 60, 60, 60, 100])


## The role request: the coach may refuse what the player has not earned.
func _career_role_row() -> Control:
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.label("Role"))
	var role := OptionButton.new()
	for entry in [["Coach decides", "auto"], ["Starter", "starter"], ["Bench", "bench"]]:
		role.add_item(entry[0])
		role.set_item_metadata(role.item_count - 1, entry[1])
	role.selected = ["auto", "starter", "bench"].find(career.profile().role)
	role.tooltip_text = "Ask to start or to come off the bench. The coach refuses a start you have not earned."
	row.add_child(role)
	row.add_child(FcUiTables.label("  Minutes"))
	var minutes := OptionButton.new()
	for entry in [["Fewer", -1], ["Normal", 0], ["More", 1]]:
		minutes.add_item(entry[0])
		minutes.set_item_metadata(minutes.item_count - 1, entry[1])
	minutes.selected = career.profile().minutes_pref + 1
	minutes.tooltip_text = "Playing more needs some reputation."
	row.add_child(minutes)
	row.add_child(FcUiTables.label("  Style"))
	var usage := OptionButton.new()
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


func _career_card_tab(card: Dictionary) -> Control:
	var columns := HBoxContainer.new()
	for group in card["groups"]:
		var rows: Array = []
		for row in group["rows"]:
			rows.append([row[0], row[1], row[2]])
		var part := VBoxContainer.new()
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.add_child(FcUiTables.label(group["name"], 16, true))
		part.add_child(FcUiTables.table(["Attribute", "Now", "Can reach"], rows, [0, 50, 70]))
		columns.add_child(part)
	return columns


func _career_develop_tab(_card: Dictionary, progress: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var view := career.development_view()
	var pot: Dictionary = view["progress"]
	var head := FcUiTables.label("Overall %d of your %d potential%s    Development points: %d" % [pot["overall"], pot["potential"], "  (at your ceiling)" if pot["at_potential"] else "  (%d to go)" % pot["to_go"], progress["development_points"]], 17, true)
	head.tooltip_text = "Potential is the highest overall you can reach. You get there by choosing which skills to raise: skills that count more in overall give more per point."
	box.add_child(head)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = pot["fraction"] * 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 14)
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
	var part := OptionButton.new()
	var appearance: Dictionary = FcBuildRules.rules()["appearance"]
	for key in appearance:
		part.add_item(str(key).replace("_", " "))
		part.set_item_metadata(part.item_count - 1, key)
	var option := OptionButton.new()
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
	box.add_child(FcUiTables.table(["Badge", "Tree", "Cost", "Status", "What it does"], rows, [170, 100, 50, 300, 0]))
	var pick := OptionButton.new()
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


## The About screen: version, the engine's licenses (the MIT notice the engine requires in every game made with it) and
## shortcuts to the folders with logs and saves, so a player can send a log when something goes wrong.
func show_about() -> void:
	var box := _reset("About Full Court", {"id": "about", "back": show_main_menu, "rebuild": show_about})
	box.add_child(FcUiTables.label("Full Court %s: a basketball management simulation. Original teams, players and staff; real cities." % FcVersion.GAME_VERSION, 16))
	if content != null:
		box.add_child(FcUiTables.label(content.report.summary(), 14))
	var info := Engine.get_version_info()
	box.add_child(FcUiTables.label("Made with the Godot Engine %s (MIT license). Copyright (c) 2014-present Godot Engine contributors, Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.  https://godotengine.org" % info.get("string", ""), 14))
	var text := TextEdit.new()
	text.editable = false
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = Engine.get_license_text()
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Open the logs folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://logs"))))
	row.add_child(FcUiTables.button("Open the saves folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))
	row.add_child(FcUiTables.button("Open the content folder", func():
		FcSafeFile.make_dir(preferences.effective_content_root())
		OS.shell_open(ProjectSettings.globalize_path(preferences.effective_content_root()))))
	row.add_child(FcUiTables.button("Back", show_main_menu))
	box.add_child(row)
	box.add_child(FcUiTables.label("If something goes wrong, send the newest file in the logs folder together with a description. Nothing is sent automatically.", 14))


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
	var o := OptionButton.new()
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
	var ids: Array[int] = []
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var b: FcTeamBusiness = w.businesses.get_by_id(t.id)
		var best := 0.0
		for pid in t.roster.player_ids:
			best = maxf(best, FcPlayerRatings.load_default().overall(w.players.get_by_id(pid)))
		rows.append([t.identity.display_name(city.name), city.country, "%.1fM" % (city.population / 1e6), FcUiTables.money(w.payroll_of_team(t.id, 2026)), "%d" % roundi(best), b.fan_interest])
		ids.append(t.id)
	box.add_child(FcUiTables.label("Pick the franchise you will own. Big markets earn more; small markets are harder but rewarding."))
	var advice := FcUiTables.label("New to the game? Choose a team with a high fan interest and a good best player: a short tutorial will open when you start. You cannot be fired, and you can change teams later.")
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice.custom_minimum_size = Vector2(300, 0)
	box.add_child(advice)
	var table := FcUiTables.table(["Team", "Country", "Metro pop.", "Payroll", "Best player", "Fan interest"], rows, [0, 150, 90, 90, 90, 90])
	box.add_child(table)
	table.set_meta("team_ids", ids)
	_form["team_table"] = table
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Start Game With Selected Team", func(): on_start_game(_selected_team_id())))
	row.add_child(FcUiTables.button("Back", show_new_league))
	box.add_child(row)


func _selected_team_id() -> int:
	var table: Tree = _form.get("team_table")
	var ids: Array = table.get_meta("team_ids")
	var item := table.get_selected()
	if item == null:
		return ids[0]
	return ids[item.get_index()]


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

func show_dashboard() -> void:
	var s := controller.season()
	var team: FcTeam = controller.state.world.teams.get_by_id(controller.state.user_team_id)
	var primary: String = team.branding.primary_color if team != null else ""
	var box := _reset(_team_name(controller.state.user_team_id), {"id": "dashboard", "skin_props": FcModeSkin.franchise(primary), "back": _confirm_leave_to_menu,
		"header": {"kind": "letterhead", "subtitle": "Season %d-%02d   %s" % [s.year, (s.year + 1) % 100, "Owner" if controller.state.mode == FcGameState.MODE_OWNER else "Spectator"],
			"abbr": team.identity.abbreviation if team != null else "", "primary": primary, "secondary": team.branding.secondary_color if team != null else ""}})
	var phase := controller.phase()
	var info := FcUiTables.label("%s    Season %d-%02d    %s    Mode: %s" % [
		controller.state.current_date.to_iso(), s.year, (s.year + 1) % 100,
		{"regular_season": "Regular season", "playoffs": "Playoffs", "season_complete": "Season complete", "offseason": "Offseason: free agency is open to you first", "draft": "The draft", "meeting": "The owners are meeting", "expansion": "Expansion draft: choose your protected players"}[phase],
		"Owner" if controller.state.mode == FcGameState.MODE_OWNER else "Spectator"], 16)
	box.add_child(info)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	match phase:
		FcGameController.PHASE_REGULAR:
			actions.add_child(FcUiTables.button("Next Day", func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Next Week", func(): on_advance(7)))
			actions.add_child(FcUiTables.button("Next Month", func(): run_with_loading("Playing a month of games...", func(): on_advance(30))))
			actions.add_child(FcUiTables.button("To End of Regular Season", func(): run_with_loading("Simulating the regular season...", on_sim_regular)))
		FcGameController.PHASE_PLAYOFFS:
			actions.add_child(FcUiTables.button("Next Playoff Day", func(): on_advance(1)))
			actions.add_child(FcUiTables.button("Play All Playoffs", func(): run_with_loading("Playing the playoffs...", on_sim_playoffs)))
		FcGameController.PHASE_MEETING:
			actions.add_child(FcUiTables.button("Close the meeting and count the votes", on_close_meeting))
		FcGameController.PHASE_EXPANSION:
			actions.add_child(FcUiTables.button("Run the expansion draft", on_run_expansion))
		FcGameController.PHASE_DRAFT:
			actions.add_child(FcUiTables.button("Let the staff finish the draft", func(): run_with_loading("Running the draft...", on_draft_auto)))
		FcGameController.PHASE_OFFSEASON:
			actions.add_child(FcUiTables.button("Finish Offseason and Start Next Season", func(): run_with_loading("Starting the next season...", on_next_season)))
		_:
			if controller.state.mode == FcGameState.MODE_OWNER:
				actions.add_child(FcUiTables.button("Begin Offseason (draft, contracts, free agency)", on_next_season))
			else:
				actions.add_child(FcUiTables.button("Start Next Season (offseason)", on_next_season))
	actions.add_child(FcUiTables.button("Save", on_save))
	if controller.state.mode == FcGameState.MODE_OWNER:
		actions.add_child(FcUiTables.button("Help", start_tutorial))
	actions.add_child(FcUiTables.button("Main Menu", show_main_menu))
	box.add_child(actions)
	if _tutorial_step >= 0 and _tutorial_step < tutorial_steps().size():
		box.add_child(_tutorial_panel())
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for name in TAB_NAMES:
		var tab := build_tab(name)
		tab.name = name
		_tabs.add_child(tab)
	box.add_child(_tabs)
	_tabs.current_tab = clampi(_last_tab, 0, TAB_NAMES.size() - 1)
	_tabs.tab_changed.connect(func(i): _last_tab = i)


func on_advance(days: int) -> void:
	controller.advance_days(days)
	show_dashboard()


func on_sim_regular() -> void:
	controller.sim_regular_season()
	show_dashboard()


func on_sim_playoffs() -> void:
	controller.sim_playoffs()
	show_dashboard()
	var champion := controller.season().champion_id
	_say("Champions: %s" % _team_name(champion))


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


## Builds one tab's content. Public so tests can open every tab.
func build_tab(tab_name: String) -> Control:
	match tab_name:
		"Overview": return _scrollable(_tab_overview())
		"Standings": return _tab_standings()
		"Schedule": return _tab_schedule()
		"Roster": return _tab_roster()
		"Finances": return _tab_finances()
		"Staff": return _tab_staff()
		"Draft": return _tab_draft()
		"Meeting": return _tab_meeting()
		"Market": return _tab_market()
		"Trades": return _tab_trades()
		"History": return _tab_history()
		"News": return _tab_news()
	return _tab_league()


# --- tabs ----------------------------------------------------------------------------------

## The Hall of Fame and single-season records.
func _tab_history() -> Control:
	var w := controller.state.world
	var records := FcRecords.new(w, controller.league_id)
	var box := HBoxContainer.new()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if controller.state.mode == FcGameState.MODE_OWNER and not controller.owner_history().is_empty():
		left.add_child(FcUiTables.label("Your ownership career (reputation %d)" % controller.owner_reputation(), 18, true))
		var career_rows: Array = []
		var history: Array = controller.owner_history()
		for i in range(history.size() - 1, -1, -1):
			var h: Array = history[i]
			career_rows.append(["%d-%02d" % [h[0], (h[0] + 1) % 100], _team_name(h[1]), h[3], h[2], "Champions" if h[4] == 1 else ""])
		var career_table := FcUiTables.table(["Season", "Team", "Wins", "Approval", ""], career_rows, [70, 0, 50, 70, 90])
		career_table.custom_minimum_size = Vector2(0, 150)
		career_table.size_flags_vertical = Control.SIZE_FILL
		left.add_child(career_table)
	left.add_child(FcUiTables.label("Hall of Fame", 18, true))
	var hof_rows: Array = []
	for entry in records.hall_of_fame(controller.state.current_season):
		var h := records.honours_of(entry[1])
		var t := w.career_totals(entry[1])
		hof_rows.append([w.player_name(entry[1]), entry[2], t["seasons"], t["points"], h["mvp"], h["titles"], roundi(entry[0])])
	if hof_rows.is_empty():
		left.add_child(FcUiTables.label("Nobody has been inducted yet. Retired stars are eligible %d seasons after their last game." % FcRecords.EXPERIENCE_WAIT))
	left.add_child(FcUiTables.table(["Player", "Inducted", "Seasons", "Points", "MVPs", "Titles", "Score"], hof_rows, [0, 70, 70, 70, 50, 50, 50]))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		right.add_child(FcUiTables.label("Best single seasons: %s" % entry[1].to_lower(), 16, true))
		var rows: Array = []
		for rec in records.single_season_records(entry[0], 5):
			rows.append([w.player_name(rec[1]), "%d-%02d" % [rec[2], (rec[2] + 1) % 100], rec[0]])
		right.add_child(FcUiTables.table(["Player", "Season", entry[1]], rows, [0, 80, 80]))
	box.add_child(right)
	return box


## Propose a trade: pick a partner, select players on both sides, check or propose.
func _tab_trades() -> Control:
	var w := controller.state.world
	var user_id := controller.state.user_team_id
	var box := VBoxContainer.new()   # the "Propose a trade" page
	var offers_page := VBoxContainer.new()
	var others: Array[int] = []
	for t in w.teams.all():
		if t.id != user_id and w.leagues.get_by_id(controller.league_id).contains_team(t.id):
			others.append(t.id)
	if others.is_empty():
		box.add_child(FcUiTables.label("There is nobody to trade with."))
		return box
	if not _trade_partner in others:
		_trade_partner = others[0]
	var picker := OptionButton.new()
	for tid in others:
		picker.add_item(_team_name(tid))
	picker.selected = others.find(_trade_partner)
	picker.item_selected.connect(func(i):
		_trade_partner = others[i]
		show_dashboard())
	var offers := controller.trade_offers()
	if not offers.is_empty():
		offers_page.add_child(FcUiTables.label("Offers from other teams (new ones every two weeks)", 18, true))
		var offer_rows: Array = []
		for o in offers:
			var theirs: FcPlayer = w.players.get_by_id(o["get"])
			var mine: FcPlayer = w.players.get_by_id(o["give"])
			var ratings_now := FcPlayerRatings.load_default()
			offer_rows.append([o["name"], "%s (%d, age %d)" % [mine.identity.full_name(), roundi(ratings_now.overall(mine)), mine.age_on(FcDate.new(controller.contract_year(), 7, 1))], "%s (%d, age %d)" % [theirs.identity.full_name(), roundi(ratings_now.overall(theirs)), theirs.age_on(FcDate.new(controller.contract_year(), 7, 1))]])
		var offer_table := FcUiTables.table(["Team", "They want", "They offer you"], offer_rows)
		offer_table.custom_minimum_size = Vector2(0, 135)
		offer_table.size_flags_vertical = Control.SIZE_FILL
		offers_page.add_child(offer_table)
		var offer_buttons := HBoxContainer.new()
		offer_buttons.add_child(FcUiTables.button("Accept selected offer", func():
			var picked := offer_table.get_selected()
			if picked == null:
				_say("Select an offer first.")
				return
			var result := controller.accept_trade_offer(offers[picked.get_index()])
			_say(result["reason"])
			if result["accepted"]:
				show_dashboard()))
		offer_buttons.add_child(FcUiTables.button("Decline selected offer", func():
			var picked2 := offer_table.get_selected()
			if picked2 == null:
				_say("Select an offer first.")
				return
			controller.decline_trade_offer(offers[picked2.get_index()])
			show_dashboard()))
		offers_page.add_child(offer_buttons)
	box.add_child(FcUiTables.label("Trade with:", 18, true))
	box.add_child(picker)
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var lists: Array = []
	var ids_by_list: Array = []
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [[user_id, "You give"], [_trade_partner, "You get"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label(side[1], 16, true))
		var list := ItemList.new()
		list.select_mode = ItemList.SELECT_MULTI
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var ids: Array[int] = []
		for pid in w.teams.get_by_id(side[0]).roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			var c := w.active_contract_of(pid)
			list.add_item("%s  %s  age %d  ovr %d  %s%s" % [p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(year, 7, 1)), roundi(ratings.overall(p)), FcUiTables.money(c.cap_hit_for(year)) if c != null else "-", "  (no-trade)" if c != null and c.no_trade else ""])
			ids.append(pid)
		col.add_child(list)
		columns.add_child(col)
		lists.append(list)
		ids_by_list.append(ids)
	box.add_child(columns)
	var pick_lists: Array = []
	var picks_by_list: Array = []
	var pick_columns := HBoxContainer.new()
	for side in [[user_id, "Draft picks you give"], [_trade_partner, "Draft picks you get"]]:
		var col2 := VBoxContainer.new()
		col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col2.add_child(FcUiTables.label(side[1], 16, true))
		var plist := ItemList.new()
		plist.select_mode = ItemList.SELECT_MULTI
		plist.custom_minimum_size = Vector2(0, 110)
		var refs: Array = []
		for entry in controller.tradable_picks(side[0]):
			plist.add_item(entry["label"])
			refs.append([entry["year"], entry["round"], entry["original"]])
		col2.add_child(plist)
		pick_columns.add_child(col2)
		pick_lists.append(plist)
		picks_by_list.append(refs)
	box.add_child(pick_columns)
	var pick_refs := func(index: int) -> Array:
		var out2: Array = []
		for i in pick_lists[index].get_selected_items():
			out2.append(picks_by_list[index][i])
		return out2
	var pick := func(index: int) -> Array:
		var out: Array = []
		for i in lists[index].get_selected_items():
			out.append(ids_by_list[index][i])
		return out
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Check the offer", func():
		_say(controller.propose_trade(_trade_partner, pick.call(0), pick.call(1), true, pick_refs.call(0), pick_refs.call(1))["reason"])))
	row.add_child(FcUiTables.button("Propose trade", func():
		var r := controller.propose_trade(_trade_partner, pick.call(0), pick.call(1), false, pick_refs.call(0), pick_refs.call(1))
		if r["accepted"]:
			show_dashboard()
		_say(r["reason"])))
	box.add_child(row)
	if offers.is_empty():
		offers_page.add_child(FcUiTables.label("No team has made you an offer right now. New offers can arrive every two weeks during the season and in the free-agency window."))
	var pages := TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offers_page.name = "Offers from teams (%d)" % offers.size()
	box.name = "Propose a trade"
	pages.add_child(offers_page)
	pages.add_child(box)
	pages.current_tab = (0 if not offers.is_empty() else 1) if _last_trade_page < 0 else clampi(_last_trade_page, 0, 1)
	pages.tab_changed.connect(func(i): _last_trade_page = i)
	return pages


## Free agents (best first) and the most recent draft. Read-only for now.
## The owners' meeting: while it is on, the proposals with how every owner leans, and your vote.
func _tab_meeting() -> Control:
	var box := VBoxContainer.new()
	var pending := controller.expansion_status()
	if not pending.is_empty():
		var info := FcUiTables.label("The owners approved an expansion to %d teams. The %d new teams will each pick %d players from the existing teams in an expansion draft. Protect up to %d of your players (select them below); no team loses more than one player. Then press Run the expansion draft." % [pending["size"], pending["new_teams"], pending["picks_per_team"], pending["limit"]], 16)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(200, 0)
		box.add_child(info)
		var protect_list := ItemList.new()
		protect_list.select_mode = ItemList.SELECT_MULTI
		protect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var roster_ids: Array[int] = []
		var ratings_now := FcPlayerRatings.load_default()
		for pid in controller.state.world.teams.get_by_id(controller.state.user_team_id).roster.player_ids:
			var p: FcPlayer = controller.state.world.players.get_by_id(pid)
			protect_list.add_item("%s  %s  age %d  ovr %d" % [p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(controller.contract_year(), 7, 1)), roundi(ratings_now.overall(p))])
			roster_ids.append(pid)
			if pid in pending["protected"]:
				protect_list.select(protect_list.item_count - 1, false)
		box.add_child(protect_list)
		box.add_child(FcUiTables.button("Confirm my protected players", func():
			var chosen: Array = []
			for i in protect_list.get_selected_items():
				chosen.append(roster_ids[i])
			var result := controller.set_protected_players(chosen)
			_say(result["reason"] + (" Press Run the expansion draft when ready." if result["ok"] else ""))))
		return box
	var items := controller.meeting_items()
	if items.is_empty():
		box.add_child(FcUiTables.label("The league's owners meet once a year, after the season, to vote on rule changes. Press Begin Offseason when the season is over to open the meeting.", 16))
	else:
		var intro := FcUiTables.label("The owners' meeting: vote on each proposal (each franchise has one vote). Cap changes need two thirds, an expansion three quarters, everything else a simple majority. Your influence: %d points (spend them to turn an owner's vote or to propose an item)." % controller.meeting_influence(), 16)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.custom_minimum_size = Vector2(200, 0)
		box.add_child(intro)
		var summary: Array = []
		for entry in items:
			var vote = entry["user_vote"]
			summary.append([entry["item"]["title"], entry["tally"]["yes"], entry["tally"]["no"], entry["tally"]["needed"], "-" if vote == null else ("Yes" if vote else "No"), "PASSES" if entry["tally"]["passes"] else "fails"])
		var summary_table := FcUiTables.table(["Proposal", "Yes", "No", "Needed", "Your vote", "Now"], summary, [0, 50, 50, 70, 80, 70])
		summary_table.custom_minimum_size = Vector2(0, 130)
		summary_table.size_flags_vertical = Control.SIZE_FILL
		box.add_child(summary_table)
		var detail_label := FcUiTables.label("Select a proposal to see what it does and how every owner leans.")
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.custom_minimum_size = Vector2(200, 0)
		box.add_child(detail_label)
		var vote_rows := FcUiTables.table(["Owner", "Vote", "Why", "To turn"], [], [0, 60, 0, 70])
		box.add_child(vote_rows)
		var vote_team_ids: Array[int] = []
		var show_item := func(index: int):
			var entry: Dictionary = items[index]
			detail_label.text = "%s: %s" % [entry["item"]["title"], entry["item"]["detail"]]
			vote_rows.clear()
			vote_team_ids.clear()
			var root_item := vote_rows.create_item()
			for v in entry["tally"]["votes"]:
				var row_item := vote_rows.create_item(root_item)
				row_item.set_text(0, v["name"])
				row_item.set_text(1, "Yes" if v["yes"] else "No")
				row_item.set_text(2, v["reason"])
				row_item.set_text(3, "-" if v["flipped"] else "%d pt%s" % [v["cost"], "" if v["cost"] == 1 else "s"])
				vote_team_ids.append(v["team"])
		summary_table.item_selected.connect(func():
			var picked := summary_table.get_selected()
			if picked != null:
				show_item.call(picked.get_index()))
		if summary_table.get_root().get_child_count() > 0:
			var first_index := mini(_last_meeting_item, summary_table.get_root().get_child_count() - 1)
			summary_table.get_root().get_child(first_index).select(0)
			show_item.call(first_index)
		var buttons := HBoxContainer.new()
		for choice in [["Vote yes", true], ["Vote no", false]]:
			buttons.add_child(FcUiTables.button(choice[0], func():
				var picked2 := summary_table.get_selected()
				if picked2 == null:
					_say("Select a proposal first.")
					return
				controller.cast_meeting_vote(items[picked2.get_index()]["item"]["id"], choice[1])
				show_dashboard()))
		buttons.add_child(FcUiTables.button("Lobby the selected owner (turn their vote)", func():
			var proposal := summary_table.get_selected()
			var owner_row := vote_rows.get_selected()
			if proposal == null or owner_row == null:
				_say("Select a proposal, then an owner in the lower list.")
				return
			var result := controller.lobby_owner(items[proposal.get_index()]["item"]["id"], vote_team_ids[owner_row.get_index()])
			_say(result["reason"])
			if result["ok"]:
				_last_meeting_item = proposal.get_index()
				show_dashboard()))
		box.add_child(buttons)
		var proposable := controller.proposable_items()
		if not proposable.is_empty():
			var propose_row := HBoxContainer.new()
			propose_row.add_child(FcUiTables.label("Add a proposal of your own (%d points, once a meeting):" % FcOwnersMeeting.PROPOSE_COST))
			var proposal_pick := OptionButton.new()
			for p in proposable:
				proposal_pick.add_item(p["title"])
			propose_row.add_child(proposal_pick)
			propose_row.add_child(FcUiTables.button("Propose it", func():
				var made := controller.propose_item(proposable[proposal_pick.selected]["id"])
				_say(made["reason"])
				if made["ok"]:
					show_dashboard()))
			box.add_child(propose_row)
		var destinations := controller.relocation_options()
		if not destinations.is_empty() and not controller.state.meeting.get("proposed", false):
			box.add_child(FcUiTables.label("Move your franchise: you choose the city and may rename the team (needs two thirds of the owners, costs %d points)." % FcOwnersMeeting.PROPOSE_COST, 14))
			var move_row := HBoxContainer.new()
			var city_pick := OptionButton.new()
			for d in destinations:
				city_pick.add_item("%s (%s, %.1fM people)" % [d["name"], d["region"], d["population"] / 1e6])
			move_row.add_child(city_pick)
			move_row.add_child(FcUiTables.label("New team name (optional):"))
			var name_edit := LineEdit.new()
			name_edit.placeholder_text = "keep the current name"
			name_edit.custom_minimum_size = Vector2(200, 0)
			move_row.add_child(name_edit)
			move_row.add_child(FcUiTables.button("Propose the move", func():
				var moved := controller.propose_relocation(destinations[city_pick.selected]["name"], name_edit.text)
				_say(moved["reason"])
				if moved["ok"]:
					show_dashboard()))
			box.add_child(move_row)
	var log_rows: Array = []
	var log: Array = controller.state.meeting_log
	for i in range(log.size() - 1, maxi(-1, log.size() - 13), -1):
		log_rows.append(["%d-%02d" % [log[i][0], (log[i][0] + 1) % 100], log[i][1], "Passed" if log[i][2] == 1 else "Failed", "%d-%d" % [log[i][3], log[i][4]]])
	box.add_child(FcUiTables.label("Past meetings", 16, true))
	box.add_child(FcUiTables.table(["Season", "Proposal", "Result", "Vote"], log_rows, [70, 0, 70, 70]))
	return box


func _tab_draft() -> Control:
	var w := controller.state.world
	var box := VBoxContainer.new()
	var status := controller.draft_status()
	if status.is_empty():
		box.add_child(FcUiTables.label("The draft is held after the season, in the offseason. You will see your scouts' board here and pick for your team.", 16))
		var report := controller.latest_draft_report()
		var rows: Array = []
		if not report.is_empty():
			box.add_child(FcUiTables.label("The %d draft" % report["year"], 18, true))
			for entry in report["rows"]:
				var p: FcPlayer = w.players.get_by_id(entry["player"])
				if p != null:
					rows.append([entry["pick"], entry["round"], _team_name(entry["team"]), p.identity.full_name(), FcPosition.abbreviation(p.primary_position)])
		box.add_child(FcUiTables.table(["Pick", "Round", "Team", "Player", "Pos"], rows, [50, 60, 0, 0, 50]))
		return box
	var prefix := "Pick %d of %d (round %d): " % [status["pick"], status["total"], status["round"]]
	if status["complete"]:
		box.add_child(FcUiTables.label("The draft is complete.", 18, true))
	elif status["user_on_clock"]:
		box.add_child(FcUiTables.label(prefix + "YOU ARE ON THE CLOCK", 18, true))
	else:
		box.add_child(FcUiTables.label(prefix + _team_name(status["team"]), 18))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_child(FcUiTables.label("Draft board (your scouts' view; ranges hold the truth about 4 times in 5)", 16, true))
	var rows2: Array = []
	var ids: Array[int] = []
	var rank := 0
	for entry in controller.draft_board():
		rank += 1
		var p: FcPlayer = entry["player"]
		var r: Dictionary = entry["report"]
		rows2.append([rank, p.identity.full_name(), FcPosition.abbreviation(p.primary_position), entry["age"], "%d cm" % p.physical.height_cm, "%d-%d" % [r["ovr_low"], r["ovr_high"]], "%d-%d" % [r["pot_low"], r["pot_high"]], r["character"] if r["worked_out"] else "", p.identity.country])
		ids.append(p.id)
	var table := FcUiTables.table(["#", "Prospect", "Pos", "Age", "Height", "Overall", "Potential", "Worked out", "From"], rows2, [40, 0, 45, 45, 70, 70, 80, 130, 110])
	left.add_child(table)
	var buttons := HBoxContainer.new()
	buttons.add_child(FcUiTables.button("Draft selected prospect", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a prospect first.")
			return
		var r2 := controller.user_draft_pick(ids[item.get_index()])
		_say(r2["reason"])
		_after_draft_action()))
	buttons.add_child(FcUiTables.button("Invite selected to a workout (%d left)" % controller.draft_workouts_left(), func():
		var item := table.get_selected()
		if item == null:
			_say("Select a prospect first.")
			return
		var r4 := controller.invite_to_workout(ids[item.get_index()])
		show_dashboard()
		_say(r4["reason"])))
	buttons.add_child(FcUiTables.button("Let my staff pick", func():
		var r3 := controller.draft_staff_pick()
		_say(r3["reason"])
		_after_draft_action()))
	left.add_child(buttons)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Picks so far", 16, true))
	var log_rows: Array = []
	var results := controller.draft_results()
	for i in range(results.size() - 1, -1, -1):
		var pick: Array = results[i]
		var p2: FcPlayer = w.players.get_by_id(pick[3])
		log_rows.append([pick[1], _team_name(pick[2]), p2.identity.full_name(), FcPosition.abbreviation(p2.primary_position)])
	right.add_child(FcUiTables.table(["Pick", "Team", "Player", "Pos"], log_rows, [50, 0, 0, 50]))
	columns.add_child(right)
	box.add_child(columns)
	return box


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


func _tab_market() -> Control:
	var w := controller.state.world
	var box := HBoxContainer.new()
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_child(FcUiTables.label("Best free agents", 18, true))
	var agents := controller.free_agent_market(20)
	var rows: Array = []
	var agent_ids: Array[int] = []
	for entry in agents:
		var p: FcPlayer = entry["player"]
		rows.append([p.identity.full_name(), FcPosition.abbreviation(p.primary_position), entry["age"], roundi(ratings.overall(p)), p.development.potential, FcUiTables.money(entry["ask"]), entry["years"]])
		agent_ids.append(p.id)
	var fa_table := FcUiTables.table(["Player", "Pos", "Age", "Ovr", "Pot", "Asks", "Years"], rows, [0, 50, 50, 50, 50, 90, 50])
	left.add_child(fa_table)
	var offer_row := HBoxContainer.new()
	offer_row.add_child(FcUiTables.label("Offer $M a year"))
	var offer_salary := SpinBox.new()
	offer_salary.min_value = 0.1
	offer_salary.max_value = 100
	offer_salary.step = 0.05
	offer_row.add_child(offer_salary)
	offer_row.add_child(FcUiTables.label("  years"))
	var offer_years := SpinBox.new()
	offer_years.min_value = 1
	offer_years.max_value = 5
	offer_row.add_child(offer_years)
	fa_table.item_selected.connect(func():
		var picked := fa_table.get_selected()
		if picked != null:
			offer_salary.value = agents[picked.get_index()]["ask"] / 1e6
			offer_years.value = agents[picked.get_index()]["years"])
	offer_row.add_child(FcUiTables.button("Sign selected free agent", func():
		var item := fa_table.get_selected()
		if item == null:
			_say("Select a free agent first.")
			return
		var r := controller.sign_free_agent(agent_ids[item.get_index()], roundi(offer_salary.value * 1e6), int(offer_years.value))
		if r["signed"]:
			show_dashboard()
		_say(r["reason"])))
	left.add_child(offer_row)
	left.add_child(FcUiTables.label("Players ask for the amount shown but accept a little less, especially for longer contracts. Change the offer and press the button; a refusal tells you the least he will take."))
	box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("Latest draft (first round)", 18, true))
	var report := controller.latest_draft_report()
	var draft_rows: Array = []
	if report.is_empty():
		right.add_child(FcUiTables.label("No draft has been held yet. The first one takes place after the season."))
	if not report.is_empty():
		for entry in report["rows"]:
			if entry["round"] != 1:
				continue
			var p: FcPlayer = w.players.get_by_id(entry["player"])
			if p != null:
				var moved: int = entry["moved"]
				draft_rows.append([entry["pick"], _team_name(entry["team"]), "%+d" % moved if moved != 0 else "-", p.identity.full_name(), FcPosition.abbreviation(p.primary_position), roundi(ratings.overall(p)), p.development.potential])
		var note := FcUiTables.label("After the %d season. %s" % [report["year"], "Lottery on: 'Lot.' shows how many places the lottery moved a team up (+) or down (-)." if report["lottery"] else "No lottery: order follows the records."])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(100, 0)
		right.add_child(note)
		var winners: Array[String] = []
		for entry in report["rows"]:
			if entry["round"] == 1 and entry["moved"] > 0:
				winners.append("%s jumped %d place%s to pick %d" % [_team_name(entry["team"]), entry["moved"], "" if entry["moved"] == 1 else "s", entry["pick"]])
		if not winners.is_empty():
			var winners_label := FcUiTables.label("Lottery winners: " + "; ".join(winners))
			winners_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			winners_label.custom_minimum_size = Vector2(100, 0)
			right.add_child(winners_label)
	right.add_child(FcUiTables.table(["Pick", "Team", "Lot.", "Player", "Pos", "Ovr", "Pot"], draft_rows, [50, 0, 50, 0, 50, 50, 50]))
	box.add_child(right)
	return box


## Wraps a long page so it can be scrolled instead of running off the bottom of the window.
func _scrollable(content: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _tab_overview() -> Control:
	var box := VBoxContainer.new()
	var s := controller.season()
	var rec := controller.user_record()
	box.add_child(FcUiTables.label("Record: %d-%d    League rank: %d    Games left: %d    Streak: %s" % [rec["wins"], rec["losses"], rec["rank"], rec["games_left"], rec["streak"]], 18))
	var next := controller.next_user_game()
	if next != null:
		var opp := next.away_id if next.home_id == controller.state.user_team_id else next.home_id
		box.add_child(FcUiTables.label("Next game: %s %s on %s" % ["vs" if next.home_id == controller.state.user_team_id else "at", _team_name(opp), s.date_of_day(next.day).to_iso()]))
	if s.status == FcSeason.Status.COMPLETE:
		box.add_child(FcUiTables.label("Champions: %s    Runner-up: %s" % [_team_name(s.champion_id), _team_name(s.runner_up_id)], 18, true))
	var warning := controller.distress_warning()
	if warning != "":
		var alert := FcUiTables.label("Warning: " + warning, 15)
		alert.add_theme_color_override("font_color", FcUiTheme.BAD)
		alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		alert.custom_minimum_size = Vector2(300, 0)
		box.add_child(alert)
	var report := controller.owner_report()
	if not report.is_empty():
		box.add_child(FcUiTables.label("Owner report, %d-%02d season" % [report["year"], (report["year"] + 1) % 100], 18, true))
		box.add_child(FcUiTables.label("Profit %s    Revenue %s    Franchise value %s (%s this season)    Cash %s    Debt %s" % [
			FcUiTables.money(report["profit"]), FcUiTables.money(report["revenue"]), FcUiTables.money(report["valuation"]),
			FcUiTables.money(report["valuation_change"]), FcUiTables.money(report["cash"]), FcUiTables.money(report["debt"])]))
		box.add_child(FcUiTables.label("Wins %d (expected about %d)    Owner approval: %d / 100" % [report["wins"], report["expected_wins"], report["approval"]]))
	if controller.state.mode == FcGameState.MODE_OWNER:
		var history := controller.owner_history()
		var stints: Array[String] = []
		for row in history:
			var label := _team_name(row[1])
			if stints.is_empty() or not stints[stints.size() - 1].begins_with(label):
				stints.append("%s (1)" % label)
			else:
				var n := int(stints[stints.size() - 1].rsplit("(")[1].trim_suffix(")")) + 1
				stints[stints.size() - 1] = "%s (%d)" % [label, n]
		box.add_child(FcUiTables.label("Owner reputation: %d / 100.%s" % [controller.owner_reputation(), "  Your career, seasons per team: " + ", ".join(stints) if not stints.is_empty() else ""]))
		var offers := controller.job_offers()
		if not offers.is_empty():
			box.add_child(FcUiTables.label("Job offers: other franchises would like you as their owner (you can change teams once a season, before the offseason starts)", 18, true))
			var offer_rows: Array = []
			var offer_ids: Array[int] = []
			for o in offers:
				offer_rows.append([o["name"], FcUiTables.money(o["valuation"]), o["wins"], FcUiTables.money(o["payroll"]), o["fan_interest"], FcUiTables.money(o["cash"]), FcUiTables.money(o["debt"]), o["seats"]])
				offer_ids.append(o["team"])
			var offer_table := FcUiTables.table(["Team", "Value", "Wins", "Payroll", "Fans", "Cash", "Debt", "Seats"], offer_rows, [0, 90, 50, 90, 50, 90, 90, 60])
			offer_table.custom_minimum_size = Vector2(0, 150)
			offer_table.size_flags_vertical = Control.SIZE_FILL
			box.add_child(offer_table)
			box.add_child(FcUiTables.button("Take the job with the selected team", func():
				var picked := offer_table.get_selected()
				if picked == null:
					_say("Select a team first.")
					return
				var result := controller.transfer_to(offer_ids[picked.get_index()])
				if result["ok"]:
					show_dashboard()
				_say(result["reason"])))
	var news: Array = controller.state.world.news
	if not news.is_empty():
		box.add_child(FcUiTables.label("Latest news", 18, true))
		for i in range(news.size() - 1, maxi(-1, news.size() - 7), -1):
			box.add_child(FcUiTables.label("  %s  %s" % [news[i]["date"], news[i]["text"]]))
	var rules := controller.state.world.rules_of_league(controller.league_id)
	box.add_child(FcUiTables.label("League rules", 18, true))
	for line in rules.playoffs.describe(controller.state.world.leagues.get_by_id(controller.league_id)):
		box.add_child(FcUiTables.label("  " + line))
	if rules.draft.lottery_teams > 0:
		box.add_child(FcUiTables.label("  Draft lottery: the worst %d non-playoff teams enter and the top %d picks are drawn" % [rules.draft.lottery_teams, rules.draft.lottery_picks]))
	else:
		box.add_child(FcUiTables.label("  No draft lottery: the worst record picks first"))
	box.add_child(FcUiTables.label("  Salary cap %s, tax line %s, hard limit %s" % [FcUiTables.money(rules.cap.salary_cap), FcUiTables.money(rules.cap.luxury_tax_line), FcUiTables.money(rules.cap.effective_limit())]))
	return box


func _tab_standings() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var league: FcLeague = controller.state.world.leagues.get_by_id(controller.league_id)
	var st := controller.standings()
	for conference in league.conferences:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("%s Conference" % conference.name, 18, true))
		var order := st.conference_ranking(conference)
		var rows: Array = []
		for t in order:
			var r: Dictionary = st.records[t]
			var l10 := st.last_ten(t)
			rows.append([("* " if t == controller.state.user_team_id else "") + _team_name(t), r["w"], r["l"], "%.3f" % st.win_pct(t), "%.1f" % st.games_behind(order[0], t), "%d-%d" % [l10[0], l10[1]], st.streak_text(t)])
		col.add_child(FcUiTables.table(["Team", "W", "L", "Pct", "GB", "L10", "Strk"], rows, [0, 40, 40, 60, 50, 50, 50]))
		row.add_child(col)
	return row


func _tab_schedule() -> Control:
	var s := controller.season()
	var tid := controller.state.user_team_id
	var rows: Array = []
	var keys: Array = []
	for g in s.games:
		if not g.involves(tid):
			continue
		keys.append([g.day, g.series])
		var home := g.home_id == tid
		var opp := g.away_id if home else g.home_id
		var result := ""
		if g.played:
			var mine := g.home_score if home else g.away_score
			var theirs := g.away_score if home else g.home_score
			result = "%s %d-%d%s" % ["W" if mine > theirs else "L", mine, theirs, " (OT)" if g.overtimes > 0 else ""]
		rows.append([s.date_of_day(g.day).to_iso(), "Playoffs" if g.series > 0 else "", "vs" if home else "at", _team_name(opp), result])
	var table := FcUiTables.table(["Date", "Round", "", "Opponent", "Result"], rows, [110, 80, 40, 0, 140])
	table.set_meta("keys", keys)
	var box := VBoxContainer.new()
	box.add_child(table)
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.button("Box score of selected game", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a game first.")
			return
		var key: Array = keys[item.get_index()]
		var text := box_score_text(key[0], key[1])
		_say("No box score is kept for that game (only your most recent games are stored)." if text == "" else "")
		if text != "":
			_show_text_popup("Box score", text)))
	row.add_child(FcUiTables.label("Box scores are kept for your team's last %d games." % FcSeason.RECENT_BOX_LIMIT))
	box.add_child(row)
	return box


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
	var w := controller.state.world
	var team: FcTeam = w.teams.get_by_id(controller.state.user_team_id)
	var ratings := FcPlayerRatings.load_default()
	var season_year := controller.state.current_season
	var stats := controller.season().stats
	var rows: Array = []
	var players: Array = []
	for pid in team.roster.player_ids:
		players.append(w.players.get_by_id(pid))
	players.sort_custom(func(a, b): return ratings.overall(a) > ratings.overall(b))
	for p in players:
		var c := w.active_contract_of(p.id)
		rows.append([p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(FcDate.new(season_year, 7, 1)),
			"%d cm" % p.physical.height_cm, roundi(ratings.overall(p)), p.development.potential,
			FcUiTables.money(c.salary_for(season_year)) if c != null else "-", c.end_season() if c != null else "-",
			"%.1f" % stats.per_game(p.id, "points"), "%.1f" % stats.per_game(p.id, "rebounds"), "%.1f" % stats.per_game(p.id, "ast"), "%.1f" % stats.per_game(p.id, "minutes"),
			"" if p.games_out == 0 else "OUT %d games: %s" % [p.games_out, p.injury]])
	var table := FcUiTables.table(["Player", "Pos", "Age", "Height", "Ovr", "Pot", "Salary", "Thru", "PPG", "RPG", "APG", "MPG", "Health"], rows, [0, 50, 50, 70, 50, 50, 90, 60, 55, 55, 55, 55, 220])
	var ids: Array[int] = []
	for p in players:
		ids.append(p.id)
	var box := VBoxContainer.new()
	box.add_child(table)
	var roster_hint := FcUiTables.label("Select a player, then extend his contract (only in the last year of the deal), release him, or open his profile.")
	roster_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_hint.custom_minimum_size = Vector2(200, 0)
	box.add_child(roster_hint)
	var row := HBoxContainer.new()
	var expiring := {}
	for e in controller.expiring_players():
		expiring[e["player"].id] = e
	var ext_salary := SpinBox.new()
	ext_salary.tooltip_text = "The yearly salary you offer, in millions, to keep this player. He accepts a little less than he asks."
	ext_salary.min_value = 0.1
	ext_salary.max_value = 100
	ext_salary.step = 0.05
	var ext_years := SpinBox.new()
	ext_years.tooltip_text = "Length of the new contract in years. Players want long deals when young and short ones when older."
	ext_years.min_value = 1
	ext_years.max_value = 5
	table.item_selected.connect(func():
		var picked := table.get_selected()
		if picked != null and expiring.has(ids[picked.get_index()]):
			ext_salary.value = expiring[ids[picked.get_index()]]["ask"] / 1e6
			ext_years.value = expiring[ids[picked.get_index()]]["years"])
	row.add_child(FcUiTables.label("Extension $M"))
	row.add_child(ext_salary)
	row.add_child(FcUiTables.label("years"))
	row.add_child(ext_years)
	row.add_child(FcUiTables.button("Extend contract of selected player", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		var r := controller.extend_contract(ids[item.get_index()], roundi(ext_salary.value * 1e6), int(ext_years.value))
		if r["ok"]:
			show_dashboard()
		_say(r["reason"])))
	row.add_child(FcUiTables.button("Release selected player (pay half his salary)", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		var r := controller.release_player(ids[item.get_index()])
		if r["released"]:
			show_dashboard()
		_say(r["reason"])))
	row.add_child(FcUiTables.button("Player profile of selected player", func():
		var item := table.get_selected()
		if item == null:
			_say("Select a player first.")
			return
		_show_text_popup("Player profile", player_profile_text(ids[item.get_index()]))))
	box.add_child(row)
	return box


## The Finances tab is split into four pages (the owner's levers are many): a summary with the
## books and the league comparison, prices and the shop, sponsors and loans, arena and facilities.
func _tab_finances() -> Control:
	var w := controller.state.world
	var b := controller.business()
	var cap := w.rules_of_league(controller.league_id).cap
	var summary := VBoxContainer.new()
	summary.add_child(FcUiTables.label("Your franchise", 18, true))
	summary.add_child(FcUiTables.label("Payroll %s of a %s cap (hard limit %s). Cash %s. Debt %s. Value %s." % [
		FcUiTables.money(w.payroll_of_team(b.id, controller.state.current_season)), FcUiTables.money(cap.salary_cap),
		FcUiTables.money(cap.effective_limit()), FcUiTables.money(b.cash), FcUiTables.money(b.debt), FcUiTables.money(b.valuation)]))
	summary.add_child(FcUiTables.label("Fan interest %d, brand %d, arena quality %d." % [b.fan_interest, b.brand, b.facilities_level]))
	var executive := w.staff_in_role(b.id, FcStaffRole.Id.BUSINESS_EXECUTIVE)
	var executive_label: Label
	if executive == null:
		executive_label = FcUiTables.label("No business executive: sponsorships, marketing and overhead all suffer. Hire one on the Staff tab.")
	else:
		executive_label = FcUiTables.label("Business executive %s: marketing %d (sponsorships and brand), financial acumen %d (overhead), community relations %d (fan interest)." % [executive.identity.full_name(), executive.skills.get_value("marketing"), executive.skills.get_value("financial_acumen"), executive.skills.get_value("community_relations")])
	executive_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	executive_label.custom_minimum_size = Vector2(200, 0)
	summary.add_child(executive_label)
	var rows: Array = []
	var years: Array = []
	for r in w.finances.all():
		if r.team_id == b.id:
			years.append(r)
	years.reverse()
	for r in years:
		rows.append(["%d-%02d" % [r.year, (r.year + 1) % 100], r.wins, FcUiTables.money(r.total_revenue()), FcUiTables.money(r.total_expenses()), FcUiTables.money(r.profit()),
			r.average_attendance, "$%d" % r.ticket_price, FcUiTables.money(r.valuation_end)])
	var books := HBoxContainer.new()
	books.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.add_child(FcUiTables.label("Your seasons", 16, true))
	mine.add_child(FcUiTables.table(["Season", "Wins", "Revenue", "Expenses", "Profit", "Attendance", "Ticket", "Value"], rows))
	books.add_child(mine)
	var league_books := controller.league_finances()
	if not league_books.is_empty():
		var compare := VBoxContainer.new()
		compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compare.add_child(FcUiTables.label("How you compare (last season, * = you)", 16, true))
		var compare_rows: Array = []
		for entry in league_books:
			compare_rows.append(["%s%s" % ["* " if entry["team"] == b.id else "", entry["name"]], entry["wins"], FcUiTables.money(entry["revenue"]), FcUiTables.money(entry["profit"]), FcUiTables.money(entry["payroll"]), "$%d" % entry["price"], entry["attendance"]])
		compare.add_child(FcUiTables.table(["Team", "Wins", "Revenue", "Profit", "Payroll", "Ticket", "Fans"], compare_rows, [150, 40, 72, 72, 72, 52, 48]))
		books.add_child(compare)
	summary.add_child(books)
	if controller.state.mode != FcGameState.MODE_OWNER:
		return summary

	# --- prices and the shop ---
	var pricing := VBoxContainer.new()
	pricing.add_child(FcUiTables.label("Tickets", 18, true))
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.label("Ticket price $"))
	var price := SpinBox.new()
	price.tooltip_text = "The price of a regular ticket. 'Use suggestion' sets the price that just fills your arena. Higher earns more per fan but empties seats; lower fills seats but earns less."
	price.min_value = 5
	price.max_value = 2000
	price.value = b.ticket_price
	row.add_child(price)
	row.add_child(FcUiTables.label("  Marketing $M"))
	var marketing := SpinBox.new()
	marketing.tooltip_text = "Yearly marketing spend in millions. It builds your brand, which lifts sponsors and merchandise. Money spent beyond what your market can use is wasted."
	marketing.min_value = 0
	marketing.max_value = 100
	marketing.step = 0.5
	marketing.value = b.marketing_budget / 1e6
	row.add_child(marketing)
	row.add_child(FcUiTables.button("Apply", func():
		var ok := controller.set_ticket_price(int(price.value)) and controller.set_marketing_budget(roundi(marketing.value * 1e6))
		_say("Updated." if ok else "Those values are not allowed.")))
	row.add_child(FcUiTables.label("   Suggested $%d" % controller.suggested_ticket_price()))
	row.add_child(FcUiTables.button("Use suggestion", func():
		price.value = controller.suggested_ticket_price()
		var ok2 := controller.set_ticket_price(int(price.value))
		_say("Ticket price set to the suggestion." if ok2 else "That price is not allowed.")))
	pricing.add_child(row)
	var hint := FcUiTables.label("The suggestion is the price that just fills your arena today. Fan interest and brand change as you win or lose, so check it each season; AI teams reprice every year.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200, 0)
	pricing.add_child(hint)
	var tix := controller.ticket_plan_preview()
	var season_row := HBoxContainer.new()
	season_row.add_child(FcUiTables.label("Season tickets % of seats"))
	var season_share := SpinBox.new()
	season_share.tooltip_text = "The share of your seats sold as season tickets. Holders pay 12% less but always come. Good when seats would stay empty, a loss when the arena sells out anyway."
	season_share.min_value = 0
	season_share.max_value = 60
	season_share.step = 5
	season_share.value = b.season_ticket_share
	season_row.add_child(season_share)
	season_row.add_child(FcUiTables.label("  Promotion nights"))
	var promo_nights := SpinBox.new()
	promo_nights.tooltip_text = "Home games with half-price tickets that fill the arena. Each costs a little to stage and adds fans and fan interest. Only worth it when seats would otherwise be empty."
	promo_nights.min_value = 0
	promo_nights.max_value = 10
	promo_nights.value = b.promotion_nights
	season_row.add_child(promo_nights)
	season_row.add_child(FcUiTables.button("Apply", func():
		var ok3 := controller.set_season_ticket_share(int(season_share.value)) and controller.set_promotion_nights(int(promo_nights.value))
		_say("Ticket plan updated." if ok3 else "Those values are not allowed.")))
	pricing.add_child(season_row)
	var plan_hint := FcUiTables.label("Season holders pay $%d (12%% off) and always come (%d of %d seats now); promotion nights sell the rest of the arena at $%d and cost %s each. Both only pay when seats would otherwise be empty (demand now %d of %d seats)." % [
		tix["season_price"], tix["holders"], tix["capacity"], tix["promo_price"], FcUiTables.money(tix["promo_cost"]), tix["demand"], tix["capacity"]])
	plan_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_hint.custom_minimum_size = Vector2(200, 0)
	pricing.add_child(plan_hint)
	pricing.add_child(FcUiTables.label("Shop and concessions", 18, true))
	var shop := HBoxContainer.new()
	shop.add_child(FcUiTables.label("Concession prices %"))
	var concessions := SpinBox.new()
	concessions.tooltip_text = "Food and drink prices as a percent of normal. Higher earns more per fan but lowers fan interest a little."
	concessions.min_value = 70
	concessions.max_value = 150
	concessions.step = 5
	concessions.value = b.concession_price_pct
	shop.add_child(concessions)
	shop.add_child(FcUiTables.label("   Playoff ticket price %"))
	var playoff_price := SpinBox.new()
	playoff_price.tooltip_text = "Playoff ticket prices as a percent of the regular price. Playoff demand is higher, so a higher premium earns more until the arena stops selling out."
	playoff_price.min_value = 100
	playoff_price.max_value = 300
	playoff_price.step = 10
	playoff_price.value = b.playoff_premium_pct
	shop.add_child(playoff_price)
	shop.add_child(FcUiTables.label("   Merchandise range"))
	var merch := OptionButton.new()
	merch.tooltip_text = "The merchandise range. Limited is cheap but sells less; Premium sells most but costs a lot of stock and only works for a strong brand."
	for name in FcTeamBusiness.MERCH_TIERS:
		merch.add_item(name)
	merch.selected = b.merch_tier
	shop.add_child(merch)
	shop.add_child(FcUiTables.button("Apply shop settings", func():
		controller.set_concession_price(int(concessions.value))
		controller.set_playoff_premium(int(playoff_price.value))
		controller.set_merch_tier(merch.selected)
		_say("Shop settings updated. Higher concession prices earn more per fan but cost fan interest; a premium range sells more but costs more stock.")))
	pricing.add_child(shop)

	# --- sponsors and loans ---
	var money := VBoxContainer.new()
	money.add_child(FcUiTables.label("Sponsors", 18, true))
	var sponsors := HBoxContainer.new()
	sponsors.add_child(FcUiTables.label("Signed:"))
	var deal_texts: Array[String] = []
	for deal in b.sponsor_deals:
		deal_texts.append("%s %s/yr%s, %d yr left" % [deal["sponsor"], FcUiTables.money(deal["amount"]), " + %s per playoff round" % FcUiTables.money(deal["bonus"]) if deal["bonus"] > 0 else "", deal["years_left"]])
	sponsors.add_child(FcUiTables.label(", ".join(deal_texts) if not deal_texts.is_empty() else "none yet (open-market income)"))
	money.add_child(sponsors)
	var offers := controller.sponsor_offers()
	if not offers.is_empty():
		var offer_row := HBoxContainer.new()
		offer_row.add_child(FcUiTables.label("Offers:"))
		var offer_pick := OptionButton.new()
		offer_pick.tooltip_text = "Sponsors that want to sign with you. Fixed deals pay a steady amount; bonus deals pay less up front and more for playoff rounds won."
		for o in offers:
			offer_pick.add_item("%s: %s/yr x %d%s" % [o["sponsor"], FcUiTables.money(o["amount"]), o["years"], " + %s per playoff round" % FcUiTables.money(o["bonus"]) if o["bonus"] > 0 else ""])
		offer_row.add_child(offer_pick)
		offer_row.add_child(FcUiTables.button("Sign sponsor deal", func():
			var r5 := controller.accept_sponsor(offers[offer_pick.selected]["sponsor"])
			_say(r5["reason"])
			if r5["ok"]:
				show_dashboard()))
		money.add_child(offer_row)
	var style_row := HBoxContainer.new()
	style_row.add_child(FcUiTables.label("Style of the rest of your sponsorship income:"))
	var plan := OptionButton.new()
	plan.tooltip_text = "How the part of your sponsorship money not covered by signed deals is paid. Steady pays less but is guaranteed; Performance pays more only if you win."
	for name in FcTeamBusiness.SPONSOR_PLANS:
		plan.add_item(name)
	plan.selected = b.sponsor_plan
	plan.item_selected.connect(func(i):
		controller.set_sponsor_plan(i)
		_say("Sponsorship: %s. Steady pays less but guaranteed; Performance pays more only if you win." % FcTeamBusiness.SPONSOR_PLANS[i]))
	style_row.add_child(plan)
	money.add_child(style_row)
	money.add_child(FcUiTables.label("Loans", 18, true))
	var loans := HBoxContainer.new()
	loans.add_child(FcUiTables.label("Loan $M"))
	var amount := SpinBox.new()
	amount.tooltip_text = "The amount, in millions, to borrow or repay. Debt costs 6% interest a season and your borrowing limit is a share of your franchise value."
	amount.min_value = 1
	amount.max_value = 500
	amount.value = 10
	loans.add_child(amount)
	loans.add_child(FcUiTables.button("Borrow", func():
		var r := controller.borrow(roundi(amount.value * 1e6))
		_say(r["reason"])
		if r["ok"]:
			show_dashboard()))
	loans.add_child(FcUiTables.button("Repay", func():
		var r := controller.repay_debt(roundi(amount.value * 1e6))
		_say(r["reason"])
		if r["ok"]:
			show_dashboard()))
	loans.add_child(FcUiTables.label("   Borrowing limit %s   Debt %s (6%% interest a season)" % [FcUiTables.money(controller.loan_limit()), FcUiTables.money(b.debt)]))
	money.add_child(loans)
	money.add_child(FcUiTables.label("Owner payouts", 18, true))
	var payouts := HBoxContainer.new()
	payouts.add_child(FcUiTables.label("Dividend $M"))
	var dividend := SpinBox.new()
	dividend.tooltip_text = "Cash to pay yourself, in millions. The club must keep a reserve and cannot have debt. It does not change how the team plays."
	dividend.min_value = 1
	dividend.max_value = 5000
	dividend.value = 10
	payouts.add_child(dividend)
	payouts.add_child(FcUiTables.button("Pay myself", func():
		var rd := controller.take_dividend(roundi(dividend.value * 1e6))
		_say(rd["reason"])
		if rd["ok"]:
			show_dashboard()))
	payouts.add_child(FcUiTables.label("   You can take %s now   Taken so far %s" % [FcUiTables.money(controller.dividend_limit()), FcUiTables.money(b.distributions)]))
	money.add_child(payouts)

	# --- arena and facilities ---
	var arena_page := VBoxContainer.new()
	arena_page.add_child(FcUiTables.label("Arena and facilities", 18, true))
	var quality := HBoxContainer.new()
	quality.add_child(FcUiTables.label("Arena quality %d (it wears down a little every season)." % b.facilities_level))
	quality.add_child(FcUiTables.button("Invest in arena (+10)", func():
		_say("Arena improved." if controller.invest_in_facilities(10) else "Not enough cash for that.")
		show_dashboard()))
	arena_page.add_child(quality)
	var build := HBoxContainer.new()
	build.add_child(FcUiTables.label("Building project:"))
	var options := controller.arena_project_options()
	var project_pick := OptionButton.new()
	project_pick.tooltip_text = "Arena projects are paid up front and finish after a few seasons. Each kind can run once at a time."
	for o in options:
		project_pick.add_item("%s (%s, %d season%s)%s" % [o["name"], FcUiTables.money(o["cost"]), o["seasons"], "" if o["seasons"] == 1 else "s", " - under way" if o["running"] else ""])
	build.add_child(project_pick)
	build.add_child(FcUiTables.button("Start project", func():
		var r := controller.start_arena_project(options[project_pick.selected]["key"])
		_say(r["reason"])
		if r["ok"]:
			show_dashboard()))
	arena_page.add_child(build)
	arena_page.add_child(FcUiTables.label("Built so far: arena suites level %d, practice facility level %d, medical center level %d." % [b.suites_level, b.practice_level, b.medical_level]))
	for o in options:
		var line := FcUiTables.label("%s: %s" % [o["name"], o["description"]])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(200, 0)
		arena_page.add_child(line)

	var pages := TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["Summary", summary], ["Prices and shop", pricing], ["Sponsors and loans", money], ["Arena and facilities", arena_page]]:
		entry[1].name = entry[0]
		pages.add_child(entry[1])
	pages.current_tab = clampi(_last_finance_page, 0, pages.get_tab_count() - 1)
	pages.tab_changed.connect(func(i): _last_finance_page = i)
	return pages


func _tab_staff() -> Control:
	var box := VBoxContainer.new()   # the "People" page
	var front := VBoxContainer.new()   # the "Front office" page
	var w := controller.state.world
	var tid := controller.state.user_team_id
	var rows: Array = []
	var ids: Array[int] = []
	for sc in w.staff_contracts_of_team(tid):
		var m: FcStaffMember = w.staff.get_by_id(sc.staff_id)
		rows.append([FcStaffRole.display_name(sc.role), m.identity.full_name(), m.reputation, m.experience_years, FcUiTables.money(sc.salary_for(controller.state.current_season)), sc.end_season()])
		ids.append(m.id)
	if controller.state.mode == FcGameState.MODE_OWNER:
		var chemistry := controller.staff_chemistry()
		front.add_child(FcUiTables.label("Staff chemistry: %d / 100 (%s)" % [chemistry["score"], chemistry["label"]], 18, true))
		front.add_child(FcUiTables.label("It moves how fast your players develop (%+.1f coaching points now)." % chemistry["development_bonus"], 14))
		for part in chemistry["parts"]:
			front.add_child(FcUiTables.label("%s: %d. %s" % [part["name"], roundi(part["value"]), part["note"]], 14))
		front.add_child(FcUiTables.label("Front office: what your general manager handles", 18, true))
		var gm := controller.gm_summary()
		if gm.is_empty():
			front.add_child(FcUiTables.label("You have no general manager, so you decide everything yourself. Hire one below."))
		else:
			front.add_child(FcUiTables.label("%s (talent evaluation %d, negotiation %d). A sharper eye means better re-signing, drafting and signings; leave an area unticked to decide it yourself." % [gm["name"], gm["talent_evaluation"], gm["negotiation"]]))
			var checks := HBoxContainer.new()
			for entry in [["contracts", "Re-sign my players"], ["draft", "Run the draft"], ["free_agency", "Sign free agents"], ["trades", "Make trades"], ["injuries", "Replace injured players"]]:
				var check := Button.new()
				check.toggle_mode = true
				check.button_pressed = controller.delegation_on(entry[0])
				check.tooltip_text = {"contracts": "Your general manager re-signs the players you would keep, at fair terms.", "draft": "Your general manager picks for you in the draft, using the scouts' board.", "free_agency": "Your general manager signs free agents within the budget you set.", "trades": "Your general manager looks for trades that fit your philosophy.", "injuries": "Your general manager signs replacements when injuries leave you short."}.get(entry[0], "")
				var title: String = entry[1]
				check.text = ("[x] " if check.button_pressed else "[ ] ") + title
				check.toggled.connect(func(on):
					controller.set_delegation(entry[0], on)
					check.text = ("[x] " if on else "[ ] ") + title)
				checks.add_child(check)
			front.add_child(checks)
			var direction_row := HBoxContainer.new()
			direction_row.add_child(FcUiTables.label("Philosophy:"))
			var philosophy_pick := OptionButton.new()
			philosophy_pick.tooltip_text = "Tells your general manager what to value: win now (today's ability, veterans), balanced, or rebuild (youth and potential)."
			for name in ["Win now (value today's ability, buy veterans)", "Balanced", "Rebuild (value youth and potential, sell veterans)"]:
				philosophy_pick.add_item(name)
			philosophy_pick.selected = FcGameState.PHILOSOPHIES.find(controller.philosophy())
			direction_row.add_child(philosophy_pick)
			direction_row.add_child(FcUiTables.label("   Budget:"))
			var budget_pick := OptionButton.new()
			budget_pick.tooltip_text = "How much payroll your general manager may commit: frugal stays below the cap, normal uses it, aggressive goes above it but under the tax line."
			for name in ["Frugal (92% of the cap)", "Normal (the cap)", "Aggressive (up to 115%, below the tax line)"]:
				budget_pick.add_item(name)
			budget_pick.selected = FcGameState.BUDGETS.find(controller.state.direction["budget"])
			direction_row.add_child(budget_pick)
			var apply_direction := func(_i):
				controller.set_direction(FcGameState.PHILOSOPHIES[philosophy_pick.selected], FcGameState.BUDGETS[budget_pick.selected])
				_say("Direction set. Your general manager follows it when he re-signs, drafts, trades and signs players (only in the areas ticked above).")
			philosophy_pick.item_selected.connect(apply_direction)
			budget_pick.item_selected.connect(apply_direction)
			front.add_child(direction_row)
			var card := controller.gm_report()
			if not card.is_empty():
				front.add_child(FcUiTables.label("Last season: %s. %d wins (about %d expected), payroll %s against a budget of %s." % [card["grade"], card["wins"], card["expected_wins"], FcUiTables.money(card["payroll"]), FcUiTables.money(card["limit"])]))
	box.add_child(FcUiTables.label("Your staff", 18, true))
	var table := FcUiTables.table(["Role", "Name", "Reputation", "Experience", "Salary", "Through"], rows)
	box.add_child(table)
	if controller.state.mode == FcGameState.MODE_OWNER:
		var row := HBoxContainer.new()
		row.add_child(FcUiTables.button("Fire selected", func():
			var item := table.get_selected()
			if item != null and controller.fire_staff(ids[item.get_index()]):
				_say("Fired.")
			show_dashboard()))
		var role_picker := OptionButton.new()
		role_picker.tooltip_text = "The job you want to fill. A general manager and head coach are one each; you can have several assistants and scouts."
		for role in [FcStaffRole.Id.GENERAL_MANAGER, FcStaffRole.Id.HEAD_COACH, FcStaffRole.Id.ASSISTANT_COACH, FcStaffRole.Id.SCOUT, FcStaffRole.Id.MEDICAL, FcStaffRole.Id.BUSINESS_EXECUTIVE]:
			role_picker.add_item(FcStaffRole.display_name(role))
			role_picker.set_item_metadata(role_picker.item_count - 1, role)
		var person_picker := OptionButton.new()
		person_picker.tooltip_text = "Available people with their reputation, asking salary and the staff chemistry you would have if you hired them."
		var fill := func():
			person_picker.clear()
			var role: int = role_picker.get_item_metadata(role_picker.selected)
			for m in controller.staff_pool(role).slice(0, 12):
				person_picker.add_item("%s (rep %d, %s, staff chemistry would be %d)" % [m.identity.full_name(), m.reputation, FcUiTables.money(controller.asking_salary(m.id)), controller.staff_chemistry(m.id, role)["score"]])
				person_picker.set_item_metadata(person_picker.item_count - 1, m.id)
		role_picker.item_selected.connect(func(_i): fill.call())
		fill.call()
		row.add_child(FcUiTables.label("Hire a"))
		row.add_child(role_picker)
		row.add_child(person_picker)
		var hire_salary := SpinBox.new()
		hire_salary.tooltip_text = "The yearly salary you offer, in millions. A person accepts a little less than they ask, and a better negotiating general manager gets a bigger discount."
		hire_salary.min_value = 0.05
		hire_salary.max_value = 30
		hire_salary.step = 0.05
		var hire_years := SpinBox.new()
		hire_years.tooltip_text = "Contract length in years. Longer deals make people accept a slightly lower salary."
		hire_years.min_value = 1
		hire_years.max_value = 5
		hire_years.value = 3
		var sync_offer := func(_i = 0):
			if person_picker.item_count > 0:
				hire_salary.value = controller.asking_salary(person_picker.get_item_metadata(person_picker.selected)) / 1e6
		person_picker.item_selected.connect(sync_offer)
		role_picker.item_selected.connect(func(_i): sync_offer.call())
		sync_offer.call()
		row.add_child(FcUiTables.label("$M"))
		row.add_child(hire_salary)
		row.add_child(FcUiTables.label("years"))
		row.add_child(hire_years)
		row.add_child(FcUiTables.button("Hire", func():
			if person_picker.item_count == 0:
				return
			var error := controller.hire_staff(person_picker.get_item_metadata(person_picker.selected), role_picker.get_item_metadata(role_picker.selected), int(hire_years.value), roundi(hire_salary.value * 1e6))
			_say("Hired." if error == "" else error)
			if error == "":
				show_dashboard()))
		box.add_child(row)
		var extend_row := HBoxContainer.new()
		extend_row.add_child(FcUiTables.label("Contract extension for the selected staff member: $M"))
		var ext_pay := SpinBox.new()
		ext_pay.tooltip_text = "The yearly salary you offer, in millions, to keep this staff member."
		ext_pay.min_value = 0.05
		ext_pay.max_value = 30
		ext_pay.step = 0.05
		var ext_len := SpinBox.new()
		ext_len.tooltip_text = "Length of the new contract in years."
		ext_len.min_value = 1
		ext_len.max_value = 5
		ext_len.value = 3
		table.item_selected.connect(func():
			var picked := table.get_selected()
			if picked != null:
				ext_pay.value = controller.asking_salary(ids[picked.get_index()]) / 1e6)
		extend_row.add_child(ext_pay)
		extend_row.add_child(FcUiTables.label("years"))
		extend_row.add_child(ext_len)
		extend_row.add_child(FcUiTables.button("Extend staff contract", func():
			var item2 := table.get_selected()
			if item2 == null:
				_say("Select a staff member first.")
				return
			var r := controller.extend_staff(ids[item2.get_index()], roundi(ext_pay.value * 1e6), int(ext_len.value))
			_say(r["reason"])))
		box.add_child(extend_row)
	if controller.state.mode != FcGameState.MODE_OWNER:
		return box
	var pages := TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["Front office", front], ["People", box]]:
		entry[1].name = entry[0]
		pages.add_child(entry[1])
	pages.current_tab = clampi(_last_staff_page, 0, 1)
	pages.tab_changed.connect(func(i): _last_staff_page = i)
	return pages


func _tab_news() -> Control:
	var w := controller.state.world
	var rows: Array = []
	var items: Array = w.news.duplicate()
	items.reverse()
	var mine := controller.state.user_team_id
	for item in items.slice(0, 80):
		var tag: String = {"injury": "Injury", "milestone": "Milestone", "champion": "Champions", "award": "Award", "signing": "Signing", "retirement": "Retirement", "draft": "Draft", "staff": "Staff"}.get(item["kind"], "News")
		rows.append([item["date"], tag, ("* " if item["team"] == mine else "") + item["text"]])
	return FcUiTables.table(["Date", "Type", "Headline"], rows, [100, 90, 0])


func _tab_league() -> Control:
	var box := VBoxContainer.new()
	var w := controller.state.world
	var s := controller.season()
	var stats := s.stats
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["Points", "points"], ["Rebounds", "rebounds"], ["Assists", "ast"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("%s per game" % entry[0], 18, true))
		var rows: Array = []
		var min_games := maxi(1, floori(controller.season().next_day / 4.0)) if s.status == FcSeason.Status.REGULAR else 20
		for pid in stats.leaders(entry[1], mini(min_games, 20), 10):
			var l: Dictionary = stats.lines[pid]
			var t: FcTeam = w.teams.get_by_id(l["team"])
			rows.append([l["name"], t.identity.abbreviation if t != null else "", "%.1f" % stats.per_game(pid, entry[1])])
		col.add_child(FcUiTables.table(["Player", "Team", entry[0]], rows, [0, 50, 60]))
		row.add_child(col)
	box.add_child(row)
	var history: Array = []
	for season in w.seasons.all():
		if season.status == FcSeason.Status.COMPLETE:
			history.append(["%d-%02d" % [season.year, (season.year + 1) % 100], _team_name(season.champion_id), _team_name(season.runner_up_id),
				_player_name(season.awards.get("mvp", 0))])
	history.reverse()
	box.add_child(FcUiTables.label("Champions", 18, true))
	box.add_child(FcUiTables.table(["Season", "Champion", "Runner-up", "MVP"], history))
	var all_time := HBoxContainer.new()
	all_time.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label("All-time %s" % entry[1].to_lower(), 18, true))
		var leader_rows: Array = []
		for pid in w.career_leaders(entry[0], 8):
			var totals := w.career_totals(pid)
			var p: FcPlayer = w.players.get_by_id(pid)
			leader_rows.append([p.identity.full_name() + ("" if p.status == FcPlayer.Status.RETIRED else " *"), totals["seasons"], totals[entry[0]]])
		col.add_child(FcUiTables.table(["Player (* active)", "Seasons", entry[1]], leader_rows, [0, 70, 80]))
		all_time.add_child(col)
	box.add_child(all_time)
	return box


func _player_name(player_id: int) -> String:
	var p: FcPlayer = controller.state.world.players.get_by_id(player_id)
	return p.identity.full_name() if p != null else "-"
