# Reconstruction timing: the 19.5% finding and what depends on it (Broadcast pass 2, M2)

Question from the founder review: investigate the reported 19.5% reconstruction timing issue and document its impact on dependent systems.

## What was measured (re-run 2026-11-23, `tools/reconstruct_spike.ps1`, 40 games, seeds 7000-7039)
Identical to the B1 report: 17,102 events, 28,374 keyframes, validator problems 0, repeated builds identical 40 of 40, reconstruction axis 982 s against a game clock of 2,888 s, step length median 0.60 s, p95 3.39 s, max 3.71 s.

**5,514 of 28,213 steps (19.5%) are "clock-compressed"**: the movement needs more time (at 22 ft/s for players, 45 ft/s for the ball) than the recorded game clock allowed plus one second.

| Step kind | Steps | Compressed |
|---|---|---|
| rebound | 3,614 | 3,175 (87.9%) |
| dead (whistle, substitution, period boundary) | 3,429 | 1,284 (37.4%) |
| loose (steal, team rebound) | 1,346 | 437 (32.5%) |
| hold | 9,653 | 618 (6.4%) |
| shot made, shot missed, shot blocked, free-throw shot, pass | 10,171 | 0 (0%) |

## Cause
The simulator has no spatial model. After a defensive rebound or a steal the other team's possession starts at once, and the illustrative formations put it at the other end of the court (60-80 ft). The recorded clock often allows less time than that distance needs at the speed limits. This is a property of the data, not a bug in the reconstructor: the validator confirms nobody exceeds the limits, so the reconstruction stretches its own time axis instead.

## Impact on dependent systems and the decision for each
| System | Impact | Decision (implemented or planned) |
|---|---|---|
| **Shot clock** (M2, `FcShotClockModel`) | A clock taken from the reconstruction axis would run slow after rebounds and steals. | It reads only the **recorded game clock** (drop in seconds since the last possession-ending event), never the reconstruction axis, so compression cannot distort it. It is still an estimate (the possession start is inferred), so it is labelled "SHOT CLOCK ≈", carries confidence `approximate`, is never stated as fact (`FcPresentationEvent.may_state_as_fact`), and is hidden at free throws, boundaries, dead balls and after 24 s. |
| **3D characters** (B4, existing) | Players could appear to run faster than the clock allows if played at game-clock pace. | Speed is capped at the 22 ft/s limit and the reconstruction's own step length (at most 3.7 s) is used as dwell for those events, as planned in B1. |
| **Camera director** (M3) | A slow follow-shot over a compressed step would show a sprint that never happened. | Use a cut or a fast ease on events that follow a rebound, steal or whistle; follow-shots only on hold, pass and shot steps (0-6% compressed). |
| **Replay claims** (M4) | Exact motion cannot be claimed. | Event order, scores, clock readings and every statistic are exact (recorded). Positions and movement between events are approximate and labelled "reconstructed". Replays are references that re-run the reconstruction, never recorded video. |
| **Commentary and graphics** (M2, M6) | Text about speed, distance or who was where would state invented facts. | Commentary and graphics use only SIM_RECORDED and DERIVED_FROM_RECORDED data (`FcPresentationEvent`); nothing about speed or position. |
| **Highlights and importance** (M4) | None: they use recorded events. | No change. |

## Limits that remain
- The compression rate depends on the illustrative formations. Better formations (for example detecting fast breaks) would lower it but would still be invented positions.
- This measurement is on 40 generated games on the development machine; the rate for other leagues or rule sets is not measured.
