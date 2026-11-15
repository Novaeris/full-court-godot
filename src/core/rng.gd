class_name FcRng
extends RefCounted
## Seeded random number source used by ALL simulation and generation code.
##
## Why this exists: games must be reproducible. Given the same seed, the same
## sequence of calls must produce the same results, so any bug found in a
## simulated season can be replayed exactly. Never call Godot's global
## randf()/randi() in simulation code; always use an FcRng.
##
## Use fork() to give each subsystem (game sim, draft, injuries...) its own
## independent stream, so adding a random call in one system does not change
## the results of another.

var _rng := RandomNumberGenerator.new()
var _seed: int = 0


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_seed = seed_value
	_rng.seed = seed_value


func get_seed() -> int:
	return _seed


## Returns a new, independent generator derived from this seed and a label.
## The same (seed, label) pair always gives the same child stream.
func fork(label: String) -> FcRng:
	return FcRng.new(hash("%d:%s" % [_seed, label]))


## Float in [0.0, 1.0).
func next_float() -> float:
	return _rng.randf()


## Integer in [from, to], both inclusive.
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Float in [from, to].
func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## True with the given probability (0.0 to 1.0).
func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Normally distributed value (bell curve).
func gaussian(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)


## Picks an index according to weights. Weights must be >= 0 and not all zero.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	assert(total > 0.0, "FcRng.weighted_index needs a positive total weight")
	var roll := _rng.randf() * total
	var running := 0.0
	for i in weights.size():
		running += float(weights[i])
		if roll < running:
			return i
	return weights.size() - 1


## Saves the generator position so it can be restored after loading a save.
## Values are stored as TEXT because the internal state is a 64-bit number and
## JSON numbers are doubles, which would silently lose precision.
func get_state() -> Dictionary:
	return {"seed": str(_seed), "state": str(_rng.state)}


func set_state(data: Dictionary) -> void:
	_seed = int(data["seed"])
	_rng.seed = _seed
	_rng.state = int(data["state"])
