class_name FcReplayScreen
extends VBoxContainer
## The game replay: a scoreboard, the court picture (FcCourtView), the sentence for the current event, a clickable play-by-play feed
## and the controls: play and pause, step back and forward, speed, a filter (all plays, key plays, scoring), a jump to each period and
## a scrubber. The same screen serves Owner, Career and Dynasty (they only differ in where the events come from, see FcReplay).
##
## All the decisions live in FcReplayModel; this class draws and plays. `advance(delta)` is what the frame callback calls, so a test can
## play a replay deterministically without waiting for real time. Playing never changes any game data: it only reads the model.

signal event_shown(index: int)

const SPEEDS := [["0.25", "0.25x"], ["0.5", "0.5x"], ["1", "1x"], ["2", "2x"], ["4", "4x"]]
## The speed an instant replay plays at: half speed, so the play can be followed.
const INSTANT_REPLAY_SPEED := 0.5
const VIEWS_2D := [["broadcast", "Broadcast 2D"], ["flat", "Flat view"]]
const VIEW_3D := ["broadcast3d", "Broadcast 3D"]
const CAMERA_MODES := [["auto", "Auto"], ["hybrid", "Auto + manual"], ["manual", "Manual"]]
const ZOOM_STEP := 1.25
const FILTERS := [[FcReplayModel.FILTER_ALL, "All plays"], [FcReplayModel.FILTER_KEY, "Key plays"], [FcReplayModel.FILTER_SCORING, "Scoring"]]

var model: FcReplayModel
var timeline: FcBroadcastTimeline   # the running state for the broadcast graphics (derived from the model, read-only)
var colors: Array = [FcUiTokens.INFO, FcUiTokens.PRIMARY]
var filter: String = FcReplayModel.FILTER_ALL
var state := FcPlaybackState.new()   # the one owner of position, play state, speed, instant replay, camera mode and view (never changed by a mode switch)
var speed: float:
	get:
		return state.speed
	set(v):
		state.speed = v
var mode: String = FcPresentationMode.DEFAULT_MODE
var hud: String = FcPresentationMode.DEFAULT_HUD
var collapsed: Dictionary = {}   # panel id -> true when the player folded it away (UI state of the modes, not playback state)
var compact: bool = false
var subjects: Array = []   # FcTeamLook subjects for [home, away]: the crests on the scoreboard ([] = none)
var prefs: FcPreferences   # where the chosen mode and HUD level are remembered (null: not remembered)
var mode_group: FcChoiceGroup
var hud_button: Button
var camera_toggle: Button
var feed_toggle: Button
var camera_inner: Control   # the camera controls proper, folded away by camera_toggle
var transport: Control
var _panels: Dictionary = {}   # presentation panel id -> Array of Controls that belong to it
var _jump_buttons: Array[Control] = []

var bug: FcScoreBug
var overlay: FcBroadcastOverlay
var spotlight: FcPlayerSpotlight   # the player card over the stage (FcSpotlightModel)
var stats_overlay: FcStatsOverlay   # the team comparison drawn over the stage on request (key S)
var stats_button: Button
var stats_on: bool = false
var lineup_card: GridContainer   # the starting lineups (FcBroadcastGraphics.lineup_card): number, name, position for each side
var team_card: GridContainer   # the team comparison card: label, home, away (FcBroadcastGraphics.team_card_at)
var court: FcCourtView
var _last_bounce_sound: float = -10.0
var court3d: FcBroadcast3DView   # null when the 3D view could not be built: the 2D court is then the only picture
var stage: Control               # holds the 2D court, the 3D view, the graphic strip and the REPLAY badge, so the graphics sit over either
var view_note: Label
var caption: Label
var analyst_label: Label   # the analyst and narrative lines from the commentary booth (M6)
var announcer_label: Label   # the stadium announcer line
var booth := FcCommentaryBooth.new()
var caption_sink := FcCaptionSink.new()
var commentary_label: Label   # announcer-style text from recorded facts (B7); follows the captions preference
var sound_caption: Label   # what the crowd and court sounds are, in words (B3); empty when there is nothing to describe
var feed: ItemList
var scrubber: HSlider
var play_button: FcButton
var filter_group: FcChoiceGroup
var speed_group: FcChoiceGroup
var period_group: FcChoiceGroup
var view_group: FcChoiceGroup
var camera_group: FcChoiceGroup
var style_group: FcChoiceGroup   # the director's style: calm, standard, energetic
var replay_button: Button
var tools: FcReplayTools   # the replay-review tools (bookmark, marks, reel, angle, replay time)
var marks: FcTimelineMarks   # ticks under the scrubber: highlights, key plays, bookmarks
var bookmarks: FcBookmarkStore = FcBookmarkStore.new("")   # in memory unless the app gives it a file (FcReplay.open): tests never touch the player's own file
var show_panel: FcProductionPanel   # the production shows (pregame, halftime, postgame, championship) drawn over the stage
var title_context: Dictionary = {}   # {series_label} when this game decided a title; empty otherwise
var right_column: Control   # the tools and the feed side by side with the court; it shows while either of them does
var package: Dictionary = {}   # FcReplayCollections.package: the reel's references and length
var highlights: Array[Dictionary] = []   # FcHighlights.select: the events worth jumping to, in game order
var highlight_prev: Button
var highlight_next: Button
var replay_badge: Label
var trail_toggle: Button
var camera_buttons: Array[Button] = []   # Wide, Zoom in, Zoom out: they move the camera by hand, so they are off in the automatic mode

var _index: int:
	get:
		return state.index
	set(v):
		state.index = v
var _playing: bool:
	get:
		return state.playing
	set(v):
		state.playing = v
var _timer: float:
	get:
		return state.timer
	set(v):
		state.timer = v
var _names: Dictionary = {}
var _feed_indices: Array[int] = []
var _roster_labels: Array = [[], []]   # per side: the five labels listing who is on court
var _roster_heads: Array = [null, null]
var _silent: bool = false
var _instant: Dictionary:   # {start, end, return_index, speed}: an instant replay in progress ({} when live); lives in `state`
	get:
		return state.instant
	set(v):
		state.instant = v


