class_name FcNameGenerator
extends RefCounted
## Picks believable first/last names for a person from a country. Each
## country mixes name pools by weight (see data/generation/names.json).
## Random choices use the supplied FcRng, so results are reproducible.

var _data: FcGenerationData


func _init(data: FcGenerationData) -> void:
	_data = data


## Country used when none (or an unknown one) is requested.
func home_country() -> String:
	return str(_data.names.get("fallback_country", ""))


## Nationality for a new person at a team in `team_country`: that country with
## probability `home_share`, otherwise any country by basketball talent weight.
func pick_origin(rng: FcRng, team_country: String, home_share: float) -> String:
	var countries: Dictionary = _data.names.get("countries", {})
	if countries.has(team_country) and rng.chance(home_share):
		return team_country
	var keys := country_keys()
	var weights: Array = []
	for k in keys:
		weights.append(float(countries[k].get("talent_weight", 1.0)))
	return keys[rng.weighted_index(weights)]


## A random team nickname (e.g. "Harriers") that is not in `taken` (keys are
## lowercase nicknames). Records the choice in `taken`. This is the "generate a
## name for me" button; users can type their own name instead. Returns "" only
## if every nickname in the data is already taken.
func random_team_nickname(rng: FcRng, taken: Dictionary) -> String:
	var pool: Array = []
	for nick in _data.world.get("nicknames", []):
		if not taken.has(str(nick).to_lower()):
			pool.append(str(nick))
	if pool.is_empty():
		return ""
	var pick: String = pool[rng.range_int(0, pool.size() - 1)]
	taken[pick.to_lower()] = true
	return pick


func country_keys() -> Array[String]:
	var out: Array[String] = []
	for k in _data.names.get("countries", {}):
		out.append(str(k))
	out.sort()
	return out


func country_name(country_key: String) -> String:
	return str(_data.names.get("countries", {}).get(country_key, {}).get("name", country_key))


## Returns {"first": String, "last": String}. Unknown countries fall back to
## the home country.
func generate(rng: FcRng, country_key: String) -> Dictionary:
	var countries: Dictionary = _data.names.get("countries", {})
	if not countries.has(country_key):
		country_key = home_country()
	var weights: Dictionary = countries[country_key]["pools"]
	var pool_keys: Array = weights.keys()
	pool_keys.sort()
	var weight_list: Array = []
	for k in pool_keys:
		weight_list.append(float(weights[k]))
	var pool_key: String = pool_keys[rng.weighted_index(weight_list)]
	var pool: Dictionary = _data.names["pools"][pool_key]
	var firsts: Array = pool["first"]
	var lasts: Array = pool["last"]
	return {
		"first": str(firsts[rng.range_int(0, firsts.size() - 1)]),
		"last": str(lasts[rng.range_int(0, lasts.size() - 1)]),
	}


## Like generate(), but avoids names already in `used` (full name -> true) and
## records the chosen one. After many attempts it accepts a duplicate rather
## than loop forever.
func generate_unique(rng: FcRng, country_key: String, used: Dictionary) -> Dictionary:
	var result := {}
	for attempt in 30:
		result = generate(rng, country_key)
		var full: String = "%s %s" % [result["first"], result["last"]]
		if not used.has(full):
			used[full] = true
			return result
	return result
