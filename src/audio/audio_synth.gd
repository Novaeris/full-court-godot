class_name FcAudioSynth
extends RefCounted
## Builds a short sound from a recipe (see data/ui/audio.json): a list of layers, each a tone (sine, triangle, square, saw) or noise with a
## start time, length, gain, exponential decay, optional pitch glide and a gentle low-pass. The game makes its own UI sounds this way so
## it ships no third-party audio (decision D4); a real audio file named in the sound map replaces the built sound when it exists.
## Pure and deterministic: the same recipe and id always give the same samples (noise comes from a small local generator, not the
## game's random numbers), so tests can check lengths and loudness.

const MIX_RATE := 22050
const PEAK := 0.89   # the loudest sample after normalising, below clipping


## Mono 16-bit samples for `recipe` ({"layers": [...]}). `seed_text` decorrelates the noise of different sounds.
static func render(recipe: Dictionary, seed_text: String = "") -> PackedFloat32Array:
	var layers: Array = recipe.get("layers", [])
	var total_ms := 0
	for layer in layers:
		total_ms = maxi(total_ms, int(layer.get("start_ms", 0)) + int(layer.get("ms", 0)))
	var count := int(total_ms / 1000.0 * MIX_RATE)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var state := _seed(seed_text)
	for layer in layers:
		state = _add_layer(mix, layer, state)
	var loudest := 0.0
	for i in count:
		loudest = maxf(loudest, absf(mix[i]))
	if loudest > 0.0:
		var scale := PEAK / loudest if loudest > PEAK else 1.0
		for i in count:
			mix[i] *= scale
	return mix


## An AudioStreamWAV (16-bit mono) from a recipe.
static func stream(recipe: Dictionary, seed_text: String = "") -> AudioStreamWAV:
	var samples := render(recipe, seed_text)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


static func duration_ms(recipe: Dictionary) -> int:
	var total := 0
	for layer in recipe.get("layers", []):
		total = maxi(total, int(layer.get("start_ms", 0)) + int(layer.get("ms", 0)))
	return total


static func _seed(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = ((h ^ text.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	return h if h != 0 else 1


static func _next(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0xFFFFFFFF


## Adds one layer into `mix`; returns the noise generator state for the next layer.
static func _add_layer(mix: PackedFloat32Array, layer: Dictionary, noise_state: int) -> int:
	var start := int(int(layer.get("start_ms", 0)) / 1000.0 * MIX_RATE)
	var length := int(int(layer.get("ms", 0)) / 1000.0 * MIX_RATE)
	var gain := float(layer.get("gain", 0.5))
	var decay := float(layer.get("decay", 10.0))
	var attack := maxf(1.0, float(layer.get("attack_ms", 2)) / 1000.0 * MIX_RATE)
	var wave := str(layer.get("wave", "sine"))
	var freq := float(layer.get("freq", 440.0))
	var freq_to := float(layer.get("freq_to", freq))
	var smooth := clampf(float(layer.get("lowpass", 1.0)), 0.02, 1.0)
	var phase := 0.0
	var filtered := 0.0
	for i in length:
		var at := start + i
		if at >= mix.size():
			break
		var t := float(i) / MIX_RATE
		var progress := float(i) / maxf(1.0, float(length))
		var envelope := minf(1.0, float(i) / attack) * exp(-decay * t)
		var value := 0.0
		if wave == "noise":
			noise_state = _next(noise_state)
			var white := float(noise_state) / 2147483648.0 - 1.0
			filtered += (white - filtered) * smooth
			value = filtered
		else:
			phase += TAU * lerpf(freq, freq_to, progress) / MIX_RATE
			var cycle := fmod(phase, TAU) / TAU
			match wave:
				"triangle":
					value = 4.0 * absf(cycle - 0.5) - 1.0
				"square":
					value = 1.0 if cycle < 0.5 else -1.0
				"saw":
					value = 2.0 * cycle - 1.0
				_:
					value = sin(phase)
			if smooth < 1.0:
				filtered += (value - filtered) * smooth   # a softer horn: the harsh top is rounded off
				value = filtered
		mix[at] += value * envelope * gain
	return noise_state
