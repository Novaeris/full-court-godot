# Phase C: team identity (shown again at Checkpoints 2 and 3)

Date 2026-11-21. Screenshots in `phase_c/`: `teams_sheet.png` (all 23 emblems, all 8 shapes, one crest at 16 to 128 px, home/away/alternate uniforms, wordmark, 32 sample teams) and `owner_header_1280x800.png` (the Owner header with the team's crest).

## What exists
- `FcTeamLook` (`src/ui/team/team_look.gd`): the one resolver. Pure, deterministic (FNV-1a of the team key), nothing stored, team data model unchanged. Shape from the hash; emblem from the words of the team's own nickname through `data/ui/team_identity.json` (Falconers get a swooping bird, Stormcallers a bolt, Sentinels a tower), a hash otherwise; colours from `FcTeamBranding` with ink, trim and uniform colours chosen to stay readable (3:1 or better, tested for all 16 league colour schemes). `logo_key` of the form `shape/emblem` overrides the choice (reserved for a later branding editor).
- `FcTeamEmblems`: 8 crest shapes and 23 vector emblems (polygons, lines, arcs; no art files). `FcTeamCrest`: the control plus a static `paint()` so tables, cards and score bugs can draw a crest without a node. Below 32 px a simplified mark; from 40 px the inner trim line; from 64 px the team letters.
- `FcTeamWordmark`: city over nickname lockup and `crest_and_name`. Home/away/alternate uniform colours are in every look (`look.uniforms`) for Phase E to wire into the figure and `FcUniformPreview`.
- `FcLetterhead` now shows the team's crest (its `_crest_text` stand-in is gone; one existing test line changed to match, noted in D-057). The Owner dashboard passes the real team subject.
- Optional mascot identity: deferred as agreed; no art was made.

## Verified
`test_ui_team_identity` (13 tests): determinism, known parts, emblem rules, chosen crest, name splitting, invalid colours, readability for every colour scheme, **every team of a seeded generated league has a different crest**, a league resolves identically twice, every emblem draws at 16/32/64/128, letterhead = the shared crest.

## Reviewed in the screenshots
- Wordmark nickname was clipped ("Falcone"): removed the clip. Letters on the banner shape collided with its notch: moved up for that shape.
- Judgement call to flag: the "wing" and "swoop" emblems are stylised and simple; they read as bird/wing at 48 px and above and as a plain mark below. Left as is; they can be replaced one by one without touching anything else.