## Builds the screen for `replay_model`. `team_colors` are the home and away colours; `phone` picks the stacked layout.
func setup(replay_model: FcReplayModel, team_colors: Array = [], phone: bool = false, preferences: FcPreferences = null, team_subjects: Array = []) -> FcReplayScreen:
	subjects = team_subjects
	model = replay_model
	compact = phone
	prefs = preferences   # null in tests and previews: the mode and HUD then start at their defaults and nothing is written
	if prefs != null:
		mode = prefs.presentation_mode
		hud = prefs.hud_level
	if team_colors.size() == 2:
		colors = team_colors
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	if model == null or model.is_empty():
		add_child(FcUiTables.label("No replay was kept for this game. Replays are recorded for the games of the team you follow, and only the most recent ones are stored.", FcUiTokens.TYPE_BODY))
		return self
	for p in model.box.players:
		_names[p.player_id] = FcPlayByPlay.short_name(p.name)
	timeline = FcBroadcastTimeline.build(model)
	_build()
	seek(model.start_index(), false)
	set_mode(mode)   # the mode picks the view and camera: 3D by default on a desktop when it could be built; a phone keeps 2D (D-030)
	return self


func current_index() -> int:
	return _index


func is_playing() -> bool:
	return _playing


# --- building -----------------------------------------------------------------------------------------------------------------

func _build() -> void:
	add_child(_mode_bar())
	bug = FcScoreBug.new()
	bug.set_crests(subjects)
	add_child(bug)
	var body: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	body.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	court = FcCourtView.new()
	court.colors = colors
	court.custom_minimum_size = Vector2(300 if compact else 520, 170 if compact else 280)
	court.home_abbreviation = str(model.box.abbreviations[0])
	stage = Control.new()
	stage.name = "Stage"
	stage.custom_minimum_size = court.custom_minimum_size
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.add_child(court)
	court.set_anchors_preset(Control.PRESET_FULL_RECT)
	court.custom_minimum_size = Vector2.ZERO
	court3d = FcBroadcast3DView.new()
	if compact:   # a phone never shows 3D (D-030), so it does not even build it: no memory or start-up time spent on a view that cannot be used
		court3d.free()
		court3d = null
	elif court3d.setup(model, timeline, colors):
		court3d.rig = court.rig   # one camera rig for both views: manual control and the director carry over when switching
		court3d.name = "Court3D"
		stage.add_child(court3d)
		court3d.set_anchors_preset(Control.PRESET_FULL_RECT)
		court3d.camera_moved_by_hand.connect(func() -> void: pass)
		court3d.ball_bounced.connect(_on_ball_bounced)
	else:
		court3d.free()
		court3d = null
	replay_badge = FcUiTables.label("REPLAY", FcUiTokens.TYPE_SMALL, true)
	replay_badge.name = "ReplayBadge"
	replay_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_badge.add_theme_color_override("font_color", FcUiTokens.GOLD)
	replay_badge.visible = false
	stage.add_child(replay_badge)
	replay_badge.position = Vector2(FcUiTokens.SPACE_3, FcUiTokens.SPACE_2)
	left.add_child(stage)
	left.add_child(_camera_panel())
	overlay = FcBroadcastOverlay.new(colors)   # the broadcast graphic sits over the court's lower edge and never takes the mouse
	overlay.size_flags_horizontal = Control.SIZE_FILL
	stage.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, FcUiTokens.SPACE_2)
	overlay.grow_vertical = Control.GROW_DIRECTION_BEGIN
	show_panel = FcProductionPanel.new()
	stage.add_child(show_panel)
	show_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, FcUiTokens.SPACE_5)
	show_panel.closed.connect(end_show)
	show_panel.reel_requested.connect(_on_show_reel)
	spotlight = FcPlayerSpotlight.new(colors)
	stage.add_child(spotlight)
	spotlight.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, FcUiTokens.SPACE_2)
	spotlight.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stats_overlay = FcStatsOverlay.new()
	stage.add_child(stats_overlay)
	stats_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, FcUiTokens.SPACE_2)
	caption = FcUiTables.label("", FcUiTokens.TYPE_H3, true)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 120
	left.add_child(caption)
	sound_caption = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	sound_caption.theme_type_variation = "MutedLabel"
	sound_caption.name = "SoundCaption"
	left.add_child(sound_caption)
	commentary_label = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	commentary_label.theme_type_variation = "MutedLabel"
	commentary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	commentary_label.name = "Commentary"
	left.add_child(commentary_label)
	analyst_label = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	analyst_label.theme_type_variation = "MutedLabel"
	analyst_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	analyst_label.name = "Analyst"
	left.add_child(analyst_label)
	announcer_label = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	announcer_label.theme_type_variation = "MutedLabel"
	announcer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announcer_label.name = "Announcer"
	left.add_child(announcer_label)
	booth.add_sink(caption_sink)
	booth.on_speaking = _on_voice
	var rosters := _roster_strip()
	var lineups := _lineup_panel()
	var teams := _team_card()
	left.add_child(rosters)
	left.add_child(lineups)
	left.add_child(teams)
	_register(FcPresentationMode.P_ROSTERS, rosters)
	_register(FcPresentationMode.P_LINEUPS, lineups)
	_register(FcPresentationMode.P_TEAMS, teams)
	body.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	right.custom_minimum_size = Vector2(0 if compact else 330, 180 if compact else 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column = right
	tools = FcReplayTools.new()
	tools.bookmark_pressed.connect(toggle_bookmark)
	tools.mark_jump.connect(jump_mark)
	tools.reel_pressed.connect(toggle_reel)
	tools.intro_pressed.connect(toggle_introductions)
	tools.show_pressed.connect(start_show)
	tools.angle_chosen.connect(set_replay_angle)
	right.add_child(tools)
	_register(FcPresentationMode.P_HIGHLIGHTS, tools)
	var feed_box := VBoxContainer.new()   # the play-by-play folds away on its own; the replay tools above it stay
	feed_box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	feed_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filter_group = FcChoiceGroup.new()
	filter_group.set_options(FILTERS, filter)
	filter_group.selected.connect(set_filter)
	feed_box.add_child(filter_group)
	feed = ItemList.new()
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed.custom_minimum_size.y = 180
	feed.item_selected.connect(_on_feed_selected)
	feed.resized.connect(func() -> void: feed.ensure_current_is_visible())   # a dialog is laid out over several frames: keep the current play in view
	feed_box.add_child(feed)
	right.add_child(feed_box)
	body.add_child(right)
	_register(FcPresentationMode.P_FEED, feed_box)
	transport = _controls()
	add_child(transport)
	_fill_feed()


func _controls() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	var start_button := FcButton.make("Start", FcButton.Variant.GHOST, func() -> void: seek(model.start_index(), true))
	row.add_child(start_button)
	row.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, func() -> void: step(-1)))
	play_button = FcButton.make("Play", FcButton.Variant.PRIMARY, toggle_play)
	row.add_child(play_button)
	row.add_child(FcButton.make("Next", FcButton.Variant.SECONDARY, func() -> void: step(1)))
	var end_button := FcButton.make("End", FcButton.Variant.GHOST, func() -> void: seek(model.final_index(), true))
	row.add_child(end_button)
	_register(FcPresentationMode.P_JUMPS, start_button)
	_register(FcPresentationMode.P_JUMPS, end_button)
	speed_group = FcChoiceGroup.new()
	speed_group.set_options(SPEEDS, "1")
	speed_group.selected.connect(func(id: String) -> void: set_speed(float(id)))
	row.add_child(speed_group)
	_register(FcPresentationMode.P_SPEED, speed_group)
	box.add_child(row)
	var periods: Array = []
	for p in model.periods():
		periods.append([str(p), ("Q%d" % p) if p <= model.quarters else ("OT" if p == model.quarters + 1 else "OT%d" % (p - model.quarters))])
	period_group = FcChoiceGroup.new()
	period_group.set_options(periods, "1")
	period_group.selected.connect(func(id: String) -> void: seek(model.period_start_index(int(id)), true))
	box.add_child(period_group)
	_register(FcPresentationMode.P_PERIODS, period_group)
	scrubber = HSlider.new()
	scrubber.min_value = 0
	scrubber.max_value = maxi(1, model.size() - 1)
	scrubber.step = 1
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.value_changed.connect(func(v: float) -> void:
		if not _silent:
			seek(int(v), false))
	box.add_child(scrubber)
	_register(FcPresentationMode.P_SCRUBBER, scrubber)
	marks = FcTimelineMarks.new()
	box.add_child(marks)
	_register(FcPresentationMode.P_SCRUBBER, marks)
	package = FcReplayCollections.package(timeline)
	_refresh_marks()
	return box


