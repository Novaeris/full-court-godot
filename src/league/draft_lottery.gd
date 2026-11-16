class_name FcDraftLottery
extends RefCounted
## Turns the teams that missed the playoffs (worst record first) into the draft
## order. With a lottery, the top `lottery_picks` picks are drawn among the worst
## `lottery_teams` teams with odds that favor the worst records; the rest of those
## teams (and everyone else) keep their record order. A team can therefore fall at
## most `lottery_picks` places below its record position. Draws use the seeded rng,
## so results are reproducible.

## `worst_first`: non-playoff team ids, worst record first. Returns the same ids in draft order.
static func order(worst_first: Array[int], rules: FcDraftRules, rng: FcRng) -> Array[int]:
	if rules.lottery_teams <= 0 or worst_first.size() < 2:
		return worst_first.duplicate()
	var entrants: Array[int] = worst_first.slice(0, mini(rules.lottery_teams, worst_first.size()))
	var rest: Array[int] = worst_first.slice(entrants.size())
	var drawn: Array[int] = []
	var pool: Array[int] = entrants.duplicate()
	for slot in mini(rules.lottery_picks, entrants.size()):
		var weights: Array[float] = []
		var total := 0.0
		for i in pool.size():
			# entrants are in worst-first order, so the first has the most weight
			var w := pow(float(entrants.size() - entrants.find(pool[i])), rules.odds_power)
			weights.append(w)
			total += w
		var roll := rng.range_float(0.0, total)
		var pick := pool.size() - 1
		var running := 0.0
		for i in pool.size():
			running += weights[i]
			if roll < running:
				pick = i
				break
		drawn.append(pool[pick])
		pool.remove_at(pick)
	var out: Array[int] = []
	out.append_array(drawn)
	out.append_array(pool)   # undrawn lottery teams keep record order
	out.append_array(rest)
	return out
