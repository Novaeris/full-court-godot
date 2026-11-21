extends SceneTree
## Plays the pack-opening reveal on a scripted timeline and saves screenshots (a storyboard) of every stage. Needs a window.
##   godot_console --path . --script res://tools/pack_reveal_demo.gd -- out=docs/validation/pack_reveal/legendary cards=common,rare,epic,legendary
## Options after "--": out=<folder>  cards=<comma list of rarities>  cinematic=1|0 (default 1)  hd=1|0 (HD portraits, default 1)
##   size=1100x760  reduced=1 (reduced motion)  skip_at=<seconds> (press Skip at that time)  movie=1 (no screenshots: for --write-movie recordings)
## Record a video:  godot_console --path . --write-movie out.avi --fixed-fps 30 --script res://tools/pack_reveal_demo.gd -- movie=1 cards=...
## The openings here are SYNTHETIC (names and ratings made up for the picture); no game state, odds or saves are involved.

const NAMES := ["Marcus Vale", "Dario Okoye", "Teo Lindqvist", "Jun Park", "Andre Castile", "Kofi Mensah", "Rafa Ibarra", "Eli Brandt", "Soren Hale", "Tomas Ruiz"]
const POSITIONS := ["PG", "SG", "SF", "PF", "C"]
const OVERALLS := {"common": 68, "uncommon": 74, "rare": 81, "epic": 88, "legendary": 95}

var _out := "user://pack_demo"
var _cards: Array = ["common", "common", "rare", "epic", "legendary"]
var _cinematic := true
var _size := Vector2i(1100, 760)
var _reduced := false
var _skip_at := -1.0
var _movie := false
var _t := 0.0
var _app: FcApp
var _reveal: FcPackReveal
var _events: Array = []   # [{t, kind, name}]
var _frame := 0


func _initialize() -> void:
	var hd := true
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"cards": _cards = Array(kv[1].split(","))
			"cinematic": _cinematic = kv[1] != "0"
			"hd": hd = kv[1] != "0"
			"size": _size = Vector2i(int(kv[1].get_slice("x", 0)), int(kv[1].get_slice("x", 1)))
			"reduced": _reduced = kv[1] == "1"
			"skip_at": _skip_at = float(kv[1])
			"movie": _movie = kv[1] == "1"
	FcPlayerFigure.hd_enabled = hd
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = _size
	DisplayServer.window_set_size(_size)
	DirAccess.make_dir_recursive_absolute(_out)
	_app = FcApp.new()
	_app.preferences = FcPreferences.new("user://pack_demo_preferences.cfg")
	_app.preferences.tutorial_done = true
	_app.preferences.reduce_motion = _reduced
	_app.saves = FcSaveManager.new("user://pack_demo_saves")
	root.add_child(_app)
	_app.setup()
	FcMotion.reduced = _reduced


func _build_reveal() -> void:
	var cards: Array = []
	var rows := {}
	for i in _cards.size():
		var id := "demo_%d" % i
		cards.append({"card_id": id, "new": i % 3 != 1, "quantity": 1})
		var rarity := str(_cards[i])
		rows[id] = {"card_id": id, "player_id": "demo_player_%d" % i, "rarity": rarity, "overall": int(OVERALLS.get(rarity, 70)) + i % 3, "position": POSITIONS[i % 5], "name": NAMES[i % NAMES.size()],
			"edition": "Base Edition", "team": "Harbor Kings", "owned": true, "available": true, "badges": [], "mastery": 0}
	_reveal = FcPackRevealCinematic.new() if _cinematic else FcPackReveal.new()
	var holder := PanelContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app.add_child(holder)
	var scroll := VBoxContainer.new()
	holder.add_child(scroll)
	scroll.add_child(_reveal)
	_reveal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reveal.setup({"opening_id": "op_demo", "pack_id": "demo", "cards": cards}, "Starter Pack", {"name": "Starter Pack", "cards_per_pack": cards.size(), "odds": {"legendary": 1, "epic": 5, "rare": 20, "common": 74}},
		func(id: String) -> Dictionary: return rows[id].duplicate(),
		func(r: String) -> int: return {"common": 5, "uncommon": 10, "rare": 25, "epic": 60, "legendary": 150}.get(r, 5),
		func() -> Dictionary: return {"owned": 18, "total": 120},
		func() -> void: pass)


## The timeline: open, then reveal each card with screenshots at the moments that matter.
func _plan() -> void:
	var t := 0.6
	_events.append({"t": t, "kind": "shot", "name": "01_pack_presented"})
	t = 1.4
	_events.append({"t": t, "kind": "open"})
	_events.append({"t": t + 0.28, "kind": "shot", "name": "02a_wrapper_shakes"})
	_events.append({"t": t + 0.5, "kind": "shot", "name": "02b_wrapper_tears"})
	_events.append({"t": t + 0.95, "kind": "shot", "name": "02c_cards_emerge"})
	t += 2.2
	_events.append({"t": t, "kind": "shot", "name": "03_cards_ready"})
	for i in _cards.size():
		var spec := FcRevealSpec.of(str(_cards[i]))
		var tease := float(spec["tease"])
		_events.append({"t": t + 0.2, "kind": "next"})
		_events.append({"t": t + 0.45, "kind": "shot", "name": "04_card%d_%s_spotlight" % [i + 1, _cards[i]]})
		if tease > 0.0:
			_events.append({"t": t + 0.2 + 0.22 + tease * 0.85, "kind": "shot", "name": "04_card%d_%s_tease" % [i + 1, _cards[i]]})
		var impact := t + 0.2 + 0.22 + tease + float(spec["flip"])
		_events.append({"t": impact - float(spec["flip"]) * 0.5, "kind": "shot", "name": "05_card%d_%s_turning" % [i + 1, _cards[i]]})
		_events.append({"t": impact + 0.2, "kind": "shot", "name": "06_card%d_%s_impact" % [i + 1, _cards[i]]})
		if bool(spec["banner"]) or bool(spec["name_plate"]):
			_events.append({"t": impact + 0.8, "kind": "shot", "name": "06_card%d_%s_hold" % [i + 1, _cards[i]]})
		t = impact + 1.3
	_events.append({"t": t, "kind": "next"})   # continue: the last card lands and the summary shows
	_events.append({"t": t + 0.8, "kind": "shot", "name": "07_summary"})
	_events.append({"t": t + 1.3, "kind": "quit"})
	if _skip_at >= 0.0:
		_events = _events.filter(func(e: Dictionary) -> bool: return e["t"] < _skip_at)
		_events.append({"t": _skip_at, "kind": "skip"})
		_events.append({"t": _skip_at + 0.5, "kind": "shot", "name": "08_after_skip"})
		_events.append({"t": _skip_at + 1.0, "kind": "quit"})


func _process(delta: float) -> bool:
	if _reveal == null:   # nodes are only in the tree from the first frame on (animations need that)
		_build_reveal()
		_plan()
		return false
	_t += delta   # run with --fixed-fps 30 so every run draws the same moments
	_frame += 1
	while not _events.is_empty() and float(_events[0]["t"]) <= _t:
		var e: Dictionary = _events.pop_front()
		match str(e["kind"]):
			"open":
				if _reveal is FcPackRevealCinematic:
					(_reveal as FcPackRevealCinematic).open_pack()
				else:
					pass
			"next":
				_reveal.reveal_next()
			"skip":
				_reveal.reveal_all()
			"shot":
				if not _movie:
					_shot.call_deferred(str(e["name"]))
			"quit":
				quit()
	return false


func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, name])
	print("saved ", name)