## The contextual camera panel: a header with fold buttons, and the camera controls proper (view, camera mode, and the manual controls, which
## only show while the camera is not fully automatic).
func _camera_panel() -> Control:
	var outer := VBoxContainer.new()
	outer.name = "CameraPanel"
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	camera_toggle = FcButton.make("Camera controls: hide", FcButton.Variant.GHOST, func() -> void: toggle_collapsed(FcPresentationMode.P_CAMERA))
	feed_toggle = FcButton.make("Play-by-play: hide", FcButton.Variant.GHOST, func() -> void: toggle_collapsed(FcPresentationMode.P_FEED))
	head.add_child(camera_toggle)
	head.add_child(feed_toggle)
	outer.add_child(head)
	camera_inner = _camera_controls()
	outer.add_child(camera_inner)
	_register(FcPresentationMode.P_CAMERA, outer)
	return outer


func _camera_controls() -> Control:
	var box := HFlowContainer.new()
	box.name = "CameraControls"
	box.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	view_group = FcChoiceGroup.new()
	var view_options: Array = []
	if court3d != null:
		view_options.append(VIEW_3D)
	view_options.append_array(VIEWS_2D)
	view_group.set_options(view_options, "broadcast")
	view_group.selected.connect(set_view)
	box.add_child(view_group)
	view_note = FcUiTables.label("" if court3d != null else "The 3D view is not available here, so the 2D view is shown.", FcUiTokens.TYPE_SMALL)
	view_note.theme_type_variation = "MutedLabel"
	view_note.name = "ViewNote"
	view_note.visible = court3d == null and not compact
	box.add_child(view_note)
	camera_group = FcChoiceGroup.new()
	camera_group.set_options(CAMERA_MODES, "hybrid")
	camera_group.selected.connect(set_camera_mode)
	box.add_child(camera_group)
	style_group = FcChoiceGroup.new()
	style_group.set_options([["calm", "Calm"], ["standard", "Normal"], ["energetic", "Lively"]], court.rig.style)
	style_group.tooltip_text = "Director style: how long shots stay up and how fast the camera moves"
	style_group.selected.connect(set_camera_style)
	var director_label := FcUiTables.label("Director:", FcUiTokens.TYPE_SMALL)
	director_label.theme_type_variation = "MutedLabel"
	box.add_child(director_label)
	box.add_child(style_group)
	for entry in [["Whole court", func() -> void: court.rig.manual_set(Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0), 1.0)],
			["Zoom in", func() -> void: court.rig.manual_move(Vector2.ZERO, ZOOM_STEP)], ["Zoom out", func() -> void: court.rig.manual_move(Vector2.ZERO, 1.0 / ZOOM_STEP)]]:
		var button := FcButton.make(entry[0], FcButton.Variant.SECONDARY, entry[1])
		camera_buttons.append(button)
		box.add_child(button)
	box.add_child(FcButton.make("Reset camera", FcButton.Variant.GHOST, reset_camera))
	trail_toggle = FcButton.make("Ball trail: on", FcButton.Variant.GHOST, toggle_trail)
	box.add_child(trail_toggle)
	replay_button = FcButton.make("Instant replay", FcButton.Variant.PRIMARY, toggle_instant_replay)
	box.add_child(replay_button)
	highlights = FcHighlights.select(timeline)
	highlight_prev = FcButton.make("Previous highlight", FcButton.Variant.SECONDARY, func() -> void: jump_highlight(-1))
	highlight_next = FcButton.make("Next highlight", FcButton.Variant.SECONDARY, func() -> void: jump_highlight(1))
	box.add_child(highlight_prev)
	box.add_child(highlight_next)
	_register(FcPresentationMode.P_HIGHLIGHTS, highlight_prev)
	_register(FcPresentationMode.P_HIGHLIGHTS, highlight_next)
	return box


# --- presentation modes and the HUD (Broadcast pass 2, M1) -------------------------------------------------------------------------

func _register(panel: String, control: Control) -> void:
	if not _panels.has(panel):
		_panels[panel] = []
	_panels[panel].append(control)


