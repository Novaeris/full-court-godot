extends FcTestCase
## The Phase 3 shell (docs/UI_POLISH_PLAN.md): the layout profile, the navigator, the notifier, the dialog stack, the frame, the
## navigation bar, and how FcApp uses them (Back, skins, Settings, confirmed delete, desktop and mobile Dynasty navigation).
## Timing, keys and focus are tested in tests/live/test_live_shell.gd.

const SAVE_DIR := "user://test_saves_shell"
const DYNASTY_DIR := "user://test_dynasty_shell"
const PREFS := "user://test_prefs_shell.cfg"

var host: Control
var app: FcApp


func before_each() -> void:
	host = Control.new()
	Engine.get_main_loop().root.add_child(host)


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)
	Engine.get_main_loop().root.remove_child(host)
	host.free()
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	FcSafeFile.remove_tree(SAVE_DIR)
	FcSafeFile.remove_tree(DYNASTY_DIR)
	FcDynastyFixture.wipe()
	DirAccess.remove_absolute(PREFS)


func _make_app() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new(SAVE_DIR)
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	if node is Button:
		text += "[" + (node as Button).text + "]\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


# --- layout profile ---------------------------------------------------------------------------------------------------

func test_a_desktop_window_is_desktop_whatever_its_width() -> void:
	for width in [500, 800, 1280, 2560]:
		assert_eq(FcLayoutProfile.classify(Vector2(width, 800), false, false)["mode"], FcLayoutProfile.DESKTOP, "%d px, no touch" % width)


func test_touch_screens_are_mobile_only_when_the_window_is_narrow() -> void:
	assert_eq(FcLayoutProfile.classify(Vector2(412, 915), false, true)["mode"], FcLayoutProfile.MOBILE, "a phone-sized window with touch")
	assert_eq(FcLayoutProfile.classify(Vector2(1280, 800), false, true)["mode"], FcLayoutProfile.DESKTOP, "a big touch laptop is desktop")
	assert_eq(FcLayoutProfile.classify(Vector2(1920, 1080), true, true)["mode"], FcLayoutProfile.MOBILE, "a mobile operating system is always mobile")


func test_the_player_can_force_a_layout() -> void:
	assert_eq(FcLayoutProfile.classify(Vector2(1280, 800), false, false, FcLayoutProfile.MOBILE)["mode"], FcLayoutProfile.MOBILE)
	assert_eq(FcLayoutProfile.classify(Vector2(412, 915), true, true, FcLayoutProfile.DESKTOP)["mode"], FcLayoutProfile.DESKTOP)
	assert_eq(FcLayoutProfile.classify(Vector2(412, 915), false, true, "nonsense")["mode"], FcLayoutProfile.MOBILE, "an unknown choice behaves like automatic")


func test_size_classes_have_clear_boundaries() -> void:
	assert_eq(FcLayoutProfile.classify(Vector2(699, 800), false, false)["size_class"], FcLayoutProfile.COMPACT)
	assert_eq(FcLayoutProfile.classify(Vector2(700, 800), false, false)["size_class"], FcLayoutProfile.REGULAR)
	assert_eq(FcLayoutProfile.classify(Vector2(1099, 800), false, false)["size_class"], FcLayoutProfile.REGULAR)
	assert_eq(FcLayoutProfile.classify(Vector2(1100, 800), false, false)["size_class"], FcLayoutProfile.WIDE)


func test_the_profile_announces_only_real_changes() -> void:
	var p := FcLayoutProfile.new()
	var seen := []
	p.changed.connect(func(profile: FcLayoutProfile) -> void: seen.append(profile.mode + "/" + profile.size_class))
	assert_true(p.update(Vector2(1280, 800)), "regular to wide is a change")
	assert_true(not p.update(Vector2(1300, 900)), "the same class again is not")
	p.touch_available = true
	assert_true(p.update(Vector2(412, 915)))
	assert_true(p.is_mobile() and p.is_compact())
	assert_eq(seen, ["desktop/wide", "mobile/compact"])
	p.override = FcLayoutProfile.DESKTOP
	assert_true(p.update(Vector2(412, 915)), "the override changes the mode")
	assert_true(not p.is_mobile())


