class_name FcPlayerDevelopment
extends RefCounted
## The player's growth profile: how good he can become and how he gets there.
## This is only the PROFILE. The yearly progression/regression process that
## uses it is a later system (see docs/ROADMAP.md).

const MIN_PEAK_AGE := 20
const MAX_PEAK_AGE := 34

## Ceiling of overall ability, 0-100 (hidden from the player unless scouted).
var potential: int = 50
## Age around which the player is expected to peak.
var peak_age: int = 26
## Multiplier on growth speed. 1.0 = typical. Stored to 3 decimals (see
## FcChecks.quantize) so saves reload bit-for-bit identical.
var development_rate: float = 1.0:
	set(value):
		development_rate = FcChecks.quantize(value)
## How uneven progress is year to year, 0 (steady) to 1 (wild swings).
## Stored to 3 decimals, like development_rate.
var volatility: float = 0.2:
	set(value):
		volatility = FcChecks.quantize(value)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if potential < 0 or potential > 100:
		errors.append("potential %d must be 0-100" % potential)
	if peak_age < MIN_PEAK_AGE or peak_age > MAX_PEAK_AGE:
		errors.append("peak age %d must be %d-%d" % [peak_age, MIN_PEAK_AGE, MAX_PEAK_AGE])
	if development_rate < 0.25 or development_rate > 2.0:
		errors.append("development rate must be 0.25-2.0")
	if volatility < 0.0 or volatility > 1.0:
		errors.append("volatility must be 0-1")
	return errors


func to_dict() -> Dictionary:
	return {
		"potential": potential, "peak_age": peak_age,
		"development_rate": development_rate, "volatility": volatility,
	}


static func from_dict(data: Dictionary) -> FcPlayerDevelopment:
	var d := FcPlayerDevelopment.new()
	d.potential = int(data.get("potential", d.potential))
	d.peak_age = int(data.get("peak_age", d.peak_age))
	d.development_rate = float(data.get("development_rate", d.development_rate))
	d.volatility = float(data.get("volatility", d.volatility))
	return d