## The mode choice (Broadcast, Replay, Analysis) and the HUD button. It stays on screen whatever the HUD level, so there is always a way back.
func _mode_bar() -> Control:
	var row := HFlowContainer.new()
	row.name = "ModeBar"
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	mode_group = FcChoiceGroup.new()
	mode_group.set_options(FcPresentationMode.MODES, mode)
	mode_group.selected.connect(set_mode)
	row.add_child(mode_group)
	hud_button = FcButton.make("HUD: full", FcButton.Variant.GHOST, cycle_hud)
	hud_button.name = "HudButton"
	row.add_child(hud_button)
	stats_button = FcButton.make("Stats overlay: off", FcButton.Variant.GHOST, toggle_stats)
	stats_button.name = "StatsButton"
	row.add_child(stats_button)
	return row


## Switches the presentation. Only the layout, the default view and the camera mode change; the replay position, play state, speed and any
## instant replay are in `state` and are not touched (tested).
func set_mode(id: String) -> void:
	if model == null or model.is_empty() or not FcPresentationMode.is_mode(id):
		return
	mode = id
	mode_group.select(id)
	var lay := FcPresentationMode.layout(id)
	set_camera_mode(str(lay["camera"]))
	var want_3d := str(lay["view"]) == "3d" and court3d != null and not compact
	set_view("broadcast3d" if want_3d else ("flat" if str(lay["view"]) == "flat" and not compact else "broadcast"))
	if prefs != null:
		prefs.presentation_mode = id
		prefs.save_file()
	apply_layout()


func set_hud(level: String) -> void:
	if not FcPresentationMode.is_hud(level):
		return
	hud = level
	if prefs != null:
		prefs.hud_level = level
		prefs.save_file()
	apply_layout()


func cycle_hud() -> void:
	set_hud(FcPresentationMode.next_hud(hud))


## Shows or hides the statistics overlay over the stage (the team comparison at the current event).
func toggle_stats() -> void:
	stats_on = not stats_on
	stats_button.text = "Stats overlay: on" if stats_on else "Stats overlay: off"
	_refresh_stats()


func _refresh_stats() -> void:
	var on := stats_on and FcPresentationMode.hud_shows(hud, FcPresentationMode.E_OVERLAY)
	stats_overlay.show_card(FcBroadcastGraphics.team_card_at(timeline, _index), on)


## Folds a panel (the feed or the camera controls) away or brings it back. Stays within the mode's layout: a panel the mode hides stays hidden.
func toggle_collapsed(panel: String) -> void:
	collapsed[panel] = not bool(collapsed.get(panel, false))
	apply_layout()


## Applies the mode, the HUD level and the folded panels to the nodes. Called after any of them changes.
func apply_layout() -> void:
	if model == null or model.is_empty():
		return
	for panel in _panels:
		var shown := FcPresentationMode.panel_visible(mode, hud, panel)
		if panel == FcPresentationMode.P_FEED:
			shown = shown and not bool(collapsed.get(panel, false))
		for c in _panels[panel]:
			(c as Control).visible = shown
	var camera_open := not bool(collapsed.get(FcPresentationMode.P_CAMERA, false))
	camera_inner.visible = camera_open
	camera_toggle.text = "Camera controls: hide" if camera_open else "Camera controls: show"
	feed_toggle.text = "Play-by-play: show" if bool(collapsed.get(FcPresentationMode.P_FEED, false)) else "Play-by-play: hide"
	feed_toggle.visible = FcPresentationMode.panel_visible(mode, hud, FcPresentationMode.P_FEED)
	right_column.visible = tools.visible or feed.get_parent().visible   # an empty column would still take its width
	hud_button.text = "HUD: %s" % hud
	_size_stage()
	var E := FcPresentationMode
	bug.visible = E.hud_shows(hud, E.E_SCOREBUG)
	overlay.hud_hidden = not E.hud_shows(hud, E.E_OVERLAY) or is_show()   # a show covers the stage: no lower third under it
	overlay.auto_hide = mode == E.BROADCAST   # a television lower third leaves by itself; the review modes keep it until the next play
	spotlight.hud_hidden = overlay.hud_hidden
	show_panel.visible = is_show() and hud != FcPresentationMode.HUD_HIDDEN
	spotlight.auto_hide = overlay.auto_hide
	if overlay.hud_hidden:
		spotlight.visible = false
	else:
		spotlight.show_model(spotlight.current_model())
	_refresh_stats()
	overlay.visible = not overlay.hud_hidden and not overlay.current_item().is_empty()
	var captions := E.hud_shows(hud, E.E_CAPTIONS)
	caption.visible = captions
	analyst_label.visible = captions
	announcer_label.visible = captions
	sound_caption.visible = captions
	commentary_label.visible = captions
	transport.visible = E.hud_shows(hud, E.E_TRANSPORT)
	_refresh_badge()
	_refresh_camera_context()
	_update_music()


## The court is the focus of Broadcast, so its stage grows with the window there; Replay and Analysis share the space with their panels.
func _size_stage() -> void:
	if compact:
		return
	if not is_inside_tree():
		if not tree_entered.is_connected(_size_stage):
			tree_entered.connect(_size_stage, CONNECT_ONE_SHOT)
		return
	var share: float = {FcPresentationMode.BROADCAST: 0.44, FcPresentationMode.REPLAY: 0.36}.get(mode, 0.3)
	if is_show():
		share = maxf(share, 0.5)   # the show's tables need room
	stage.custom_minimum_size.y = clampf(get_viewport_rect().size.y * share, 280.0, 1100.0)


func _refresh_badge() -> void:
	replay_badge.text = FcReplayReference.REEL_BADGE_TEXT if is_reel() else FcReplayReference.BADGE_TEXT
	replay_badge.visible = (is_instant_replay() or is_reel()) and FcPresentationMode.hud_shows(hud, FcPresentationMode.E_BADGE)


## The manual camera controls only make sense when the camera is not fully automatic, so they appear only then.
func _refresh_camera_context() -> void:
	var manual_ok := state.camera_mode != "auto"
	for b in camera_buttons:
		b.visible = manual_ok
		b.disabled = not manual_ok


## Jumps to the highlight after (1) or before (-1) the current event and pauses there; nothing happens when there is none that way.
func jump_highlight(direction: int) -> void:
	var h := FcHighlights.neighbor(highlights, _index, direction)
	if h.is_empty():
		return
	if _playing:
		toggle_play()
	seek(int(h["index"]))


func toggle_trail() -> void:
	court.show_trail = not court.show_trail
	trail_toggle.text = "Ball trail: on" if court.show_trail else "Ball trail: off"
	court.queue_redraw()


