class_name FcVersion
extends RefCounted
## Version numbers used by saves.

## Human-facing game version (shown in save slot info).
const GAME_VERSION := "0.1.0"

## Version of the save DATA layout. Increase it whenever saved data changes
## shape in a way old code cannot read, AND add a migration step for the old
## version in FcSaveMigrator. Never change a released version's meaning.
const DATA_VERSION := 5

## Version of a Dynasty Mode profile file (user://dynasty). Separate from DATA_VERSION: a Dynasty profile is its own
## file with its own migrator (FcDynastyMigrator), so changing it never touches Owner or Career saves.
const DYNASTY_DATA_VERSION := 4
