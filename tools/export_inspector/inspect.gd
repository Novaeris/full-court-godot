extends SceneTree
## Lists the files inside an exported package (.exe with an embedded pack, .pck or .apk) and checks the packaging rules of the release milestone:
## everything the game needs is inside, nothing from the development tree is. Run through tools/inspect_export.ps1.
## Exit code 0 = the package follows the rules.

const REQUIRED := [
	"res://project.binary", "res://data/content_starter/manifest.json", "res://data/definitions/attributes.json", "res://data/dynasty/economy.json",
	"res://data/simulation", "res://data/ui/audio.json", "res://data/career/badges.json", "res://assets/fonts/Inter-Variable.ttf",
	"res://assets/icons/lucide", "res://assets/icons/app_icon.svg", "res://assets/shaders/card_sweep.gdshader",
	"res://assets/fonts/OFL-Inter.txt", "res://assets/fonts/OFL-BarlowCondensed.txt", "res://assets/icons/lucide/LICENSE.txt", "res://src/ui/app.gd", "res://src/dynasty/dynasty_catalog.gd", "res://scenes/main.tscn",
]
## Folders and files that must never ship.
const FORBIDDEN_PREFIXES := ["res://tests/", "res://tools/", "res://docs/", "res://creator_studio/", "res://builds/", "res://.github/", "res://.git/"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: inspect.gd -- <package>")
		quit(2)
		return
	if not ProjectSettings.load_resource_pack(args[0]):
		print("FAIL could not open %s as a Godot package" % args[0])
		quit(1)
		return
	var files: Array[String] = []
	_walk("res://", files)
	# an export stores scripts as "name.gd.remap" and imported assets as "name.ext.import" (the data itself lives under .godot): fold both back to
	# the source name, and ignore the inspector project's own two files
	var cleaned: Array[String] = []
	for f in files:
		if f == "res://inspect.gd" or f == "res://project.godot":
			continue
		cleaned.append(f.trim_suffix(".remap").trim_suffix(".import"))
	files = cleaned
	files.sort()
	var problems: Array[String] = []
	for f in files:
		for bad in FORBIDDEN_PREFIXES:
			if f.begins_with(bad):
				problems.append("must not be packaged: %s" % f)
	for need in REQUIRED:
		var found := false
		for f in files:
			if f == need or f.begins_with(need + "/"):
				found = true
				break
		if not found:
			problems.append("missing: %s" % need)
	var counts := {}
	for f in files:
		var top := f.trim_prefix("res://").get_slice("/", 0)
		counts[top] = int(counts.get(top, 0)) + 1
	print("PACKAGE %s: %d files" % [args[0], files.size()])
	for k in counts:
		print("  %-12s %d" % [k, counts[k]])
	for p in problems:
		print("PROBLEM ", p)
	print("RESULT %s" % ("ok" if problems.is_empty() else "FAILED"))
	quit(0 if problems.is_empty() else 1)


func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir.path_join(n)
		if d.current_is_dir():
			_walk(full, out)
		else:
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