## Switches between the projected broadcast view and the original flat top-down court. The replay position is untouched.
func set_view(id: String) -> void:
	var want_3d := id == "broadcast3d"
	if want_3d and court3d == null:   # asked for 3D but it could not be built: stay in 2D, say so, lose nothing
		id = "broadcast"
		want_3d = false
		view_note.text = "The 3D view is not available here, so the 2D view is shown."
		view_note.visible = true
	if court3d != null:
		court3d.visible = want_3d
	court.visible = not want_3d
	court.set_flat(id == "flat")
	state.view_id = id
	view_group.select(id)
	if want_3d:
		court3d.show_event(_index, false)   # the replay position is the screen's: the 3D view just shows it


## "auto" (the director only), "hybrid" (the director, until you move the camera; it comes back after a few idle seconds) or "manual".
func set_camera_mode(id: String) -> void:
	court.rig.mode = {"auto": FcCameraRig.Mode.AUTO, "hybrid": FcCameraRig.Mode.HYBRID, "manual": FcCameraRig.Mode.MANUAL}.get(id, FcCameraRig.Mode.HYBRID)
	camera_group.select(id)
	state.camera_mode = id
	for b in camera_buttons:
		b.disabled = id == "auto"
	_refresh_camera_context()
	_request_shot(true)


## The director's style (calm, standard, energetic): how long shots stay up, how soon one can come back and how fast the camera moves.
func set_camera_style(id: String) -> void:
	if not FcBroadcastStyle.camera_styles().has(id):
		return
	court.rig.style = id
	style_group.select(id)
	if prefs != null:
		prefs.camera_style = id
		prefs.save_file()


## Asks the camera for the shot of the current event: the director's shot, or a replay angle while an instant replay runs.
func _request_shot(jump: bool = false) -> void:
	court.rig.request(FcCameraDirector.replay_shot_for(timeline, _index, _replay_variant()) if (is_instant_replay() or is_reel()) else FcCameraDirector.shot_for(timeline, _index), jump)


## Gives the camera back to the director (and leaves manual mode).
func reset_camera() -> void:
	court.rig.reset()
	camera_group.select("hybrid")
	state.camera_mode = "hybrid"
	for b in camera_buttons:
		b.disabled = false
	_refresh_camera_context()
	_request_shot(true)


func _lineup_panel() -> Control:
	var panel := FcPanel.new("Starting lineups", FcPanel.Variant.FLAT)
	lineup_card = GridContainer.new()
	lineup_card.name = "LineupCard"
	lineup_card.columns = 6
	lineup_card.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	lineup_card.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	lineup_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.body.add_child(lineup_card)
	var card := FcBroadcastGraphics.lineup_card(timeline)
	if not card.is_empty():
		var sides: Array = card["sides"]
		var head: Array = [str(sides[0]["abbreviation"]), "", "", str(sides[1]["abbreviation"]), "", ""]
		for text in head:
			var h := FcUiTables.label(text, FcUiTokens.TYPE_SMALL, true)
			lineup_card.add_child(h)
		for r in 5:
			for s in 2:
				var rows: Array = sides[s]["rows"]
				var row: Array = rows[r] if r < rows.size() else ["", "", ""]
				for col in 3:
					var l := FcUiTables.label(str(row[col]), FcUiTokens.TYPE_SMALL)
					l.theme_type_variation = "NumericLabel" if col == 0 else "CaptionLabel"
					l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if col == 1 else Control.SIZE_SHRINK_BEGIN
					lineup_card.add_child(l)
	return panel


func _team_card() -> Control:
	var panel := FcPanel.new("Team comparison", FcPanel.Variant.FLAT)
	team_card = GridContainer.new()
	team_card.name = "TeamCard"
	team_card.columns = 3
	team_card.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	team_card.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	team_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.body.add_child(team_card)
	return panel


func _update_team_card(index: int) -> void:
	var card := FcBroadcastGraphics.team_card_at(timeline, index)
	if card.is_empty():
		return
	for child in team_card.get_children():
		team_card.remove_child(child)
		child.queue_free()
	var cells: Array = [["", str(card["abbreviations"][0]), str(card["abbreviations"][1])]]
	cells.append_array(card["rows"])
	for row in cells:
		for col in 3:
			var l := FcUiTables.label(str(row[col]), FcUiTokens.TYPE_SMALL, row == cells[0])
			l.theme_type_variation = "CaptionLabel" if col == 0 else "NumericLabel"
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			team_card.add_child(l)


func _roster_strip() -> Control:
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	for side in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := FcUiTables.label(model.box.abbreviations[side], FcUiTokens.TYPE_SMALL, true)   # plain text colour: a dark team colour is unreadable on this background
		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		var swatch := ColorRect.new()   # the team's colour, as drawn on the court
		swatch.color = colors[side]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_row.add_child(swatch)
		head_row.add_child(head)
		col.add_child(head_row)
		_roster_heads[side] = head
		for i in 5:
			var l := FcUiTables.label("", FcUiTokens.TYPE_SMALL)
			l.theme_type_variation = "CaptionLabel"
			col.add_child(l)
			_roster_labels[side].append(l)
		grid.add_child(col)
	return grid


func _fill_feed() -> void:
	feed.clear()
	_feed_indices = model.indices_for(filter)
	for i in _feed_indices:
		var e: Dictionary = model.entries[i]
		var text := "%s %s  %s" % [e["clock_text"], str(e["abbr"]), e["text"]]
		if e["points"] > 0:
			text += "  (%d-%d)" % [e["home"], e["away"]]
		feed.add_item(text)


# --- playing ------------------------------------------------------------------------------------------------------------------

