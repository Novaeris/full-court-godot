extends SceneTree
## Renders the real UI in a window and saves a PNG so the screens can be looked at.
## NOT headless: run with a window, e.g.
##   godot_console --path . --script res://tools/screenshot.gd -- screen=Roster out=C:/temp/roster.png days=20
## screen:
##   menu | settings | new_league | career_menu | career_creator | career_hub
##   Overview | Standings | Schedule | Roster | Finances | Staff | Market | Trades | History | News | League   (Owner tabs)
##   dynasty_entry | dynasty_hub | dynasty_collection | dynasty_lineup | dynasty_packs | dynasty_reveal | dynasty_market | dynasty_play
##   gallery  (the development-only Component Gallery)
## days: how many days to play first (Owner screens, so tables have data).
## size=1024x700 (default 1280x800): the window size to render at.
## stretch=off (default): logical pixels equal window pixels, so a 412x915 window shows a true 412-wide layout; stretch=project
##   keeps the project's canvas_items scaling (everything shrinks to fit the 1280x800 design size).
## text=0|1|2: the text size setting (Small, Normal, Large).
## gallery only: skin=neutral|broadcast|collectible|franchise  section=Buttons (scroll to a section)  touch=1  reduce=1
## layout=auto|desktop|mobile: force the presentation target (mobile shows the bottom navigation and touch-sized controls).
##   (dynasty screens) view=grid|carousel  demo=inspector|compare
##   demo=modal_info|modal_confirm|modal_destructive|toasts|loading (opens that overlay)
## offseason=draft: play the season out and stop at the owner's draft; offseason=window: the free-agency window after it.
## Dynasty screens use the test fixture content (tests/support/dynasty_fixture.gd), so the pictures do not depend on the machine.

var _app: FcApp
var _screen := "Overview"
var _out := "user://screenshot.png"
var _days := 14
var _frames := 0
var _offseason := ""
var _size := Vector2i(1280, 800)
var _stretch := false
var _text := 1
var _skin := ""
var _section := ""
var _touch := false
var _reduce := false
var _demo := ""
var _layout := "auto"
var _view := "grid"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"screen": _screen = kv[1]
			"out": _out = kv[1]
			"days": _days = int(kv[1])
			"offseason": _offseason = kv[1]
			"size": _size = Vector2i(int(kv[1].get_slice("x", 0)), int(kv[1].get_slice("x", 1)))
			"stretch": _stretch = kv[1] == "project"
			"text": _text = int(kv[1])
			"skin": _skin = kv[1]
			"section": _section = kv[1]
			"touch": _touch = kv[1] == "1"
			"reduce": _reduce = kv[1] == "1"
			"demo": _demo = kv[1]
			"layout": _layout = kv[1]
			"view": _view = kv[1]
	if not _stretch:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = _size
	DisplayServer.window_set_size(_size)
	_app = FcApp.new()
	_app.preferences = FcPreferences.new("user://screenshot_preferences.cfg")   # not the tests' file
	_app.preferences.content_root = "C:/Example/FullCourtContent"   # a neutral path: pictures are committed and must not show the real one
	_app.preferences.layout_override = _layout   # a Phase 3 setting; ignored by older code
	_app.preferences.text_size = _text   # before setup(), so the first screen (the menu) is built at this size
	_app.preferences.tutorial_done = true   # the tutorial has its own tests
	FcSafeFile.remove_tree("user://screenshot_saves")   # start from no saved games, so every picture is reproducible
	_app.saves = FcSaveManager.new("user://screenshot_saves")
	root.add_child(_app)
	_app.setup()
	_build_screen()


