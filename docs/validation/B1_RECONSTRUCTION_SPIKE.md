# B1: reconstruction feasibility spike

Question (master plan 4.1): can the recorded events, which hold no positions, no pass events and no possession starts, be turned into convincing basketball movement without a second simulation and without pretending the movement is real?

**Verdict: PASS for the headless feasibility.** The reconstruction is valid under an independent validator, repeats byte for byte, never exceeds the speed limits, and explains every recorded event. One caveat is measured below: in about one step in five the reconstruction needs more time than the recorded game clock gave, mostly where possession changes. That is a presentation timing matter (the replay already shows events about a second each, not at game speed), not a failure.

Date 2026-11-22. Code: `src/ui/replay/reconstructor.gd` (`FcReconstructor`), `reconstruction_validator.gd` (`FcReconstructionValidator`). Tests: `tests/unit/test_reconstruction.gd` (6). Measurement: `tools/reconstruct_spike.ps1`.

## What was built
- A pure reconstructor over the broadcast timeline. Output: keyframes `{event, kind, t, players {id: feet}, ball (x, y, z), holder}` labelled `reconstructed = true`. No random numbers, no clock; jitter comes from a hash of the events, the presentation seed is made from the scores, teams and event count (so **no saved data**, option 1 of the plan).
- The ball-interaction model of the plan: `hold`, `pass` (reconstruction-level, inserted only before an assisted basket, from the recorded assister to the shooter), `shot_made`, `shot_missed`, `shot_blocked`, `ft_shot`, `rebound`, `loose` (steal or team rebound), `dead` (whistle, substitution, period boundary).
- Player positions use the existing illustrative formation and shot spots (`FcCourtLayout`) plus bounded jitter and a deterministic separation pass (no two players closer than 1.5 ft).
- A time axis of its own: each step lasts as long as the fastest player or the ball needs at the limits, at least 0.4 s.

## Decisions (D-069 item 12 and 21: values chosen from physics and the sample, written down before the verdict)
| Limit | Value | Basis |
|---|---|---|
| Player speed | 22 ft/s | a sprint, about 7 m/s |
| Ball speed (pass or shot) | 45 ft/s | about 30 mph |
| Minimum spacing | 1.5 ft | bodies do not overlap |
| Minimum step | 0.4 s | readable |

## The independent validator
It recomputes the five-per-side lineups from the play-by-play (`FcPlayByPlay.on_court`) instead of trusting the reconstructor, and checks: labelled reconstructed; every event from the tip-off has a keyframe, in order, time strictly forward; everyone and the ball inside the court; no overlap; no player or ball over the speed limits between keyframes (no unexplained discontinuity); a ball with a holder is in his hands, a ball in flight has none; a change of holder only at a pass, rebound, steal or possession start; each event ends in the interaction it calls for (an assist is a pass from the assister to the shooter, a rebound is held by the recorded rebounder, a steal ends with the thief). Each rule is proved able to fail by `test_the_validator_catches_each_kind_of_break` (13 deliberate breaks).
**The validator found a real bug in its first run** (players substituted out stayed placed, giving 11 on court). It was fixed in the reconstructor.

## Measurements (40 games, seeds 7000-7039, 17,102 events, 28,374 keyframes)
- Validator problems: **0**. Repeated builds identical: **40 of 40**.
- Reconstruction time per game 982 s on its own axis (the game clock is 2,888 s); step length median 0.60 s, p95 3.39 s, max 3.71 s.
- **Clock-compressed steps** (the reconstruction needs more than the game clock allowed plus one second): 5,514 of 28,213 (19.5%). By interaction: rebound 87.9% (3,175 of 3,614), dead 37.4%, loose 32.5%, hold 6.4%; shots, passes and free throws 0%.
- Reading: a defensive rebound or a steal is followed at once by the other team's possession, which the illustrative formations put at the other end of the court (60 to 80 ft), so the players need a few seconds to get there.

## Limits to keep stating
- Everything is presentation. Positions between events are invented, from event kinds, not tracked play; a fast break is not distinguished; there is no off-ball movement, screens or pick-and-roll; passes exist only to explain assists.
- The 19.5% compression means a viewer that plays the reconstruction at the game clock would have players run faster than the clock allows after rebounds and steals. The planned handling (B4, B6): use the reconstruction's own step length as the dwell for those events (it is at most 3.7 s) rather than the fixed dwell of 0.6 to 1.6 s.

## Gate result for the 3D decision
B1 passes. B1b (3D rendering performance) and B1c (player models) are still open, so the overall 3D decision is not yet made.
