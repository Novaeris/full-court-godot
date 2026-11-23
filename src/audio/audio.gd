class_name FcAudio
extends Node
## The game's sound, owned by FcApp (not an autoload). Five buses: Master, UI, SFX, Music and Crowd (the game's crowd and arena reactions; Music is empty for now: no music has been
## licensed or made, and nothing unlicensed is ever added, decision D4). Sounds come from data/ui/audio.json: an id, a bus, and where the
## sound comes from, which is the audio file if it exists and otherwise a short sound built by FcAudioSynth. An unknown id, a missing
## file or a muted game is simply silent, so the game is fully playable with the sound off.
## Screens do not hold an FcAudio; they call FcAudio.cue("id"), which does nothing when no audio is running (tests, tools).
##
## Broadcast pass 2, M6: three more buses (Ambience, Commentary, Announcer); LOOPS (the arena ambience bed in three intensities that crossfade, and
## the original synthesised music pads), each with a smooth fade; and DUCKING (FcDuckingModel): while a voice speaks the Crowd, Ambience and
## Music buses step down and come back. Loops and fades advance in `advance(delta)` (called every frame), so tests drive them without an audio
## device. Commentary content lives elsewhere (FcCommentaryBooth); this class only plays sound.

const MAP_PATH := "res://data/ui/audio.json"
const VOICES := 8
const HISTORY := 40
const FADE_SECONDS := 1.5
const AMBIENCE_IDS := ["ambience_low", "ambience_mid", "ambience_high"]
const SILENT := 0.001

## The audio of the running app (set by FcApp), so any screen can fire a cue without a reference.
static var current: FcAudio = null

var prefs: FcPreferences
var sounds: Dictionary = {}   # id -> {bus, gain_db, stream (or null), source "file" or "synth"}
var buses: Array = []
## The ids that were asked for (newest last, capped), whether or not they could be heard: tests and the settings screen read it.
var requested: Array[String] = []
## Background loops: id -> {player (or null when there is no audio device or tree), level (0 to 1, what is playing now), target, rate (per second)}.
var _loops: Dictionary = {}
## Ducking of the background buses while a voice speaks.
var ducking := FcDuckingModel.new()
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0


func _init(preferences: FcPreferences = null, map_path: String = MAP_PATH) -> void:
	prefs = preferences if preferences != null else FcPreferences.new()
	_load_map(map_path)


func _ready() -> void:
	setup_buses()
	apply_settings()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(delta: float) -> void:
	advance(delta)


## Static shortcuts for the broadcast (all do nothing when no audio is running): the arena ambience intensity (0 to 1), a voice starting or stopping
## (so the crowd ducks), and the broadcast music.
static func ambience(level: float) -> void:
	if current != null and is_instance_valid(current):
		current.set_ambience_level(level)


static func ambience_off() -> void:
	if current != null and is_instance_valid(current):
		current.stop_ambience()


static func speaking(role: String, on: bool) -> void:
	if current != null and is_instance_valid(current):
		current.set_speaking(role, on)


static func music(id: String) -> void:
	if current != null and is_instance_valid(current):
		current.play_music(id)


static func music_off() -> void:
	if current != null and is_instance_valid(current):
		current.stop_music()


## Fires a cue from anywhere: silent if nothing is running or the id is unknown.
static func cue(id: String) -> void:
	if current != null and is_instance_valid(current):
		current.play(id)


## Plays a sound. Returns true only if a sound was actually started (false for an unknown id, a muted game or a silent volume).
func play(id: String) -> bool:
	requested.append(id)
	if requested.size() > HISTORY:
		requested.pop_front()
	if not sounds.has(id) or prefs.audio_muted or _voices.is_empty() or not is_inside_tree():
		return false
	var entry: Dictionary = sounds[id]
	if entry["stream"] == null or bus_percent(str(entry["bus"])) <= 0 or prefs.audio_master <= 0:
		return false
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = entry["stream"]
	voice.bus = str(entry["bus"])
	voice.volume_db = float(entry["gain_db"])
	voice.play()
	return true