## Shows event `i`. `animate` glides the players; stepping and scrubbing pass false for a clean jump when asked.
func seek(i: int, animate: bool = true) -> void:
	if model == null or model.is_empty():
		return
	_index = clampi(i, 0, model.size() - 1)
	_timer = 0.0
	var st := model.state_at(_index)
	if not animate:
		court.clear_trail()   # a jump or scrub: the earlier positions are not "just before"
	court.show_state(st, _names, animate)
	bug.setup(model.box.abbreviations[0], st["home"], model.box.abbreviations[1], st["away"], model.status_at(_index), colors[0], colors[1])
	bug.show_broadcast(timeline.snapshot(_index), model.box.abbreviations[0], model.box.abbreviations[1])
	overlay.show_item(FcBroadcastGraphics.top_item_at(timeline, _index))
	spotlight.show_model(FcSpotlightModel.at(timeline, _index))
	bug.show_shot_clock(FcShotClockModel.at(timeline, _index))
	bug.show_stoppage(FcStoppageModel.at(timeline, _index))
	_refresh_stats()
	_update_team_card(_index)
	_request_shot(not animate)
	if court3d != null and court3d.visible:
		court3d.show_event(_index, animate)
	sound_caption.text = ""   # a jump or a scrub makes no sound; stepping and playing set it again
	if not animate:
		_reset_booth()   # a jump: what was said before is no longer "just now"
	_update_ambience(_index)
	caption.text = "%s  %s" % [st["clock_text"], st["text"]] if st["text"] != "" else st["clock_text"]
	_update_rosters(st)
	_silent = true
	scrubber.value = _index
	tools.show_time(timeline.seconds_at(_index), timeline.total_seconds())
	tools.bookmark_button.text = "Remove bookmark" if bookmarks.has_bookmark(model.game_key(), _index) else "Bookmark this play"
	period_group.select(str(st["period"]))
	_silent = false
	_select_in_feed()
	event_shown.emit(_index)


func step(direction: int) -> void:
	var before := _index
	if direction < 0:
		_reset_booth()   # stepping back: the replay clock goes backwards, so the commentary starts afresh
	seek(model.step(_index, direction, filter), true)
	if direction > 0 and _index != before:
		_make_sounds(_index)   # stepping forward plays the next event's sounds; stepping back is silent


func toggle_play() -> void:
	if model == null or model.is_empty():
		return
	if is_show():
		end_show()   # Play (or Space) closes the show and goes back to the replay
		return
	if is_intro():
		end_introductions()   # Play (or Space) skips the introductions and goes back to the replay
		return
	if not _playing and _index >= model.final_index():
		seek(model.start_index(), false)   # play again from the tip-off
	_playing = not _playing
	play_button.text = "Pause" if _playing else "Play"
	set_process(_playing)


func set_speed(value: float) -> void:
	speed = clampf(value, 0.25, 8.0)
	_sync_speed_group()


## The speed buttons show the nearest speed to the real one.
func _sync_speed_group() -> void:
	var best := "1"
	var gap := 1e9
	for s in SPEEDS:
		if absf(float(s[0]) - speed) < gap:
			gap = absf(float(s[0]) - speed)
			best = str(s[0])
	if speed_group != null:
		speed_group.select(best)


## `[` and `]` step through the speed buttons.
func _nudge_speed(direction: int) -> void:
	var at := 0
	for k in SPEEDS.size():
		if absf(float(SPEEDS[k][0]) - speed) < absf(float(SPEEDS[at][0]) - speed):
			at = k
	set_speed(float(SPEEDS[clampi(at + direction, 0, SPEEDS.size() - 1)][0]))


func set_filter(id: String) -> void:
	filter = id
	filter_group.select(id)
	_fill_feed()
	_select_in_feed()


## One frame of playback: after the current event has been up for its dwell time (shorter at higher speeds) the next one is shown.
## At the end the replay pauses. Called every frame while playing, and directly by tests.
func advance(delta: float) -> void:
	if is_intro():
		_advance_intro(delta)   # the introductions run on real time, whether or not the replay is playing
		return
	if not _playing or model == null:
		return
	_timer += delta * speed
	if _timer < model.dwell(_index):
		return
	if is_reel():
		var windows: Array = state.reel["windows"]
		var at: int = state.reel["at"]
		if _index >= int(windows[at]["end"]):
			if at + 1 >= windows.size():
				end_reel()
				return
			state.reel["at"] = at + 1
			seek(int(windows[at + 1]["start"]), false)   # the next highlight: a clean cut to its first event, from the next angle
			tools.reel_note.text = _reel_note()
			return
		seek(_index + 1, true)
		_make_sounds(_index)
		return
	if not _instant.is_empty():
		if _index >= int(_instant["end"]):
			end_instant_replay()
			return
		seek(_index + 1, true)   # an instant replay shows every event of the play, whatever the feed filter is
		_make_sounds(_index)
		return
	var nxt := model.step(_index, 1, filter)
	if nxt == _index:
		_playing = false
		play_button.text = "Play"
		set_process(false)
		return
	seek(nxt, true)
	_make_sounds(_index)


## The arena ambience follows the game: louder when it is tight and late, quieter in a blowout or at a whistle (FcAmbienceModel).
func _update_ambience(index: int) -> void:
	FcAudio.ambience(FcAmbienceModel.level_at(timeline, index))


## A voice started or stopped speaking: the crowd and ambience duck while it does.
func _on_voice(role: String, on: bool) -> void:
	FcAudio.speaking(role, on)


func _reset_booth() -> void:
	booth.reset()
	analyst_label.text = ""
	announcer_label.text = ""


## Broadcast music (original, synthesised, off by default): plays only in the Broadcast mode and only when the player turned it on.
func _update_music() -> void:
	if prefs != null and prefs.broadcast_music and mode == FcPresentationMode.BROADCAST:
		FcAudio.music("music_broadcast")
	else:
		FcAudio.music_off()


func _exit_tree() -> void:
	if booth != null:
		booth.reset()
	FcAudio.ambience_off()
	FcAudio.music_off()


## The crowd and court sounds of event `i` and their caption. Called when playback advances or the user steps forward (never when scrubbing or
## jumping, so dragging the scrubber is silent). Sounds go through FcAudio.cue (silent when muted or no audio is running); the caption is
## shown unless the player turned captions off.
func _make_sounds(i: int) -> void:
	var cues := FcBroadcastAudio.cues_at(timeline, i)
	for id in cues:
		FcAudio.cue(id)
	if court3d != null and court3d.visible:
		court3d.react(cues)   # the 3D crowd stands up for a cheer
	var captions_on := FcAudio.current.prefs.sound_captions if FcAudio.current != null and is_instance_valid(FcAudio.current) else true
	var said := booth.on_event(timeline, i, timeline.seconds_at(i))   # the analyst, the narrator and the stadium announcer (M6)
	var line: Dictionary = said["line"]
	if not line.is_empty() and str(line["cue"]) != "":
		FcAudio.cue(str(line["cue"]))
	analyst_label.text = (caption_sink.latest(FcCommentaryEvents.ROLE_NARRATIVE) if caption_sink.latest(FcCommentaryEvents.ROLE_NARRATIVE) != "" else caption_sink.latest(FcCommentaryEvents.ROLE_COLOR)) if captions_on else ""
	announcer_label.text = caption_sink.latest(FcCommentaryEvents.ROLE_ANNOUNCER) if captions_on else ""
	sound_caption.text = FcBroadcastAudio.caption_for(cues) if captions_on else ""
	commentary_label.text = FcCommentary.line_at(timeline, i) if captions_on else ""