func _build_screen() -> void:
	if _screen == "menu":
		return
	if _screen == "new_league":
		_app.show_new_league()
		return
	if _screen == "settings":
		_app.call("show_settings")
		return
	if _screen == "career_menu":
		_app.show_career_home()
		return
	if _screen == "gallery":
		_app.call("show_gallery")
		var gallery = _app._form["gallery"]
		if _skin != "":
			gallery.call("set_skin", _skin)
		if _touch:
			gallery.call("set_touch", true)
		if _reduce:
			gallery.call("set_reduced_motion", true)
		if _text != 1:
			gallery.call("set_text_index", _text)
		return
	if _screen == "career_creator" or _screen == "career_hub":
		if _screen == "career_creator":
			_app.show_career_creator()
		else:
			var spec := FcPlayerBuild.default_spec("two_way_wing", 3, _app._defs)
			spec["first_name"] = "Maya"
			spec["last_name"] = "Okoro"
			spec["jersey_number"] = 11
			_app.on_create_career(spec, 4)
		return
	if _screen.begins_with("dynasty"):
		_build_dynasty()
		return
	_app.on_create_league({"teams": 12, "conferences": 2, "divisions": 1, "free_agents": 12, "seed": "5", "name": "Screenshot League"})
	_app.on_start_game(_app._pending_state.world.teams.ids()[2])
	_app.on_advance(_days)
	if _offseason != "":
		_app.on_sim_regular()
		_app.on_sim_playoffs()
		_app.on_next_season()
		if _app.controller.phase() == FcGameController.PHASE_MEETING:
			if _offseason == "meeting":
				_app._tabs.current_tab = FcApp.TAB_NAMES.find("Meeting")
			else:
				_app.on_close_meeting()
				_app.on_next_season()
		if _app.controller.state.offseason_stage == 0:
			_app.on_next_season()
		if _offseason == "window" and _app.controller.phase() == FcGameController.PHASE_DRAFT:
			_app.on_draft_auto()
	var index := FcApp.TAB_NAMES.find(_screen)
	if index >= 0:
		_app._tabs.current_tab = index


func _build_dynasty() -> void:
	FcSafeFile.remove_tree("user://screenshot_dynasty")
	FcDynastyFixture.wipe()
	_app.dynasty = FcDynastyController.new(_app.content, _app._defs, FcDynastyStore.new("user://screenshot_dynasty"))
	_app.dynasty_ui = FcDynastyUi.new(_app, _app.dynasty)
	_app.dynasty.catalog = FcDynastyFixture.catalog()
	if _screen == "dynasty_entry":
		_app.dynasty_ui.show_entry()
		return
	_app.dynasty_ui.on_create("Harbor Kings", "HBK")
	if _screen == "dynasty_reveal":
		var bought := _app.dynasty.buy_pack("bronze_pack")
		_app.dynasty_ui.show_tab("packs")
		if bought.ok:
			FcDynastyScreensPacks.show_reveal(_app.dynasty_ui, bought.data["opening"])
			var skip := _find_button(_app, "Skip animation")
			if skip != null:
				skip.pressed.emit()
		return
	if _app.ui_state != null:
		_app.ui_state.set_value("collection", "view", _view)
	_app.dynasty_ui.show_tab(_screen.trim_prefix("dynasty_"))


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.begins_with(text):
		return node
	for c in node.get_children():
		var found := _find_button(c, text)
		if found != null:
			return found
	return null


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4 and _screen == "gallery" and _section != "":
		_app._form["gallery"].call("scroll_to_section", _section)
	if _frames == 5 and _screen.begins_with("dynasty") and _demo in ["inspector", "compare", "profile"]:
		var first := FcDynastyFixture.card_id(0)
		if _demo == "profile":
			var vm := FcPlayerPresentation.from_card(_app.dynasty.card_detail(first), _app.dynasty)
			FcPlayerProfile.open_modal(_app, vm)
		elif _demo == "inspector":
			FcCardInspector.open_for(_app.dynasty_ui, first, [FcDynastyFixture.card_id(0), FcDynastyFixture.card_id(1), FcDynastyFixture.card_id(2)])
		else:
			FcCardCompare.open_for(_app.dynasty_ui, first, FcDynastyFixture.card_id(1))
	if _frames == 5 and _screen == "gallery" and _demo != "":
		_app._form["gallery"].call("show_demo", _demo)
	if _frames == (40 if _demo != "" else 10):   # overlays get time to finish their animation
		var image := root.get_texture().get_image()
		image.save_png(_out)
		print("saved ", _out, " ", image.get_size())
		FcSafeFile.remove_tree("user://screenshot_dynasty")
		quit(0)
	return false
