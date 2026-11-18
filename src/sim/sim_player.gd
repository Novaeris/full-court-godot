class_name FcSimPlayer
extends RefCounted
## One player's working state during a simulated game: his composite ratings
## (computed once), tendencies, energy, fouls and box-score line. Built from an
## FcPlayer; the FcPlayer itself is never changed by a game.

var id: int
var name: String
var position: int
var ratings: Dictionary
var overall: float
## Tendencies 0-100 (how often he shoots threes, drives, posts up...).
var tend_three: float
var tend_mid: float
var tend_drive: float
var tend_post: float
var tend_pass: float
var tend_foul: float
var tend_oreb: float
var consistency: float
var stamina: float
var durability: float

var energy: float = 100.0
var fouls: int = 0
var on_court: bool = false
## Per-game hot/cold streak added to shooting percentages.
var form: float = 0.0
var stats := FcPlayerGameStats.new()
## Court time as a precise float; copied into stats.seconds when the game ends.
var seconds_f: float = 0.0
## Set when he is hurt during this game: he leaves and cannot return.
var injured: bool = false
var injury_games: int = 0
var injury_name: String = ""


## `composite_bonus` ({composite name: points}) is only given for a Career Mode player's equipped badges (already capped by
## FcCareerRules); it adds to the named composite ratings, never to the overall. Empty for everyone else.
func _init(player: FcPlayer, rating_calculator: FcPlayerRatings, team_id: int, composite_bonus: Dictionary = {}) -> void:
	id = player.id
	name = player.identity.full_name()
	position = player.primary_position
	ratings = rating_calculator.compute(player)
	for composite in composite_bonus:
		if ratings.has(composite):
			ratings[composite] = clampf(float(ratings[composite]) + float(composite_bonus[composite]), 0.0, 100.0)
	overall = ratings["overall"]
	tend_three = player.tendencies.get_value("three_point_tendency")
	tend_mid = player.tendencies.get_value("mid_range_tendency")
	tend_drive = player.tendencies.get_value("drive_tendency")
	tend_post = player.tendencies.get_value("post_tendency")
	tend_pass = player.tendencies.get_value("pass_tendency")
	tend_foul = player.tendencies.get_value("foul_tendency")
	tend_oreb = player.tendencies.get_value("offensive_rebound_tendency")
	consistency = player.attributes.get_value("consistency")
	stamina = float(player.attributes.get_value("stamina"))
	durability = float(player.attributes.get_value("durability"))
	stats.player_id = id
	stats.team_id = team_id
	stats.name = name
	stats.position = position


## Energy as a 0.0-1.0 performance factor: 1.0 fresh, lower when tired.
func freshness() -> float:
	return clampf(energy / 100.0, 0.0, 1.0)
