class_name FcContentFeatures
extends RefCounted
## What this build of the game can understand from a content release.
##
## WHY: content (players, cards, packs...) can ship without a new game build, but
## only for things the game's code already knows how to do. A release names the
## features it needs in `requires_features`; any name this list does not contain
## makes the release INCOMPATIBLE (fail closed), so new mechanics still need an
## app update. Add a name here only in the same change that adds the code for it.

## The newest content file format this build can read.
const SCHEMA_VERSION := 1
## The oldest content file format this build can still read.
const MIN_SCHEMA_VERSION := 1

## Folder name inside a release -> kind of definition stored there.
const KIND_FOLDERS := {
	"players": "player",
	"cards": "card",
	"packs": "pack",
	"challenges": "challenge",
	"seasonal": "seasonal",
	"support": "support",
}

## The id field every definition file of a kind must carry.
const ID_FIELDS := {
	"player": "player_id",
	"card": "card_id",
	"pack": "pack_id",
	"challenge": "challenge_id",
	"seasonal": "season_id",
	"support": "support_id",
}

## Feature identifiers the game supports today (documented in docs/ARCHITECTURE.md).
const SUPPORTED := [
	"card_rarity_v1",
	"pack_fixed_v1",
]


static func is_supported(feature: String) -> bool:
	return SUPPORTED.has(feature)
