class_name FcGameAvailability
extends RefCounted
## What a screen may offer for one game (D-077 D): the one place that decides which buttons a game gets, from what is really stored, so no
## screen ever offers an action the data cannot fulfil. Pure: it reads the season and changes nothing.
##
##   game                          | watch / replay | box score | play-by-play | result line | preview | follow
##   user team, not played          | watch live (*) | –         | –            | –           | yes     | –
##   user team, played, box kept    | yes            | yes       | yes (if any) | yes         | –       | –
##   user team, played, box dropped | –              | –         | –            | yes         | –       | –
##   other teams, not played        | –              | –         | –            | –           | yes     | yes (until FOLLOW_LIMIT)
##   other teams, played            | if followed    | if kept   | if kept      | yes         | –       | –
##   archived season                | –              | –         | –            | score only  | –       | –
## (*) "watch live" plays the day up to the game with recording on and then opens the broadcast; only the next unplayed game of the
## user's team can be watched live (earlier days must be played first).

const FOLLOW_LIMIT := 20


## {"preview", "watch_live", "replay", "box_score", "play_by_play", "result_line", "final_score", "follow", "followed", "user_game"} (all bool).
static func capabilities(season: FcSeason, game: FcScheduledGame, user_team_id: int, next_user_game: FcScheduledGame = null) -> Dictionary:
	var user_game := user_team_id > 0 and game.involves(user_team_id)
	var entry := stored_box(season, game)
	var has_box := not entry.is_empty()
	var has_events := has_box and not (entry.get("events", {}).get("rows", []) as Array).is_empty()
	var followed := season.followed.has(game.id)
	return {
		"user_game": user_game,
		"followed": followed,
		"preview": not game.played and not season.archived,
		"watch_live": not game.played and user_game and next_user_game != null and next_user_game.id == game.id,
		"replay": game.played and has_events,
		"box_score": game.played and has_box,
		"play_by_play": game.played and has_events,
		"result_line": game.played and not game.line.is_empty(),
		"final_score": game.played,
		"follow": not game.played and not user_game and not followed and season.followed.size() < FOLLOW_LIMIT and not season.archived,
	}


## The stored box-score entry of a game ({} when none was kept): the user team's recent games and the followed games.
static func stored_box(season: FcSeason, game: FcScheduledGame) -> Dictionary:
	for source in [season.recent_boxes, season.followed_boxes]:
		for entry in source:
			if game.id > 0 and int(entry.get("game_id", 0)) == game.id:
				return entry
			if int(entry.get("game_id", 0)) == 0 and int(entry.get("day", -1)) == game.day and int(entry.get("series", 0)) == game.series:
				var box: Dictionary = entry.get("box", {})
				var ids: Array = box.get("team_ids", [])
				if ids.size() == 2 and int(ids[0]) == game.home_id and int(ids[1]) == game.away_id:
					return entry
	return {}
