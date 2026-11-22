class_name FcOnlineConfig
extends RefCounted
## Where the game's online services live (D-066: Supabase for accounts and storage). The URL and the PUBLIC "anon" key are read from
## `user://online_config.json`, which is never part of the repository, so nothing secret or project-specific is committed. The anon key is
## meant to be public (Supabase protects data with row-level rules on the server), but the SERVICE-ROLE key can read and write everything
## and must NEVER be in a game client: `validate()` refuses a config whose key says it is a service-role key.

const FILE := "user://online_config.json"

var url: String = ""
var anon_key: String = ""


static func make(project_url: String, public_key: String) -> FcOnlineConfig:
	var c := FcOnlineConfig.new()
	c.url = project_url.strip_edges().trim_suffix("/")
	c.anon_key = public_key.strip_edges()
	return c


## Reads the config file. Returns null when it is missing or unreadable (online features then stay off and the game plays offline).
static func load_file(path: String = FILE) -> FcOnlineConfig:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return null
	var data: Dictionary = json.data
	return make(str(data.get("url", "")), str(data.get("anon_key", "")))


## Problems with the config (empty = usable): an https address and a public key that is not a service-role key.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if not url.begins_with("https://") or url.length() < 12:
		errors.append("the project url must start with https://")
	if anon_key.is_empty():
		errors.append("the public (anon) key is missing")
	elif is_secret_key(anon_key):
		errors.append("that is a service-role (secret) key: it must never be put in the game. Use the public publishable (anon) key")
	return errors


## Whether a key is one that must never ship in a game: Supabase's new "sb_secret_..." keys and old-style JWTs whose role is service_role.
## The new "sb_publishable_..." keys and old "anon" JWTs are the public ones.
static func is_secret_key(key: String) -> bool:
	return key.begins_with("sb_secret_") or role_of(key) == "service_role"


## The "role" claim inside a Supabase key (a JWT), or "" when it cannot be read.
static func role_of(jwt: String) -> String:
	var parts := jwt.split(".")
	if parts.size() != 3:
		return ""
	var payload := parts[1].replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var parsed = JSON.parse_string(Marshalls.base64_to_raw(payload).get_string_from_utf8())
	return str(parsed.get("role", "")) if parsed is Dictionary else ""
