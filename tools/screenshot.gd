extends SceneTree
## Renders the real UI in a window and saves a PNG so the screens can be looked at.
## NOT headless: run with a window, e.g.
##   godot_console --path . --script res://tools/screenshot.gd -- screen=Roster out=C:/temp/roster.png days=20
## screen: menu | new_league | Overview | Standings | Schedule | Roster | Finances | Staff | Market | Trades | History | News | League
## days: how many days to play first (so tables have data).
## offseason=draft: play the season out and stop at the owner's draft; offseason=window: the free-agency window after it.

var _app: FcApp
var _screen := "Overview"
var _out := "user://screenshot.png"
var _days := 14
var _frames := 0
var _offseason := ""


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
	root.size = Vector2i(1280, 800)
	_app = FcApp.new()
	_app.preferences = FcPreferences.new("user://test_preferences.cfg")
	_app.preferences.tutorial_done = true   # the tutorial has its own tests
	_app.saves = FcSaveManager.new("user://screenshot_saves")
	root.add_child(_app)
	_app.setup()
	if _screen == "menu":
		return
	if _screen == "new_league":
		_app.show_new_league()
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


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var image := root.get_texture().get_image()
		image.save_png(_out)
		print("saved ", _out, " ", image.get_size())
		quit(0)
	return false