## Starts or stops an instant replay of the possession that led to the current event (master plan B2b option C): the same events, at half
## speed, with a REPLAY badge, then back to exactly where the live replay was. The replay is a cursor over the recorded events; nothing is
## rewound, simulated or changed.
func toggle_instant_replay() -> void:
	if _instant.is_empty():
		start_instant_replay()
	else:
		end_instant_replay()


func start_instant_replay() -> void:
	if model == null or model.is_empty() or not _instant.is_empty():
		return
	var window := timeline.replay_window(_index)
	state.replay_variant += 1   # each instant replay looks from the next angle: main, baseline, overhead
	_instant = {"start": int(window["start"]), "end": int(window["end"]), "return_index": _index, "speed": speed, "was_playing": _playing}
	_refresh_badge()
	replay_button.text = "Back to the game"
	court.clear_trail()
	speed = INSTANT_REPLAY_SPEED
	_playing = true
	set_process(true)
	play_button.text = "Pause"
	seek(int(_instant["start"]), false)


## Leaves the instant replay: the live position, speed and play or pause state come back exactly as they were.
func end_instant_replay() -> void:
	if _instant.is_empty():
		return
	var back := int(_instant["return_index"])
	speed = float(_instant["speed"])
	_playing = bool(_instant["was_playing"])
	_instant = {}
	_refresh_badge()
	replay_button.text = "Instant replay"
	set_process(_playing)
	play_button.text = "Pause" if _playing else "Play"
	court.clear_trail()
	seek(back, false)


func is_instant_replay() -> bool:
	return not _instant.is_empty()


func _process(delta: float) -> void:
	advance(delta)


## Bookmarks or un-bookmarks the current play (saved when the app gave the screen a bookmark file).
func toggle_bookmark() -> void:
	if model == null or model.is_empty():
		return
	bookmarks.toggle(model.game_key(), _index)
	_refresh_marks()
	tools.bookmark_button.text = "Remove bookmark" if bookmarks.has_bookmark(model.game_key(), _index) else "Bookmark this play"


## Gives the screen a bookmark store (the app's own file) and redraws the marks.
func set_bookmark_store(store: FcBookmarkStore) -> void:
	bookmarks = store
	if timeline != null and marks != null:
		_refresh_marks()


## Jumps to the next (1) or previous (-1) bookmark and pauses there; nothing happens when there is none that way.
func jump_mark(direction: int) -> void:
	var refs := FcReplayCollections.bookmarks(timeline, bookmarks.indices(model.game_key()))
	var target := -1
	for ref in refs:
		var at := int(ref["end"])
		if direction > 0 and at > _index:
			target = at
			break
		if direction < 0 and at < _index:
			target = at
	if target < 0:
		return
	if _playing:
		toggle_play()
	seek(target)


func _refresh_marks() -> void:
	var keys: Array = []
	for ref in FcReplayCollections.key_plays(timeline):
		keys.append(int(ref["end"]))
	var lights: Array = []
	for ref in package.get("refs", []):
		lights.append(int(ref["end"]))
	marks.set_marks(model.size(), keys, lights, bookmarks.indices(model.game_key()))
	tools.prev_mark.disabled = bookmarks.indices(model.game_key()).is_empty()
	tools.next_mark.disabled = tools.prev_mark.disabled
	tools.reel_note.text = _reel_note()


func _reel_note() -> String:
	var refs: Array = package.get("refs", [])
	if refs.is_empty():
		return "No highlight reel for this game."
	if is_reel():
		return "Highlight %d of %d" % [int(state.reel["at"]) + 1, (state.reel["windows"] as Array).size()]
	return "Reel: %d plays, %s" % [refs.size(), FcReplayTools.clock(float(package.get("seconds", 0.0)))]


## Plays the automatic highlight package one play after another (each as a reconstructed replay window), then returns to where the replay was.
func toggle_reel() -> void:
	if is_reel():
		end_reel()
	else:
		start_reel()


func start_reel() -> void:
	var refs: Array = package.get("refs", [])
	if model == null or model.is_empty() or refs.is_empty() or is_reel():
		return
	if is_instant_replay():
		end_instant_replay()
	var windows: Array = []
	for ref in refs:
		windows.append({"start": int(ref["start"]), "end": int(ref["end"])})
	state.reel = {"windows": windows, "at": 0, "return_index": _index, "speed": speed, "was_playing": _playing}
	tools.reel_button.text = "Stop reel"
	speed = 1.0
	_sync_speed_group()
	_playing = true
	set_process(true)
	play_button.text = "Pause"
	court.clear_trail()
	_refresh_badge()
	tools.reel_note.text = _reel_note()
	seek(int(windows[0]["start"]), false)


func end_reel() -> void:
	if not is_reel():
		return
	var back := int(state.reel["return_index"])
	speed = float(state.reel["speed"])
	_sync_speed_group()
	_playing = bool(state.reel["was_playing"])
	state.reel = {}
	tools.reel_button.text = "Highlight reel"
	set_process(_playing)
	play_button.text = "Pause" if _playing else "Play"
	court.clear_trail()
	_refresh_badge()
	tools.reel_note.text = _reel_note()
	seek(back, false)


func is_reel() -> bool:
	return not state.reel.is_empty()


func is_show() -> bool:
	return not state.show.is_empty()


## Tells the screen this game decided a title (FcReplay finds out from the season's playoffs): the championship presentation becomes available.
func set_title_context(context: Dictionary) -> void:
	title_context = context
	if tools != null:
		tools.championship_button.visible = not context.is_empty()


