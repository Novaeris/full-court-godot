class_name FcTonight
extends RefCounted
## "Full Court Tonight" for an Owner league (Broadcast pass 2, M7): collects the saved league data the weekly show needs (the season's results, the league
## structure, team names, the kept box scores, the playoff format) and opens the show. The week is the last seven days that were played. All the
## content is FcWeeklyRecap's; this class only gathers inputs and shows a panel, and changes nothing in the game.


## The input dictionary of FcWeeklyRecap.build for the Owner's current season ({} before any day has been played).
static func input_for(controller: FcGameController) -> Dictionary:
	var season := controller.season()
	if season == null or season.next_day <= 0:
		return {}
	var world := controller.state.world
	var league: FcLeague = world.leagues.get_by_id(controller.league_id)
	var names := {}
	var abbrs := {}
	for id in league.all_team_ids():
		names[id] = world.team_display_name(id)
		var team: FcTeam = world.teams.get_by_id(id)
		abbrs[id] = team.identity.abbreviation if team != null else "T%d" % id
	var entries: Array = []
	for e in season.recent_boxes:
		entries.append({"day": int(e["day"]), "series": int(e.get("series", 0)), "box": FcBoxScore.from_dict(e["box"])})
	var rules := world.rules_of_league(controller.league_id)
	var cutoff := 0
	if rules != null and rules.playoffs.bracket == "conference":
		cutoff = rules.playoffs.bracket_size(league)
	var week_end := season.next_day - 1
	var games: Array = []
	games.assign(season.games)
	return {"games": games, "league": league, "names": names, "abbrs": abbrs, "week_start": maxi(0, week_end - (FcWeeklyRecap.WEEK_DAYS - 1)), "week_end": week_end,
		"box_entries": entries, "cutoff": cutoff, "date_text": func(day: int) -> String: return season.date_of_day(day).to_iso()}


## The show for the Owner's league, or {} when nothing has been played yet.
static func plan_for(controller: FcGameController) -> Dictionary:
	var input := input_for(controller)
	return FcWeeklyRecap.build(input) if not input.is_empty() else {}


## Opens Full Court Tonight on the app's dialog layer. With nothing played yet it says so instead.
static func open(app: FcApp, controller: FcGameController) -> void:
	var plan := plan_for(controller)
	if plan.is_empty():
		app.host.modals.notice("Full Court Tonight", "The show starts once the season has begun: there are no games to talk about yet.")
		return
	var modal := FcModal.new("Full Court Tonight", "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else 760
	var panel := FcProductionPanel.new()
	panel.name = "TonightPanel"
	panel.custom_minimum_size.y = 360
	panel.closed.connect(func() -> void: modal.close(false))
	modal.content.add_child(panel)
	panel.show_plan(plan)
	app.host.modals.open(modal)