func test_safe_margins_come_from_the_safe_area() -> void:
	var m := FcLayoutProfile.safe_margins(Rect2i(0, 48, 1080, 2200), Vector2i(1080, 2400))
	assert_eq(m, {"left": 0, "top": 48, "right": 0, "bottom": 152}, "a notch on top and a gesture bar below")
	assert_eq(FcLayoutProfile.safe_margins(Rect2i(30, 0, 1000, 800), Vector2i(1080, 800))["right"], 50, "a rounded corner on the sides")
	assert_eq(FcLayoutProfile.safe_margins(Rect2i(0, 0, 0, 0), Vector2i(1080, 2400)), {"left": 0, "top": 0, "right": 0, "bottom": 0}, "an empty area gives no margins")
	assert_eq(FcLayoutProfile.safe_margins(Rect2i(-10, -10, 2000, 3000), Vector2i(1080, 2400))["bottom"], 0, "margins are never negative")


# --- navigator --------------------------------------------------------------------------------------------------------

func test_the_navigator_knows_where_back_goes() -> void:
	var nav := FcNavigator.new()
	var log: Array = []
	assert_true(nav.enter("menu"), "the first screen is new")
	assert_true(not nav.can_go_back() and not nav.go_back(), "the menu has no Back")
	assert_true(nav.enter("career_home", func() -> void: log.append("to menu")), "a different screen")
	assert_true(nav.can_go_back())
	assert_true(nav.go_back())
	assert_eq(log, ["to menu"])
	assert_true(not nav.enter("career_home", func() -> void: log.append("again")), "the same screen again is not new")
	assert_eq(nav.trail(), ["menu", "career_home"], "the trail records each screen once")


func test_the_navigator_can_show_a_screen_again() -> void:
	var nav := FcNavigator.new()
	var log: Array = []
	nav.enter("hub", Callable(), func() -> void: log.append("rebuilt"))
	assert_true(nav.can_rebuild() and nav.rebuild())
	assert_eq(log, ["rebuilt"])
	nav.enter("plain")
	assert_true(not nav.can_rebuild() and not nav.rebuild(), "a screen that offers no rebuild is left alone")


func test_the_navigator_trail_is_capped_and_announces_screens() -> void:
	var nav := FcNavigator.new()
	var announced: Array = []
	nav.entered.connect(func(id: String) -> void: announced.append(id))
	for i in FcNavigator.TRAIL_LIMIT + 10:
		nav.enter("screen_%d" % i)
	assert_eq(nav.trail().size(), FcNavigator.TRAIL_LIMIT)
	assert_eq(nav.trail().back(), "screen_%d" % (FcNavigator.TRAIL_LIMIT + 9))
	assert_eq(announced.size(), FcNavigator.TRAIL_LIMIT + 10)


# --- notifier ---------------------------------------------------------------------------------------------------------

func test_messages_are_classified_by_their_words() -> void:
	assert_eq(FcNotifier.classify("Cannot create this league: a name is needed"), FcToast.Kind.ERROR)
	assert_eq(FcNotifier.classify("The save could not be written"), FcToast.Kind.ERROR)
	assert_eq(FcNotifier.classify("Not enough credits"), FcToast.Kind.ERROR)
	assert_eq(FcNotifier.classify("Saved."), FcToast.Kind.SUCCESS)
	assert_eq(FcNotifier.classify("Player created."), FcToast.Kind.SUCCESS)
	assert_eq(FcNotifier.classify("Select a player first"), FcToast.Kind.INFO)


func test_the_notifier_keeps_a_capped_history_and_ignores_empty_messages() -> void:
	var n := FcNotifier.new()
	n.say("   ")
	n.say("")
	assert_eq(n.history.size(), 0, "nothing to say, nothing recorded")
	for i in FcNotifier.HISTORY_LIMIT + 5:
		n.info("message %d" % i)
	assert_eq(n.history.size(), FcNotifier.HISTORY_LIMIT)
	assert_eq(n.last()["text"], "message %d" % (FcNotifier.HISTORY_LIMIT + 4))
	n.error("Broken")
	assert_eq(n.last()["kind"], FcToast.Kind.ERROR)
	assert_eq(FcNotifier.new().last(), {}, "no messages yet")