func has_sound(id: String) -> bool:
	return sounds.has(id)


func sound_ids() -> Array:
	return sounds.keys()


## Which source a sound uses right now: "file" (the audio file exists) or "synth" (the built sound).
func source_of(id: String) -> String:
	return str(sounds.get(id, {}).get("source", ""))


func bus_percent(bus_name: String) -> int:
	match bus_name:
		"UI":
			return prefs.audio_ui
		"SFX":
			return prefs.audio_sfx
		"Music":
			return prefs.audio_music
		"Crowd":
			return prefs.audio_crowd
		"Ambience":
			return prefs.audio_ambience
		"Commentary":
			return prefs.audio_commentary
		"Announcer":
			return prefs.audio_announcer
	return 100


# --- loops, ambience, music and ducking (M6) ---------------------------------------------------------------------------------

## One step of time: the ducking offset moves, the buses follow it and every loop fades towards its target.
func advance(delta: float) -> void:
	ducking.advance(delta)
	_apply_ducking()
	advance_loops(delta)


## A voice starts or stops speaking (role: play_by_play, color, narrative or announcer); the background buses duck while any voice does.
func set_speaking(role: String, on: bool) -> void:
	ducking.set_speaking(role, on)


## The bus volume in dB the player's setting asks for, plus the ducking now applied to it (tests and the buses read the same number).
func effective_bus_db(bus_name: String) -> float:
	var base := _db(bus_percent(bus_name))
	return -80.0 if base <= -80.0 else base + ducking.offset_for(bus_name)


func _apply_ducking() -> void:
	for bus_name in FcDuckingModel.DUCKED_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, effective_bus_db(bus_name))


## Starts a looping sound (`id` must be a "loop": true sound) fading in from silence over `seconds`. Returns false for an unknown or non-looping id.
## Safe when nothing can be heard: the level still moves, so a muted or deviceless run behaves the same.
func play_loop(id: String, seconds: float = FADE_SECONDS) -> bool:
	if not sounds.has(id) or not bool(sounds[id].get("loop", false)):
		return false
	if not _loops.has(id):
		_loops[id] = {"player": null, "level": 0.0, "target": 1.0, "rate": 1.0 / maxf(seconds, 0.05)}
	fade_loop(id, 1.0, seconds)
	return true


## Moves a running loop to `target` (0 to 1) over `seconds`; a loop faded to 0 stops.
func fade_loop(id: String, target: float, seconds: float = FADE_SECONDS) -> void:
	if not _loops.has(id):
		return
	_loops[id]["target"] = clampf(target, 0.0, 1.0)
	_loops[id]["rate"] = 1.0 / maxf(seconds, 0.05)


func loop_level(id: String) -> float:
	return float(_loops[id]["level"]) if _loops.has(id) else 0.0


func loop_target(id: String) -> float:
	return float(_loops[id]["target"]) if _loops.has(id) else 0.0


## The loops that are running or fading (level or target above silence).
func active_loops() -> Array[String]:
	var out: Array[String] = []
	for id in _loops:
		if float(_loops[id]["level"]) > SILENT or float(_loops[id]["target"]) > SILENT:
			out.append(str(id))
	return out


func advance_loops(delta: float) -> void:
	for id in _loops:
		var loop: Dictionary = _loops[id]
		var level := float(loop["level"])
		var target := float(loop["target"])
		var step := float(loop["rate"]) * maxf(delta, 0.0)
		level = minf(target, level + step) if level < target else maxf(target, level - step)
		loop["level"] = level
		var player = loop["player"]
		if level <= SILENT and target <= SILENT:
			if player != null and is_instance_valid(player) and (player as AudioStreamPlayer).playing:
				(player as AudioStreamPlayer).stop()
			continue
		if player == null and is_inside_tree() and not prefs.audio_muted:
			var p := AudioStreamPlayer.new()
			add_child(p)
			p.stream = sounds[id]["stream"]
			p.bus = str(sounds[id]["bus"])
			loop["player"] = p
			player = p
		if player != null and is_instance_valid(player):
			var p2 := player as AudioStreamPlayer
			p2.volume_db = float(sounds[id]["gain_db"]) + (linear_to_db(level) if level > SILENT else -80.0)
			if not p2.playing and level > SILENT:
				p2.play()


