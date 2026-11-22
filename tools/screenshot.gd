extends SceneTree
## Renders the real UI in a window and saves a PNG so the screens can be looked at.
## NOT headless: run with a window, e.g.
##   godot_console --path . --script res://tools/screenshot.gd -- screen=Roster out=C:/temp/roster.png days=20
## screen:
##   menu | menu_saves | credits | online | online_in | settings | new_league | career_menu | career_creator | career_hub | career_story
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
##   screens dynasty_postgame, owner_postgame (the shared post-game screen)
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
var _scroll := 0


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
			"scroll": _scroll = int(kv[1])   # scrolls an open profile dialog down by this many pixels
			"hd": FcPlayerFigure.hd_enabled = kv[1] == "1"   # the high-fidelity portrait prototype (docs/PLAYER_VISUAL_PROPOSAL.md)
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
	if _screen == "menu_saves":
		# three scratch saves (in user://screenshot_saves, never the player's own) so the Continue card and the saved-game cards show
		_app.on_create_league({"teams": 12, "conferences": 2, "divisions": 1, "free_agents": 12, "seed": "5", "name": "Screenshot League"})
		_app.on_start_game(_app._pending_state.world.teams.ids()[2])
		for slot in [["owner_1", "Houston dynasty"], ["owner_2", "Rebuild year two"], ["owner_3", "Expansion test"]]:
			_app.saves.save(slot[0], _app.controller.state, slot[1])
		_app.show_main_menu()
		return
	if _screen == "credits":
		_app.show_credits()
		return
	if _screen == "online" or _screen == "online_in":   # sign-in screen with a made-up address and key (nothing is contacted)
		var payload := Marshalls.raw_to_base64(JSON.stringify({"role": "anon"}).to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=")
		_app.online = FcOnlineController.new(FcOnlineConfig.make("https://example-project.supabase.co", "eyJ.%s.sig" % payload), "user://screenshot_online_session.json")
		if _screen == "online_in":
			_app.online.finish("sign_in", {"status": 200, "body": {"access_token": "t", "refresh_token": "r", "expires_in": 3600, "user": {"id": "u", "email": "maya@example.com"}}})
		_app.show_online()
		DirAccess.remove_absolute("user://screenshot_online_session.json")
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
	if _screen == "career_creator" or _screen == "career_hub" or _screen == "career_story":
		if _screen == "career_creator":
			_app.show_career_creator()
		else:
			var spec := FcPlayerBuild.default_spec("two_way_wing", 3, _app._defs)
			spec["first_name"] = "Maya"
			spec["last_name"] = "Okoro"
			spec["jersey_number"] = 11
			_app.on_create_career(spec, 4)
			if _screen == "career_story":   # a signed player with one finished season, on the Story tab
				_app.career.join_team(_app.career.state.world.teams.ids()[2])
				var pending := _app.career.pending_event()
				if not pending.is_empty():
					_app.career.answer_event(str(pending["choices"][0]["key"]))
				_app.career.finish_season()
				_app._last_career_tab = 4
				_app.show_career_hub()
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
	if _screen == "owner_postgame":
		var boxes: Array = _app.controller.season().recent_boxes
		if not boxes.is_empty():
			FcPostGame.open(_app, FcPostGame.for_owner(_app.controller, boxes[boxes.size() - 1]["box"], boxes[boxes.size() - 1].get("events", {})))
		return
	if _screen == "owner_history":
		# eight finished seasons and a franchise legend, then the History tab on the page named by section= (Franchise, Retired numbers,
		# Rivalries, Storylines)
		for i in 8:
			_app.controller.sim_playoffs()
			_app.controller.start_next_season()
		var world: FcWorld = _app.controller.state.world
		FcHistoryFixture.retired_player(world, _app.controller.state.user_team_id, _app.controller.state.current_season - 12, 9, 2200, 910001)
		_app.show_dashboard()
		var index := FcApp.TAB_NAMES.find("History")
		_app._tabs.current_tab = index
		var pages := _app._tabs.get_current_tab_control().find_child("HistoryPages", true, false) as FcTabPages
		var wanted := FcOwnerHistory.PAGE_NAMES.find(_section) if _section != "" else 0
		if pages != null and wanted >= 0:
			pages.open(wanted, true)
		return
	if _screen == "owner_gameday":
		var preview := FcGameDay.for_owner(_app.controller)
		if not preview.is_empty():
			FcGameDay.open(_app, preview, _app.controller.state.world, func() -> void: pass)
		return
	if _screen == "owner_replay":
		# the replay of the owner's latest game, paused on the first made three-pointer after the first quarter
		var kept: Array = _app.controller.season().recent_boxes
		if not kept.is_empty():
			var built := FcReplay.for_owner(_app.controller, kept[kept.size() - 1])
			if not built.is_empty():
				FcReplay.open(_app, built)
				var shown := _app.find_child("ReplayScreen", true, false) as FcReplayScreen
				var model: FcReplayModel = built["model"]
				for e in model.entries:
					if e["type"] == FcGameEventLog.EV_SHOT_MADE and e["x"] == FcGameEventLog.SHOT_THREE and e["period"] >= 2:
						shown.seek(e["index"], false)
						break
		return
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
	if _screen == "dynasty_postgame":
		_app.dynasty.auto_fill_lineup()
		_app.dynasty.play_quick_game("easy")
		_app.dynasty_ui.show_tab("play")
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
	if _frames == 5 and _demo == "profile" and not _screen.begins_with("dynasty"):   # the dossier for the Career player or the best Owner player
		# for the picture only: a made-up injury and history, so the Health panel has something to show (the game itself is not touched on disk)
		var demo_world: FcWorld = _app.career.state.world if _screen == "career_hub" else _app.controller.state.world
		var demo_id: int = _app.career.player().id if _screen == "career_hub" else int(demo_world.teams.get_by_id(_app.controller.state.user_team_id).roster.player_ids[0])
		var demo_player: FcPlayer = demo_world.players.get_by_id(demo_id)
		demo_player.games_out = 12
		demo_player.injury = "sprained ankle"
		demo_world.record_injury(demo_id, 2024, "bruised knee", 5, false)
		demo_world.record_injury(demo_id, 2025, "torn ACL", 82, true)
		demo_world.record_injury(demo_id, 2026, "sprained ankle", 12, false)
		var demo_team: int = demo_world.team_of_player(demo_id).id if demo_world.team_of_player(demo_id) != null else 1
		demo_world.careers[demo_id] = [[2023, demo_team, 70, 126000, 1500, 0, 0, 90, 0, 0, 0, 140, 380, 310, 80, 40, 0, 0], [2024, demo_team, 72, 130000, 1750, 0, 0, 110, 0, 0, 0, 150, 400, 330, 90, 45, 0, 0], [2025, demo_team, 30, 60000, 600, 0, 0, 40, 0, 0, 0, 60, 150, 120, 30, 20, 0, 0], [2026, demo_team, 55, 100000, 1200, 0, 0, 70, 0, 0, 0, 110, 300, 260, 60, 30, 0, 0]]   # for the picture only
		if _screen == "career_hub":
			FcPlayerProfile.open_modal(_app, FcPlayerPresentation.from_career(_app.career))
		elif _app.controller != null:
			var world: FcWorld = _app.controller.state.world
			var roster: Array = world.teams.get_by_id(_app.controller.state.user_team_id).roster.player_ids
			FcPlayerProfile.open_modal(_app, FcPlayerPresentation.from_player(world, int(roster[0]), _app.controller.state.current_season, _app.controller.league_id))
	if _frames == 5 and _screen == "gallery" and _demo != "":
		_app._form["gallery"].call("show_demo", _demo)
	if _frames == 30 and _scroll > 0:
		var found := _app.find_children("*", "ScrollContainer", true, false).filter(func(n: Node) -> bool: return n.get_child_count() > 0 and n.get_child(0) is FcPlayerProfile)
		if not found.is_empty():
			(found[0] as ScrollContainer).scroll_vertical = _scroll
	if _frames == (40 if _demo != "" else 10):   # overlays get time to finish their animation
		var image := root.get_texture().get_image()
		image.save_png(_out)
		print("saved ", _out, " ", image.get_size())
		FcSafeFile.remove_tree("user://screenshot_dynasty")
		quit(0)
	return false