func test_long_messages_stay_longer() -> void:
	assert_eq(FcToast.hold_seconds(FcToast.Kind.INFO, 10), 3.0)
	assert_true(FcToast.hold_seconds(FcToast.Kind.INFO, 140) > 3.0, "a long message gets more time")
	assert_true(FcToast.hold_seconds(FcToast.Kind.ERROR, 1000) <= 11.0, "but never an endless one")


# --- dialog stack and frame -------------------------------------------------------------------------------------------

func test_dialogs_stack_and_only_the_top_one_listens() -> void:
	var modals := FcModalHost.new()
	host.add_child(modals)
	var results: Array = []
	var first := modals.confirm("First", "", func() -> void: results.append("first"))
	var second := modals.confirm("Second", "", func() -> void: results.append("second"), true)
	assert_eq(modals.count(), 2)
	assert_true(modals.top() == second)
	assert_eq(first.process_mode, Node.PROCESS_MODE_DISABLED, "the dialog beneath is paused")
	second.close(false)
	assert_eq(modals.count(), 1, "closing the top one leaves the other")
	assert_eq(first.process_mode, Node.PROCESS_MODE_INHERIT, "and wakes it up again")
	first.confirm_button.pressed.emit()
	assert_eq(results, ["first"], "only the confirmed dialog ran its action")
	assert_eq(modals.count(), 0)
	assert_true(modals.top() == null)
	assert_eq(modals.mouse_filter, Control.MOUSE_FILTER_IGNORE, "an empty layer never blocks the screen")


func test_closing_all_dialogs_cancels_them() -> void:
	var modals := FcModalHost.new()
	host.add_child(modals)
	var cancelled: Array = []
	for i in 3:
		var m := modals.confirm("Dialog %d" % i, "", func() -> void: pass)
		m.cancelled.connect(func() -> void: cancelled.append(i))
	modals.close_all()
	assert_eq(modals.count(), 0)
	assert_eq(cancelled.size(), 3)
	modals.notice("Info", "Hello")
	assert_eq(modals.count(), 1)


func test_the_frame_scrolls_sideways_instead_of_clipping() -> void:
	var frame := FcScreenHost.new()
	host.add_child(frame)
	var scroll := frame.content.get_parent() as ScrollContainer
	assert_true(scroll != null, "the screen column sits in a scroll area")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "a wide screen scrolls sideways")
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "screens manage their own vertical scrolling")
	assert_true(frame.content.size_flags_vertical & Control.SIZE_EXPAND != 0 and frame.content.size_flags_horizontal & Control.SIZE_EXPAND != 0, "and the column fills the area (a ScrollContainer only stretches children that expand)")


func test_the_frame_applies_safe_margins_and_the_skin_backdrop() -> void:
	var frame := FcScreenHost.new()
	host.add_child(frame)
	frame.set_safe_margins({"left": 0, "top": 48, "right": 0, "bottom": 34})
	var margin := frame.content.get_parent().get_parent() as MarginContainer
	assert_eq(margin.get_theme_constant("margin_top"), FcScreenHost.BASE_MARGIN + 48)
	assert_eq(margin.get_theme_constant("margin_left"), FcScreenHost.BASE_MARGIN)
	for skin in FcModeSkin.ids():
		frame.set_skin(FcModeSkin.resolve(skin))
		assert_eq(frame.backdrop_style(), FcModeSkin.resolve(skin)["background"], "%s backdrop" % skin)


func test_the_bottom_bar_sits_in_the_frame_and_lifts_the_toasts() -> void:
	var frame := FcScreenHost.new()
	host.add_child(frame)
	var before := frame.toasts.offset_bottom
	var bar := Label.new()
	frame.set_bottom_bar(bar)
	assert_true(bar.get_parent() == frame.bottom_slot, "the bar is part of the frame, not of a screen")
	assert_true(frame.toasts.offset_bottom < before, "toasts move up so they do not cover it")
	frame.set_bottom_bar(null)
	assert_eq(frame.bottom_slot.get_child_count(), 0, "removing the bar empties the slot")
	assert_eq(frame.toasts.offset_bottom, before)


# --- navigation bar ---------------------------------------------------------------------------------------------------

const ITEMS := [["a", "Alpha", "house"], ["b", "Beta", "layers"], ["c", "Gamma", "package"], ["d", "Delta", "play"], ["e", "Epsilon", "star"], ["f", "Zeta", "trophy"]]


