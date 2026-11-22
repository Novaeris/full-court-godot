class_name FcPostGame
extends RefCounted
## Adapters that turn what each mode has about a finished game into the one post-game screen: Owner (a box score kept in the season,
## the league standings now), Career (the player's night against their season average, XP and milestones earned) and the dialog the
## screens open it in. Read-only: they ask the controllers for numbers and never change anything.


## Team colours of a box score's two sides (home, away) from the franchises' branding; neutral colours if a team is unknown.
static func team_colors(world: FcWorld, box: Dictionary) -> Array:
	var out: Array = []
	var fallback := [FcUiTokens.INFO, FcUiTokens.PRIMARY]
	for i in 2:
		var team: FcTeam = world.teams.get_by_id(int(box["team_ids"][i]))
		out.append(Color.html(team.branding.primary_color) if team != null and FcChecks.is_hex_color(team.branding.primary_color) else fallback[i])
	return out


## Which side of the box score is the user's team (-1 when it is neither).
static func user_side(box: Dictionary, user_team_id: int) -> int:
	for i in 2:
		if int(box["team_ids"][i]) == user_team_id:
			return i
	return -1


## A face for every player who appears in the box score, from the same resolver every other screen uses.
static func world_subjects(world: FcWorld, box: Dictionary, prefix: String) -> Dictionary:
	var out := {}
	for row in box["players"]:
		var pid := int(row["player_id"])
		out[pid] = FcPlayerPresentation.subject_for_player(world, pid, prefix)
	return out


## {"vm", "colors", "replay"} for an Owner Mode game kept in the season (`events` is its stored play-by-play, if any). The implications
## describe the standings as they are NOW.
static func for_owner(controller: FcGameController, box: Dictionary, events: Dictionary = {}) -> Dictionary:
	var world := controller.state.world
	var side := user_side(box, controller.state.user_team_id)
	var implications: Array = []
	if side >= 0:
		var rec := controller.user_record()
		implications.append("Season record now: %d-%d (rank %d in the league, %s)." % [rec["wins"], rec["losses"], rec["rank"], rec["streak"]])
	var vm := FcPostGameModel.build(box, {"user_side": side, "subjects": world_subjects(world, box, "owner_player"), "implications": implications})
	var colors := team_colors(world, box)
	return {"vm": vm, "colors": colors, "replay": FcReplay.build(box, events, colors)}


## {"vm", "colors"} for a Career game entry (as FcCareerController.advance_days returns it, with its "box"). The player's night is set
## against their season average, and the XP and milestones the game paid are listed.
static func for_career(career: FcCareerController, game: Dictionary) -> Dictionary:
	var world := career.state.world
	var box: Dictionary = game["box"]
	var side := user_side(box, career.state.user_team_id)
	var line: Dictionary = game["line"]
	var avg := career.season_line()
	var implications: Array = []
	if int(avg.get("games", 0)) > 0:
		implications.append("Your night: %d PTS, %d REB, %d AST. Season average: %.1f / %.1f / %.1f." % [line["points"], line["rebounds"], line["assists"], avg["points"], avg["rebounds"], avg["assists"]])
	else:
		implications.append("Your night: %d PTS, %d REB, %d AST." % [line["points"], line["rebounds"], line["assists"]])
	if game.has("duel"):
		implications.append("Duel with %s: %s (%d points for them)." % [game["duel"]["rival"], "won" if game["duel"]["won"] else "lost", game["duel"]["rival_points"]])
	var rewards: Array = ["+%d XP" % int(game["xp"])]
	if int(game.get("levels_gained", 0)) > 0:
		rewards.append("%d level%s gained" % [game["levels_gained"], "" if int(game["levels_gained"]) == 1 else "s"])
	for m in game.get("milestones", []):
		rewards.append(str(m).replace("_", " "))
	var vm := FcPostGameModel.build(box, {"user_side": side, "subjects": world_subjects(world, box, "career_player"), "implications": implications, "rewards": rewards})
	var colors := team_colors(world, box)
	return {"vm": vm, "colors": colors, "replay": FcReplay.build(box, game.get("events", {}), colors)}


## Opens a post-game dialog on the app's dialog layer.
static func open(app: FcApp, built: Dictionary) -> FcModal:
	var modal := FcModal.new("Game summary", "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else 820
	var replay_button := FcReplay.button_for(app, built.get("replay", {}))
	if replay_button != null:
		modal.content.add_child(replay_button)   # only when the play-by-play of this game was kept
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var screen := FcPostGameScreen.new().setup(built["vm"], built["colors"])
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(screen)
	modal.content.add_child(scroll)
	app.host.modals.open(modal)
	return modal
