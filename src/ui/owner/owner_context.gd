class_name FcOwnerContext
extends RefCounted
## What an Owner Mode tab needs from the app, and nothing more (docs/VISUAL_IDENTITY_PLAN.md, 5.6): the game controller (the one API screens use),
## and the few things only the app can do (say something, rebuild the dashboard, open a dialog). Tabs are built from a context, never by reaching
## into FcApp, so they can be tested alone and FcApp stays a router. Also caches each team's resolved look so a table of 30 teams resolves
## each crest once.

var controller: FcGameController
## Callable(text: String): shows a message (a toast).
var say: Callable
## Callable(): rebuilds the dashboard after a change (the user's data moved).
var refresh: Callable
## Callable(entry: Dictionary): opens the post-game screen for a stored box-score entry.
var open_post_game: Callable
## Callable(player_id: int): opens the player profile dialog.
var open_profile: Callable
var _looks: Dictionary = {}


func _init(game_controller: FcGameController = null, say_callable: Callable = Callable(), refresh_callable: Callable = Callable(),
		post_game_callable: Callable = Callable(), profile_callable: Callable = Callable()) -> void:
	controller = game_controller
	say = say_callable
	refresh = refresh_callable
	open_post_game = post_game_callable
	open_profile = profile_callable


func world() -> FcWorld:
	return controller.state.world


func user_team_id() -> int:
	return controller.state.user_team_id


func team_name(team_id: int) -> String:
	return world().team_display_name(team_id)


## The resolved identity of a team (crest, colours, wordmark): the same look every screen shows.
func team_look(team_id: int) -> Dictionary:
	if not _looks.has(team_id):
		var team: FcTeam = world().teams.get_by_id(team_id)
		_looks[team_id] = FcTeamLook.resolve(FcTeamLook.subject_for_team(world(), team)) if team != null else FcTeamLook.resolve(FcTeamLook.subject("team:%d" % team_id, "-", "", "", ""))
	return _looks[team_id]


## A crest and name for a team, as a control (marks the user's team).
func team_chip(team_id: int, crest_px: int = 24, text: String = "") -> FcTeamChip:
	return FcTeamChip.new().setup(team_look(team_id), text if text != "" else team_name(team_id), crest_px, team_id == user_team_id(), false)


## A message, when a message callable was given.
func tell(text: String) -> void:
	if say.is_valid():
		say.call(text)
