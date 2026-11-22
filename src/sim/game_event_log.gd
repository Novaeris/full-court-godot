class_name FcGameEventLog
extends RefCounted
## The play-by-play record of one simulated game, kept as compact integer rows so it can be saved, replayed and narrated later.
##
## WHY A SEPARATE RECORDER: the simulator decides everything with its seeded random numbers. This log only WRITES DOWN what
## the simulator already decided (it never asks the random generator for anything), so switching it on cannot change a game:
## the same teams and seed give the identical box score with or without it (tests/unit/test_game_events.gd proves it).
##
## ROW LAYOUT (six whole numbers, no floats, so saves never lose precision):
##   [type, clock_tenths, side, a, b, x]
##   type          one of the EV_* constants below
##   clock_tenths  time left in the period, in tenths of a second
##   side          0 = home, 1 = away: the team the event belongs to (see each type)
##   a, b, x       type-specific, listed with each constant
## The period and the running score are NOT stored: they are worked out by FcPlayByPlay from the rows, so there is only one
## truth (the rows) and nothing that can disagree with the box score.

const ROW_SIZE := 6
const COL_TYPE := 0
const COL_CLOCK := 1
const COL_SIDE := 2
const COL_A := 3
const COL_B := 4
const COL_X := 5

## x = period number (1-4, then 5 and up for overtimes).
const EV_PERIOD_START := 1
## side, a = player id: who starts the game on court.
const EV_STARTER := 2
## side = shooter's team, a = shooter, b = passer (0 = unassisted), x = shot kind (SHOT_*).
const EV_SHOT_MADE := 3
## side = shooter's team, a = shooter, x = shot kind.
const EV_SHOT_MISSED := 4
## side = shooter's team, a = shooter, b = blocker, x = shot kind.
const EV_SHOT_BLOCKED := 5
## side = rebounding team, a = player (0 for a team rebound), x = 1 if offensive, 0 if defensive.
const EV_REBOUND := 6
## side = team that lost the ball, a = ball handler, b = thief (0 = none credited).
const EV_TURNOVER := 7
## side = fouling team, a = fouler, x = FOUL_* kind.
const EV_FOUL := 8
## side = shooter's team, a = shooter, b = attempt number * 10 + attempts in the trip (12 = "1 of 2"), x = 1 if made.
const EV_FREE_THROW := 9
## side, a = player coming in, b = player going out.
const EV_SUBSTITUTION := 10
## side, a = player hurt, b = games he will miss.
const EV_INJURY := 11
## x = period number.
const EV_PERIOD_END := 12
const EV_GAME_END := 13

const SHOT_THREE := 0
const SHOT_MID := 1
const SHOT_RIM := 2

const FOUL_PERSONAL := 0
const FOUL_SHOOTING := 1
const FOUL_INTENTIONAL := 2

## The rows, oldest first. Each is an Array of ROW_SIZE ints.
var rows: Array = []


func clear() -> void:
	rows.clear()


func size() -> int:
	return rows.size()


## Writes one event down. Pure bookkeeping: it must never call the random generator.
func add(type: int, clock_tenths: int, side: int, a: int = 0, b: int = 0, x: int = 0) -> void:
	rows.append([type, maxi(0, clock_tenths), side, a, b, x])


## Points a made shot is worth.
static func points_of(kind: int) -> int:
	return 3 if kind == SHOT_THREE else 2


## The saved form: rows as plain integer arrays.
func to_dict() -> Dictionary:
	return {"rows": rows.duplicate(true)}


## Reads a saved log. Anything malformed is skipped rather than crashing a load (old or damaged saves).
static func from_dict(data: Dictionary) -> FcGameEventLog:
	var log := FcGameEventLog.new()
	var raw = data.get("rows", [])
	if not (raw is Array):
		return log
	for row in raw:
		if not (row is Array) or row.size() != ROW_SIZE:
			continue
		var clean: Array = []
		for v in row:
			clean.append(int(v))
		log.rows.append(clean)
	return log