## The weights of the three ambience beds for a crowd intensity 0 to 1: quiet is all `low`, medium is all `mid`, loud is all `high`, and
## between them two beds crossfade. The weights always add up to 1.
static func ambience_weights(level: float) -> Dictionary:
	var l := clampf(level, 0.0, 1.0)
	return {"ambience_low": clampf(1.0 - 2.0 * l, 0.0, 1.0), "ambience_mid": 1.0 - absf(2.0 * l - 1.0), "ambience_high": clampf(2.0 * l - 1.0, 0.0, 1.0)}


## Sets the arena ambience to a crowd intensity (see FcAmbienceModel): the beds start if they are not running and crossfade to the new mix.
func set_ambience_level(level: float, seconds: float = FADE_SECONDS) -> void:
	var weights := ambience_weights(level)
	for id in AMBIENCE_IDS:
		if not _loops.has(id) and float(weights[id]) > SILENT:
			play_loop(id, seconds)
		fade_loop(id, float(weights[id]), seconds)


func stop_ambience(seconds: float = FADE_SECONDS) -> void:
	for id in AMBIENCE_IDS:
		fade_loop(id, 0.0, seconds)


## Plays a music pad (a "loop": true sound on the Music bus), fading any other music out. Music is original and synthesised (decision D4).
func play_music(id: String, seconds: float = FADE_SECONDS) -> bool:
	if not sounds.has(id) or str(sounds[id]["bus"]) != "Music" or not bool(sounds[id].get("loop", false)):
		return false
	for other in _loops:
		if str(sounds.get(other, {}).get("bus", "")) == "Music" and other != id:
			fade_loop(other, 0.0, seconds)
	return play_loop(id, seconds)


func stop_music(seconds: float = FADE_SECONDS) -> void:
	for id in _loops:
		if str(sounds.get(id, {}).get("bus", "")) == "Music":
			fade_loop(id, 0.0, seconds)


## A short vibration on phones for big moments (a rare pull, a reward); never on a desktop and never when the player turned it off.
func haptic(milliseconds: int = 30) -> void:
	if prefs.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


# --- buses and settings ------------------------------------------------------------------------------------------------------------

## Makes sure the UI, SFX and Music buses exist and feed the Master bus (safe to call again).
func setup_buses() -> void:
	for bus_name in buses:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


## Pushes the player's volumes and mute onto the buses (call after changing a setting).
func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, _db(prefs.audio_master))
	AudioServer.set_bus_mute(0, prefs.audio_muted)
	for bus_name in buses:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, _db(bus_percent(bus_name)))


static func _db(percent: int) -> float:
	return -80.0 if percent <= 0 else linear_to_db(clampf(percent / 100.0, 0.0, 1.0))


# --- the sound map -----------------------------------------------------------------------------------------------------------------

func _load_map(map_path: String) -> void:
	if not FileAccess.file_exists(map_path):
		return   # no map: no sound, never an error
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	if not (parsed is Dictionary):
		return   # no map: no sound, never an error
	buses = (parsed as Dictionary).get("buses", ["UI", "SFX", "Music"]).duplicate()
	for id in (parsed as Dictionary).get("sounds", {}):
		var def: Dictionary = parsed["sounds"][id]
		var stream: AudioStream = null
		var source := "synth"
		var file := str(def.get("file", ""))
		if file != "" and ResourceLoader.exists(file):
			stream = load(file) as AudioStream
			source = "file"
		if stream == null and def.has("synth"):
			stream = FcAudioSynth.stream(def["synth"], str(id))
			source = "synth"
		var loops := bool(def.get("loop", false))
		if loops and stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.data.size() / 2.0)   # 16-bit mono: two bytes a sample
		sounds[str(id)] = {"bus": str(def.get("bus", "SFX")), "gain_db": float(def.get("gain_db", 0.0)), "stream": stream, "source": source, "loop": loops}
