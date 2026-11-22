class_name FcAudio
extends Node
## The game's sound, owned by FcApp (not an autoload). Five buses: Master, UI, SFX, Music and Crowd (the game's crowd and arena reactions; Music is empty for now: no music has been
## licensed or made, and nothing unlicensed is ever added, decision D4). Sounds come from data/ui/audio.json: an id, a bus, and where the
## sound comes from, which is the audio file if it exists and otherwise a short sound built by FcAudioSynth. An unknown id, a missing
## file or a muted game is simply silent, so the game is fully playable with the sound off.
## Screens do not hold an FcAudio; they call FcAudio.cue("id"), which does nothing when no audio is running (tests, tools).

const MAP_PATH := "res://data/ui/audio.json"
const VOICES := 8
const HISTORY := 40

## The audio of the running app (set by FcApp), so any screen can fire a cue without a reference.
static var current: FcAudio = null

var prefs: FcPreferences
var sounds: Dictionary = {}   # id -> {bus, gain_db, stream (or null), source "file" or "synth"}
var buses: Array = []
## The ids that were asked for (newest last, capped), whether or not they could be heard: tests and the settings screen read it.
var requested: Array[String] = []
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
	return 100


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
		sounds[str(id)] = {"bus": str(def.get("bus", "SFX")), "gain_db": float(def.get("gain_db", 0.0)), "stream": stream, "source": source}