func test_desktop_navigation_shows_every_item_as_tabs() -> void:
	var nav := FcNavBar.new()
	host.add_child(nav)
	nav.setup(ITEMS, "b", false)
	assert_eq(nav.visible_ids().size(), 6, "all items are visible on desktop")
	assert_eq(nav.overflow_ids(), [], "nothing hides under More")
	assert_true(nav.more_button() == null)
	assert_eq(_find(nav, FcTabBar).size(), 1, "a tab bar")
	assert_eq(nav.current_id, "b")


func test_mobile_navigation_keeps_the_main_items_and_puts_the_rest_under_more() -> void:
	var nav := FcNavBar.new()
	host.add_child(nav)
	nav.setup(ITEMS, "a", true, ["a", "b", "c"])
	assert_eq(nav.visible_ids(), ["a", "b", "c"])
	assert_eq(nav.overflow_ids(), ["d", "e", "f"])
	assert_true(nav.more_button() != null, "a More button for the rest")
	assert_true(nav.button_for("a").custom_minimum_size.y >= FcUiTokens.TOUCH_TARGET, "every target is at least 44 px tall")
	assert_eq(nav.button_for("a").theme_type_variation, "NavButton")
	var default_nav := FcNavBar.new()
	host.add_child(default_nav)
	default_nav.setup(ITEMS, "a", true)
	assert_eq(default_nav.visible_ids().size(), FcNavBar.MAX_BOTTOM_ITEMS, "without a list, the first four stay")


func test_navigation_emits_only_when_the_player_picks_something_new() -> void:
	var nav := FcNavBar.new()
	host.add_child(nav)
	nav.setup(ITEMS, "a", true, ["a", "b", "c"])
	var picked: Array = []
	nav.selected.connect(func(id: String) -> void: picked.append(id))
	nav.select("b")
	assert_eq(picked, [], "select() is silent")
	nav.button_for("c").pressed.emit()
	assert_eq(picked, ["c"])
	nav.button_for("c").pressed.emit()
	assert_eq(picked, ["c"], "the open item again does nothing")
	nav._menu.index_pressed.emit(1)
	assert_eq(picked, ["c", "e"], "an item from the More menu is picked the same way")
	assert_true(nav.more_button().button_pressed, "More shows as open while an item from it is open")


func test_the_same_items_work_on_both_targets() -> void:
	var nav := FcNavBar.new()
	host.add_child(nav)
	nav.setup(ITEMS, "d", false)
	var picked: Array = []
	nav.selected.connect(func(id: String) -> void: picked.append(id))
	nav.button_for("e").pressed.emit()
	assert_eq(picked, ["e"], "desktop tabs emit the same signal")
	nav.setup(ITEMS, "e", true, ["a", "b"])
	assert_eq(nav.current_id, "e", "switching target keeps the open item")


func test_dynasty_tabs_all_have_icons_and_the_mobile_set_is_valid() -> void:
	var ids: Array = []
	for entry in FcDynastyUi.TABS:
		ids.append(entry[0])
		assert_true(FcUiIcons.has_icon(str(entry[2])), "icon for " + str(entry[0]))
	for id in FcDynastyUi.MOBILE_PRIMARY:
		assert_true(id in ids, "mobile primary tab %s exists" % id)
	assert_true(FcDynastyUi.MOBILE_PRIMARY.size() <= FcNavBar.MAX_BOTTOM_ITEMS)


# --- the app on the shell ----------------------------------------------------------------------------------------------

func test_back_goes_to_the_parent_screen() -> void:
	_make_app()
	assert_true(not app.go_back(), "the main menu has nowhere to go back to")
	app.show_career_home()
	assert_true(app.navigator.can_go_back())
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "menu")
	app.show_career_creator()
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "career_home", "the creator goes back to the Career home")
	app.show_settings()
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "menu")
	app.show_about()
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "menu")


func test_back_closes_an_open_dialog_before_leaving_the_screen() -> void:
	_make_app()
	app.show_career_home()
	app.host.modals.notice("Hello", "A dialog")
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "career_home", "the first Back only closes the dialog")
	assert_eq(app.host.modals.count(), 0)
	assert_true(app.go_back())
	assert_eq(app.navigator.current_id, "menu", "the second one leaves the screen")


