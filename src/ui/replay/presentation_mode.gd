class_name FcPresentationMode
extends RefCounted
## The three presentation experiences of the replay screen and the HUD levels (Broadcast pass 2, M1). Pure data and rules; the screen
## only applies what is returned here, so what each mode shows is decided (and unit tested) in one place.
##
## BROADCAST  immersion: the 3D court fills the screen, the director drives the camera, only the scoreboard, graphics and captions show.
## REPLAY     reviewing plays: scrubber with key plays, periods, speed, highlights, instant replay, the feed, a contextual camera panel.
## ANALYSIS   information and tactics: top-down tactical view, free camera, the feed, rosters, lineups and the team comparison.

const BROADCAST := "broadcast"
const REPLAY := "replay"
const ANALYSIS := "analysis"
const MODES := [[BROADCAST, "Broadcast"], [REPLAY, "Replay"], [ANALYSIS, "Analysis"]]
const DEFAULT_MODE := REPLAY

const HUD_FULL := "full"
const HUD_MINIMAL := "minimal"
const HUD_HIDDEN := "hidden"
const HUD_LEVELS := [[HUD_FULL, "HUD: full"], [HUD_MINIMAL, "HUD: minimal"], [HUD_HIDDEN, "HUD: hidden"]]
const DEFAULT_HUD := HUD_FULL

## HUD elements drawn over or around the stage.
const E_SCOREBUG := "scorebug"
const E_OVERLAY := "overlay"
const E_BADGE := "badge"
const E_CAPTIONS := "captions"   # the sentence, the sound caption and the commentary line
const E_TRANSPORT := "transport"   # the play controls row, periods and scrubber

## Panels of the screen.
const P_FEED := "feed"
const P_CAMERA := "camera"
const P_ROSTERS := "rosters"
const P_LINEUPS := "lineups"
const P_TEAMS := "teams"
const P_HIGHLIGHTS := "highlights"
const P_PERIODS := "periods"
const P_SCRUBBER := "scrubber"
const P_SPEED := "speed"
const P_JUMPS := "jumps"   # Start and End buttons
const TRANSPORT_PANELS := [P_HIGHLIGHTS, P_PERIODS, P_SCRUBBER, P_SPEED, P_JUMPS]


static func is_mode(id: String) -> bool:
	return id in [BROADCAST, REPLAY, ANALYSIS]


static func is_hud(id: String) -> bool:
	return id in [HUD_FULL, HUD_MINIMAL, HUD_HIDDEN]


## What a mode wants: the default camera and view, and the panels it shows (a Dictionary of panel id -> bool).
## `view` is "3d" (the 3D court when it can be built) or "flat" (the top-down tactical court). The caller falls back when 3D is missing.
static func layout(mode: String) -> Dictionary:
	match mode:
		BROADCAST:
			return {"camera": "auto", "view": "3d", "panels": {P_FEED: false, P_CAMERA: false, P_ROSTERS: false, P_LINEUPS: false, P_TEAMS: false,
					P_HIGHLIGHTS: false, P_PERIODS: false, P_SCRUBBER: false, P_SPEED: true, P_JUMPS: false}}
		ANALYSIS:
			return {"camera": "manual", "view": "flat", "panels": {P_FEED: true, P_CAMERA: true, P_ROSTERS: true, P_LINEUPS: true, P_TEAMS: true,
					P_HIGHLIGHTS: false, P_PERIODS: true, P_SCRUBBER: true, P_SPEED: true, P_JUMPS: true}}
		_:
			return {"camera": "hybrid", "view": "3d", "panels": {P_FEED: true, P_CAMERA: true, P_ROSTERS: false, P_LINEUPS: false, P_TEAMS: false,
					P_HIGHLIGHTS: true, P_PERIODS: true, P_SCRUBBER: true, P_SPEED: true, P_JUMPS: true}}


## Whether a HUD element is shown at a level. Hidden removes everything drawn over the court (the transport stays reachable by keys);
## Minimal keeps the scoreboard, the graphic strip and the replay badge; Full adds captions and, outside Broadcast, the transport.
static func hud_shows(level: String, element: String) -> bool:
	match level:
		HUD_HIDDEN:
			return false
		HUD_MINIMAL:
			return element in [E_SCOREBUG, E_OVERLAY, E_BADGE]
		_:
			return true


## Whether `panel` is visible for a mode at a HUD level. A hidden HUD hides every panel too (a clean picture).
static func panel_visible(mode: String, level: String, panel: String) -> bool:
	if level == HUD_HIDDEN:
		return false
	if level != HUD_FULL and panel in TRANSPORT_PANELS:
		return false   # the minimal HUD has no play controls over the picture (keys still work)
	return bool(layout(mode)["panels"].get(panel, false))


## The next HUD level when the player presses the HUD key (full, minimal, hidden, full ...).
static func next_hud(level: String) -> String:
	return {HUD_FULL: HUD_MINIMAL, HUD_MINIMAL: HUD_HIDDEN}.get(level, HUD_FULL)
