class_name FcReplay
extends RefCounted
## Adapters that turn what each mode keeps about a finished game into the one replay screen, the way FcPostGame does for the summary:
## Owner (the events stored beside the box score in the season), Career (the game entry the controller returns) and Dynasty (the result
## of a game just played). Read-only: they build a model and open a dialog; nothing is changed or saved.


## Whether an events dictionary holds a replay worth opening.
static func has_replay(events: Dictionary) -> bool:
	return not events.is_empty() and FcGameEventLog.from_dict(events).size() > 0


## {"model", "colors"} for a stored box (a Dictionary) and its events, or {} when no replay was kept.
static func build(box: Dictionary, events: Dictionary, colors: Array = [], subjects: Array = []) -> Dictionary:
	if not has_replay(events) or box.is_empty():
		return {}
	var model := FcReplayModel.build(FcGameEventLog.from_dict(events), FcBoxScore.from_dict(box))
	if model.is_empty():
		return {}
	var palette := colors if colors.size() == 2 else [FcUiTokens.INFO, FcUiTokens.PRIMARY]
	return {"model": model, "colors": palette, "subjects": subjects}


## Owner: a stored season entry {day, series, box, events}.
static func for_owner(controller: FcGameController, entry: Dictionary) -> Dictionary:
	return build(entry["box"], entry.get("events", {}), FcPostGame.team_colors(controller.state.world, entry["box"]), _subjects(controller.state.world, entry["box"]))


## Career: a game entry as FcCareerController.advance_days returns it.
static func for_career(career: FcCareerController, game: Dictionary) -> Dictionary:
	return build(game["box"], game.get("events", {}), FcPostGame.team_colors(career.state.world, game["box"]), _subjects(career.state.world, game["box"]))


## Dynasty: the result data of a game just played (it has "box" and "events", not saved).
static func for_dynasty(game: Dictionary) -> Dictionary:
	return build(game.get("box", {}), game.get("events", {}))


## The two teams' look subjects (home, away) for the scoreboard crests, or [] when a team is unknown (Dynasty has no world teams).
static func _subjects(world: FcWorld, box: Dictionary) -> Array:
	var out: Array = []
	for i in 2:
		var team: FcTeam = world.teams.get_by_id(int(box["team_ids"][i]))
		if team == null:
			return []
		out.append(FcTeamLook.subject_for_team(world, team))
	return out


## Opens the replay on the app's dialog layer.
static func open(app: FcApp, built: Dictionary) -> FcModal:
	var model: FcReplayModel = built["model"]
	var title := "Replay: %s at %s" % [model.box.abbreviations[1], model.box.abbreviations[0]]
	var modal := FcModal.new(title, "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else _dialog_width(app)
	var screen := FcReplayScreen.new().setup(model, built["colors"], app.layout.is_mobile(), app.preferences, built.get("subjects", []))
	screen.name = "ReplayScreen"
	screen.set_bookmark_store(FcBookmarkStore.new())   # the person's own bookmark file, apart from saved games
	if app.layout.is_mobile():
		modal.content.add_child(screen)
	else:
		# a desktop dialog is most of the window tall, and its content scrolls when a mode shows more than fits (Analysis on a short window)
		var scroll := ScrollContainer.new()
		scroll.name = "ReplayScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = _window_size(app).y * 0.8
		screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(screen)
		modal.content.add_child(scroll)
	app.host.modals.open(modal)
	return modal


## Wide windows get a wider replay dialog so the court has room; 1040 is the floor (and the width when the window is not known yet).
static func _dialog_width(app: FcApp) -> float:
	return clampf(_window_size(app).x * 0.85, 1040.0, 2200.0)


## The size of the window the dialog opens in: the viewport once the app is in the tree, the OS window before that (the screenshot tool opens
## dialogs at once).
static func _window_size(app: FcApp) -> Vector2:
	return app.get_viewport().get_visible_rect().size if app.is_inside_tree() else Vector2(DisplayServer.window_get_size())


## A "Watch replay" button for a post-game screen, or null when no replay was kept (the box is still there, just not the events).
static func button_for(app: FcApp, built: Dictionary) -> Button:
	if built.is_empty():
		return null
	return FcButton.make("Watch replay", FcButton.Variant.PRIMARY, func() -> void: open(app, built))