func test_each_mode_gets_its_own_presentation_skin() -> void:
	_make_app()
	assert_eq(app._skin["id"], FcModeSkin.NEUTRAL, "the main menu")
	app.show_career_home()
	assert_eq(app._skin["id"], FcModeSkin.BROADCAST, "Career uses the Broadcast skin (D7)")
	app.show_new_league()
	assert_eq(app._skin["id"], FcModeSkin.FRANCHISE, "Owner screens use the Franchise skin")
	assert_eq(app.host.backdrop_style(), "flat")
	app.show_career_home()
	assert_eq(app.host.backdrop_style(), "grid", "Broadcast draws the grid")
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY_DIR))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Skin Kings", "SKN")
	assert_eq(app._skin["id"], FcModeSkin.COLLECTIBLE, "Dynasty uses the Collectible skin")
	assert_eq(app.host.backdrop_style(), "spotlight")
	app.show_main_menu()
	assert_eq(app._skin["id"], FcModeSkin.NEUTRAL, "and the menu goes back to neutral")


func test_the_owner_dashboard_uses_the_franchise_colours_and_a_letterhead() -> void:
	_make_app()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Shell League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	assert_eq(app._skin["id"], FcModeSkin.FRANCHISE)
	assert_eq(_find(app, FcLetterhead).size(), 1, "the team letterhead heads the dashboard")
	assert_true(FcUiContrast.ratio(app._skin["accent"], FcUiTokens.SURFACE_RAISED) >= 4.5, "whatever the team colour, the accent stays readable")
	app.go_back()
	assert_eq(app.host.modals.count(), 1, "Back from a game in progress asks first")
	assert_eq(app.navigator.current_id, "dashboard", "and stays put until the player agrees")
	app.host.modals.top().confirm_button.pressed.emit()
	assert_eq(app.navigator.current_id, "menu")


func test_messages_become_toasts_and_stay_readable_for_tests() -> void:
	_make_app()
	app._say("Saved.")
	assert_eq(app._message.text, "Saved.", "the latest message is still available as text")
	assert_true(not app._message.visible, "but it is not drawn: the toast is what the player sees")
	assert_eq(app.notifier.last(), {"kind": FcToast.Kind.SUCCESS, "text": "Saved."})
	app.notify(FcToast.Kind.ERROR, "Nope")
	assert_eq(app.notifier.last()["kind"], FcToast.Kind.ERROR)
	assert_eq(app._message.text, "Nope")


func test_the_main_menu_fits_a_phone_and_keeps_its_buttons() -> void:
	_make_app()
	app.show_main_menu()
	var text := _labels_text(app)
	for expected in ["FULL COURT", "[Owner Mode]", "[Career Mode]", "[Dynasty Mode]", "[Settings]", "[About, licenses and logs]", "[Quit]"]:
		assert_true(expected in text, "the menu shows " + expected)
	assert_true(app._root.get_combined_minimum_size().x + 32 < 460, "three mode cards stack: the menu needs well under 460 px (it was 820)")


func test_settings_change_the_text_size_motion_and_layout() -> void:
	_make_app()
	app.show_settings()
	var groups := _find(app, FcChoiceGroup)
	assert_eq(groups.size(), 2, "text size and layout")
	(groups[0] as FcChoiceGroup).selected.emit("2")
	assert_eq(app.preferences.text_size, 2, "Large text is remembered")
	assert_eq(app.navigator.current_id, "settings", "and the screen shows again")
	groups = _find(app, FcChoiceGroup)
	(groups[1] as FcChoiceGroup).selected.emit("mobile")
	assert_eq(app.preferences.layout_override, "mobile")
	assert_eq(FcPreferences.new(PREFS).layout_override, "mobile", "saved to the settings file")
	assert_true(app.layout.is_mobile(), "and applied at once")
	var toggles := _find(app, FcToggle)
	(toggles[0] as FcToggle).button_pressed = true
	assert_true(app.preferences.reduce_motion and FcMotion.reduced, "Reduce motion applies at once")


func test_an_invalid_layout_setting_falls_back_to_automatic() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "layout", "sideways")
	cfg.save(PREFS)
	assert_eq(FcPreferences.new(PREFS).layout_override, "auto")
	DirAccess.remove_absolute(PREFS)