## A production show (FcProductionPlan: pregame, halftime, postgame or championship) over the stage, from the segments of its template. The replay
## goes to the show's moment (the tip-off, the half or the end), is paused, and comes back exactly as it was when the show ends.
func start_show(id: String) -> void:
	if model == null or model.is_empty():
		return
	var plan := FcProductionPlan.build(id, timeline, title_context)
	if plan.is_empty():
		return
	if is_show():
		show_panel.show_plan(plan)
		state.show["id"] = id
		seek(int(plan["index"]), false)
		return
	if is_reel():
		end_reel()
	if is_instant_replay():
		end_instant_replay()
	if is_intro():
		end_introductions()
	state.show = {"id": id, "return_index": _index, "speed": speed, "was_playing": _playing}
	_playing = false
	set_process(false)
	play_button.text = "Play"
	seek(int(plan["index"]), false)
	show_panel.show_plan(plan)
	apply_layout()
	show_panel.visible = hud != FcPresentationMode.HUD_HIDDEN


func end_show() -> void:
	if not is_show():
		return
	var back := int(state.show["return_index"])
	speed = float(state.show["speed"])
	_playing = bool(state.show["was_playing"])
	state.show = {}
	show_panel.visible = false
	apply_layout()
	set_process(_playing)
	play_button.text = "Pause" if _playing else "Play"
	seek(back, false)


func _on_show_reel(_refs: Array) -> void:
	end_show()
	start_reel()


func is_intro() -> bool:
	return not state.intro.is_empty()


## The dribbled ball hits the floor in the 3D view: a soft thump on the effects bus, at normal speed or slower, while playing, never in a rapid burst.
func _on_ball_bounced() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if FcBroadcastAudio.bounce_heard(now, _last_bounce_sound, speed, _playing):
		_last_bounce_sound = now
		FcAudio.cue(FcBroadcastAudio.CUE_BOUNCE)


## The player introductions (M5): the tip-off positions, then each starter in turn with a spotlight card and a close camera, visitors first.
## It uses the recorded starters and the reconstruction's tip-off only, then puts the replay back exactly as it was.
func toggle_introductions() -> void:
	if is_intro():
		end_introductions()
	else:
		start_introductions()


func start_introductions() -> void:
	if model == null or model.is_empty() or is_intro():
		return
	var steps := FcPlayerIntroductions.plan(timeline)
	if steps.is_empty():
		return
	if is_reel():
		end_reel()
	if is_instant_replay():
		end_instant_replay()
	state.intro = {"steps": steps, "at": 0, "timer": 0.0, "return_index": _index, "speed": speed, "was_playing": _playing}
	_playing = false
	set_process(true)
	play_button.text = "Play"
	tools.intro_button.text = "Skip introductions"
	seek(model.start_index(), false)
	_show_intro_step()


func end_introductions() -> void:
	if not is_intro():
		return
	var back := int(state.intro["return_index"])
	speed = float(state.intro["speed"])
	_playing = bool(state.intro["was_playing"])
	state.intro = {}
	tools.intro_button.text = "Player introductions"
	spotlight.show_model({})
	if court3d != null:
		court3d.show_introduction(0)
	set_process(_playing)
	play_button.text = "Pause" if _playing else "Play"
	seek(back, false)


func _show_intro_step() -> void:
	var step: Dictionary = (state.intro["steps"] as Array)[int(state.intro["at"])]
	spotlight.show_model(step["spotlight"])
	court.rig.request(step["shot"], true)
	if court3d != null:
		court3d.show_introduction(int(step["player_id"]))
	_make_intro_sound()


func _advance_intro(delta: float) -> void:
	state.intro["timer"] = float(state.intro["timer"]) + delta
	var steps: Array = state.intro["steps"]
	var at: int = state.intro["at"]
	if float(state.intro["timer"]) < float(steps[at]["seconds"]):
		return
	if at + 1 >= steps.size():
		end_introductions()
		return
	state.intro["at"] = at + 1
	state.intro["timer"] = 0.0
	_show_intro_step()


## A short crowd cheer as each player is announced.
func _make_intro_sound() -> void:
	FcAudio.cue("crowd_cheer_small")
	if court3d != null and court3d.visible:
		court3d.react(["crowd_cheer_small"])


## The replay angle: "auto" cycles main, baseline, overhead from one instant replay or reel highlight to the next; "0", "1", "2" fix it.
func set_replay_angle(id: String) -> void:
	state.replay_angle = -1 if id == "auto" else clampi(int(id), 0, 2)
	tools.angle_group.select(id)
	if is_instant_replay() or is_reel():
		_request_shot(true)


## The variant of the replay shot to ask for now.
func _replay_variant() -> int:
	if state.replay_angle >= 0:
		return state.replay_angle
	return int(state.reel["at"]) if is_reel() else state.replay_variant


func _unhandled_input(event: InputEvent) -> void:
	if model == null or model.is_empty() or not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			toggle_play()
		KEY_RIGHT:
			step(1)
		KEY_LEFT:
			step(-1)
		KEY_H:
			cycle_hud()
		KEY_S:
			toggle_stats()
		KEY_B:
			toggle_bookmark()
		KEY_R:
			toggle_instant_replay()
		KEY_I:
			toggle_introductions()
		KEY_COMMA:
			jump_highlight(-1)
		KEY_PERIOD:
			jump_highlight(1)
		KEY_BRACKETLEFT:
			_nudge_speed(-1)
		KEY_BRACKETRIGHT:
			_nudge_speed(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _on_feed_selected(item: int) -> void:
	if item >= 0 and item < _feed_indices.size():
		seek(_feed_indices[item], true)


func _select_in_feed() -> void:
	if feed == null or _feed_indices.is_empty():
		return
	var at := 0
	for k in _feed_indices.size():
		if _feed_indices[k] <= _index:
			at = k
		else:
			break
	feed.deselect_all()
	feed.select(at, false)
	if is_inside_tree():   # after the next frame's layout, or a list that has not been sized yet will not scroll
		get_tree().process_frame.connect(func() -> void:
			if is_instance_valid(feed):
				feed.ensure_current_is_visible(), CONNECT_ONE_SHOT)


func _update_rosters(st: Dictionary) -> void:
	for side in 2:
		var ids: Array = FcCourtLayout.order_by_position(st["on_court"][side], st["positions"])
		for i in 5:
			var label: Label = _roster_labels[side][i]
			if i < ids.size():
				var id: int = ids[i]
				label.text = "%s  %d pts  %d PF" % [_names.get(id, "?"), int(st["points"].get(id, 0)), int(st["fouls"].get(id, 0))]
			else:
				label.text = ""
		(_roster_heads[side] as Label).text = "%s  (team fouls %d)" % [model.box.abbreviations[side], int(st["team_fouls"][side])]
