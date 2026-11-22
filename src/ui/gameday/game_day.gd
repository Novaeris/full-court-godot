class_name FcGameDay
extends RefCounted
## The game-day preview of the user's next regular-season game, for Owner and Career: who plays whom, where, both records and ranks,
## the five each coach would start (the same rule the game itself uses, so the preview and the game agree) and who is out hurt.
## `build` is pure and read-only; `open` shows it and offers "Play this game", which plays the days up to and including that game and
## then opens the game summary (with the replay). Lineups stay with the coaches in Owner Mode by design (the owner sets direction, not
## the starting five); Career asks for a role through its own screen and the preview shows the result.


## The model for the user's next regular-season game, or {} when there is none (season over, playoffs, no team).
static func for_owner(controller: FcGameController) -> Dictionary:
	var game := controller.next_user_game()
	if game == null:
		return {}
	return build(controller.state.world, controller.engine, controller.standings(), game, controller.state.user_team_id,
		controller.season().date_of_day(game.day).to_iso())


## {"date", "user_side", "sides": [home, away]} where each side is
## {"team_id", "name", "abbr", "record", "rank", "overall", "starters": [{"id", "name", "position", "overall"}], "out": [{"name", "games", "injury"}]}.
static func build(world: FcWorld, engine: FcSeasonEngine, standings: FcStandings, game: FcScheduledGame, user_team_id: int, date_iso: String) -> Dictionary:
	var ratings := FcPlayerRatings.load_default()
	var ranking := standings.league_ranking()
	var sides: Array = []
	for team_id in [game.home_id, game.away_id]:
		var team: FcTeam = world.teams.get_by_id(team_id)
		var squad := FcGameTeam.from_world(world, team_id, ratings, engine.composite_bonuses, engine.role_inputs)
		var starters: Array = []
		var total := 0.0
		for p in FcGameSimulator.new().projected_starters(squad):
			starters.append({"id": p.id, "name": FcPlayByPlay.short_name(p.name), "position": FcPosition.abbreviation(p.position), "overall": roundi(p.overall)})
			total += p.overall
		var out: Array = []
		for pid in team.roster.player_ids:
			var player: FcPlayer = world.players.get_by_id(pid)
			if player != null and player.games_out > 0:
				out.append({"name": FcPlayByPlay.short_name(player.identity.full_name()), "games": player.games_out, "injury": player.injury})
		var record: Dictionary = standings.records[team_id]
		sides.append({
			"team_id": team_id, "name": world.team_display_name(team_id), "abbr": team.identity.abbreviation,
			"record": "%d-%d" % [int(record["w"]), int(record["l"])], "rank": ranking.find(team_id) + 1,
			"overall": roundi(total / maxf(1.0, starters.size())), "starters": starters, "out": out,
		})
	return {"date": date_iso, "user_side": 0 if game.home_id == user_team_id else 1, "sides": sides}


## Shows the preview on the dialog layer. `on_play` runs after the dialog closes when the player presses "Play this game".
static func open(app: FcApp, model: Dictionary, world: FcWorld, on_play: Callable) -> FcModal:
	var home: Dictionary = model["sides"][0]
	var away: Dictionary = model["sides"][1]
	var modal := FcModal.new("Game day: %s at %s" % [away["abbr"], home["abbr"]], "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else 760
	var screen := FcGameDayScreen.new().setup(model, _looks(world, model), app.layout.is_mobile())
	screen.name = "GameDayScreen"
	modal.content.add_child(screen)
	var play := FcButton.make("Play this game", FcButton.Variant.PRIMARY, func() -> void:
		modal.close(false)
		on_play.call())
	play.name = "PlayGameButton"
	modal.content.add_child(play)
	var note := FcUiTables.label("Plays every day up to and including this game, then shows the game summary. You can watch the replay from there.", FcUiTokens.TYPE_SMALL)
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 120
	modal.content.add_child(note)
	app.host.modals.open(modal)
	return modal


static func _looks(world: FcWorld, model: Dictionary) -> Array:
	var out: Array = []
	for side in model["sides"]:
		var team: FcTeam = world.teams.get_by_id(int(side["team_id"]))
		out.append(FcTeamLook.resolve(FcTeamLook.subject_for_team(world, team)))
	return out