func test_deleting_a_save_asks_first() -> void:
	_make_app()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Delete League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_save()
	app.show_main_menu()
	var saved := app.saves.list_slots().size()
	assert_true(saved >= 1, "there is a save to delete")
	app.request_delete_selected()
	assert_eq(app.host.modals.count(), 1, "a dialog asks")
	assert_eq(app.saves.list_slots().size(), saved, "nothing is deleted yet")
	assert_true(app.host.modals.top().cancel_button.has_focus() or app.host.modals.top().kind == FcModal.Kind.DESTRUCTIVE, "it is a destructive dialog (focus starts on Cancel)")
	app.host.modals.top().cancel_button.pressed.emit()
	assert_eq(app.saves.list_slots().size(), saved, "cancelling keeps the save")
	app.request_delete_selected()
	app.host.modals.top().confirm_button.pressed.emit()
	assert_eq(app.saves.list_slots().size(), saved - 1, "confirming deletes exactly one save")


func test_dynasty_uses_top_tabs_on_desktop_and_a_bottom_bar_on_mobile() -> void:
	_make_app()
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY_DIR))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	app.dynasty_ui.on_create("Nav Kings", "NAV")
	assert_eq(app.host.bottom_slot.get_child_count(), 0, "desktop: no bottom bar")
	assert_eq(_find(app._root, FcTabBar).size(), 1, "desktop: tabs along the top")
	app.layout.override = FcLayoutProfile.MOBILE
	app.layout.update(Vector2(412, 915))
	assert_true(FcUiTokens.touch_mode, "mobile turns on the touch sizing")
	app.dynasty_ui.show_tab("collection")
	assert_true(app.host.bottom_slot.get_child_count() > 0, "mobile: the navigation bar is in the frame")
	var nav: FcNavBar = _find(app.host.bottom_slot, FcNavBar)[0]
	assert_eq(nav.visible_ids(), FcDynastyUi.MOBILE_PRIMARY)
	assert_eq(nav.current_id, "collection")
	assert_eq(_find(app._root, FcTabBar).size(), 0, "mobile: no top tabs")
	nav.button_for("packs").pressed.emit()
	assert_eq(app.dynasty_ui.tab, "packs", "the bottom bar navigates")
	assert_eq(app.navigator.current_id, "dynasty_packs")
	assert_true(app.go_back() and app.dynasty_ui.tab == "hub", "Back from a tab returns to the Dynasty hub")
	app.go_back()
	assert_eq(app.navigator.current_id, "dynasty_entry", "and Back from the hub saves and returns to the team list")
	assert_true(app.dynasty_ui.on_create("Nav Kings Too", "NV2"), "open a team again")
	app.layout.override = FcLayoutProfile.DESKTOP
	app.layout.update(Vector2(1280, 800))
	app.dynasty_ui.show_tab("hub")
	assert_eq(app.host.bottom_slot.get_child_count(), 0, "back on desktop the bottom bar is removed")


func test_touch_layouts_enlarge_the_stock_buttons_too() -> void:
	var desktop := FcUiTheme.build(1)
	var small := desktop.get_stylebox("normal", "Button").get_minimum_size().y
	FcUiTokens.touch_mode = true
	var touch := FcUiTheme.build(1)
	assert_true(touch.get_stylebox("normal", "Button").get_minimum_size().y > small, "older screens' buttons grow with the touch layout")
	assert_true(touch.get_stylebox("normal", "Button").get_minimum_size().y + 15 >= FcUiTokens.TOUCH_TARGET - 8, "to roughly 44 px with the text")


func test_the_highlighted_saved_game_is_the_one_that_loads() -> void:
	# regression: Load always used the dropdown's first entry, whatever row the player clicked in the table
	_make_app()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Pick League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_save()
	assert_true(app.saves.save("second_slot", app.controller.state, "Second").is_ok(), "a second save")
	app.show_main_menu()
	var slots := app.saves.list_slots()
	assert_true(slots.size() >= 2, "two saves to choose from")
	var tree: Tree = _find(app, Tree)[0]
	var picker: OptionButton = app._form["slot"]
	assert_eq(picker.get_item_text(picker.selected), slots[0].slot_id, "the first row starts highlighted and chosen")
	tree.get_root().get_child(1).select(0)
	assert_eq(picker.get_item_text(picker.selected), slots[1].slot_id, "clicking the second row chooses the second save")
