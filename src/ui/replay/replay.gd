class_name FcReplay
extends RefCounted
## Adapters that turn what each mode keeps about a finished game into the one replay screen, the way FcPostGame does for the summary:
## Owner (the events stored beside the box score in the season), Career (the game entry the controller returns) and Dynasty (the result
## of a game just played). Read-only: they build a model and open a dialog; nothing is changed or saved.


## Whether an events dictionary holds a replay worth opening.
static func has_replay(events: Dictionary) -> bool:
	return not events.is_empty() and FcGameEventLog.from_dict(events).size() > 0


## {"model", "colors"} for a stored box (a Dictionary) and its events, or {} when no replay was kept.
static func build(box: Dictionary, events: Dictionary, colors: Array = []) -> Dictionary:
	if not has_replay(events) or box.is_empty():
		return {}
	var model := FcReplayModel.build(FcGameEventLog.from_dict(events), FcBoxScore.from_dict(box))
	if model.is_empty():
		return {}
	var palette := colors if colors.size() == 2 else [FcUiTokens.INFO, FcUiTokens.PRIMARY]
	return {"model": model, "colors": palette}


## Owner: a stored season entry {day, series, box, events}.
static func for_owner(controller: FcGameController, entry: Dictionary) -> Dictionary:
	return build(entry["box"], entry.get("events", {}), FcPostGame.team_colors(controller.state.world, entry["box"]))


## Career: a game entry as FcCareerController.advance_days returns it.
static func for_career(career: FcCareerController, game: Dictionary) -> Dictionary:
	return build(game["box"], game.get("events", {}), FcPostGame.team_colors(career.state.world, game["box"]))


## Dynasty: the result data of a game just played (it has "box" and "events", not saved).
static func for_dynasty(game: Dictionary) -> Dictionary:
	return build(game.get("box", {}), game.get("events", {}))


## Opens the replay on the app's dialog layer.
static func open(app: FcApp, built: Dictionary) -> FcModal:
	var model: FcReplayModel = built["model"]
	var title := "Replay: %s at %s" % [model.box.abbreviations[1], model.box.abbreviations[0]]
	var modal := FcModal.new(title, "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else _dialog_width(app)
	var screen := FcReplayScreen.new().setup(model, built["colors"], app.layout.is_mobile(), app.preferences)
	screen.name = "ReplayScreen"
	modal.content.add_child(screen)
	app.host.modals.open(modal)
	return modal


## Wide windows get a wider replay dialog so the court has room; 1040 is the floor (and the width when the window is not known yet).
static func _dialog_width(app: FcApp) -> float:
	var window := app.get_window() if app.is_inside_tree() else null
	return clampf(float(window.size.x) * 0.85, 1040.0, 2200.0) if window != null else 1040.0


## A "Watch replay" button for a post-game screen, or null when no replay was kept (the box is still there, just not the events).
static func button_for(app: FcApp, built: Dictionary) -> Button:
	if built.is_empty():
		return null
	return FcButton.make("Watch replay", FcButton.Variant.PRIMARY, func() -> void: open(app, built))
