class_name FcBookmarkStore
extends RefCounted
## The person's replay bookmarks (Broadcast pass 2, M4, D-071), kept in a small local file of their own (user://replay_bookmarks.json), apart from
## saved games exactly like FcPreferences: they belong to the person, not to a playthrough, and no league, career or dynasty save changes.
## Format {"version": 1, "games": {game_key: [event index, ...]}}. Reading never fails (a missing or damaged file is an empty store). A game keeps
## at most MAX_PER_GAME bookmarks and the store at most MAX_GAMES games (the oldest game is dropped first), so the file cannot grow without limit.
## Indices are positions in a game's replay model; the game key (FcReplayModel.game_key) ties them to the right game.

const DEFAULT_PATH := "user://replay_bookmarks.json"
const VERSION := 1
const MAX_PER_GAME := 20
const MAX_GAMES := 200

var path: String
var _games: Dictionary = {}   # game key -> Array[int], insertion order = age


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	load_file()


func load_file() -> void:
	_games = {}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or int((parsed as Dictionary).get("version", 0)) != VERSION or not ((parsed as Dictionary).get("games") is Dictionary):
		return
	for key in (parsed["games"] as Dictionary):
		var list = parsed["games"][key]
		if not (list is Array):
			continue
		var clean: Array = []
		for v in list:
			if (v is float or v is int) and int(v) >= 0 and not clean.has(int(v)):
				clean.append(int(v))
		clean.sort()
		if not clean.is_empty():
			_games[str(key)] = clean.slice(0, MAX_PER_GAME)


func save_file() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "games": _games}))
	return true


## The bookmarked event indices of a game, ascending.
func indices(game_key: String) -> Array:
	return (_games.get(game_key, []) as Array).duplicate()


func has_bookmark(game_key: String, index: int) -> bool:
	return (_games.get(game_key, []) as Array).has(index)


## Adds a bookmark. Returns false when it already exists or the game is at its limit.
func add(game_key: String, index: int) -> bool:
	if game_key == "" or index < 0 or has_bookmark(game_key, index):
		return false
	if not _games.has(game_key):
		_games[game_key] = []
		while _games.size() > MAX_GAMES:
			_games.erase(_games.keys()[0])   # the oldest game goes
	var list: Array = _games[game_key]
	if list.size() >= MAX_PER_GAME:
		return false
	list.append(index)
	list.sort()
	save_file()
	return true


func remove(game_key: String, index: int) -> bool:
	if not has_bookmark(game_key, index):
		return false
	(_games[game_key] as Array).erase(index)
	if (_games[game_key] as Array).is_empty():
		_games.erase(game_key)
	save_file()
	return true


## Adds the bookmark when it is not there and removes it when it is. Returns true when the play is bookmarked afterwards.
func toggle(game_key: String, index: int) -> bool:
	if has_bookmark(game_key, index):
		remove(game_key, index)
		return false
	return add(game_key, index)


func game_count() -> int:
	return _games.size()
