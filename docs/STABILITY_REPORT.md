# Stability report: Owner Mode foundation (2026-11-18)

Written after every run below had finished; every number is from an actual run on the commit named. Nothing here is a forecast. Commit under test: `805b22d` (plus this report). Machine: the developer's Windows PC (16 cores); GitHub-hosted runners for CI.

## Follow-up 2026-11-18 (after the founder asked for the open items to be closed with recommended answers)
- **Small-market decision taken (recommended option):** revenue sharing doubled (`revenue_sharing_amount` 120M to 240M), the GM now keeps payroll within 65% of last season's revenue unless the budget is aggressive (before: only once in debt), and the owner sees a plain **distress warning** on the Overview tab (`FcGameController.distress_warning`, tested).
- **Result, same five seeds, same settings (inflation pricing, balanced, normal budget, levers off):**
| Seed | Before: restructurings (written off) / final debt | After: restructurings (written off) / final debt |
|---|---|---|
| 41 | 0 / $148M | 0 / $0 (cash $2.33B) |
| 42 | 4 ($3.67B) / $1.58B | 2 ($2.25B) / $1.04B |
| 43 | 5 ($5.08B) / $1.07B | 2 ($2.61B) / $1.23B |
| 44 | 0 / $0 | 0 / $0 (cash $1.38B) |
| 45 | 1 ($1.46B) / $953M | 1 ($1.04B) / $1.91B |
All five: 0 integrity problems. Restructurings in the three small-market seeds fell from 10 to 5 and the amounts written off from $10.2B to $5.9B, but small-market owners are still rescued once or twice in 50 seasons and end in debt: revenue minus the other costs leaves little room once interest on a large debt (6%) compounds. This is better, not solved; further options are lower interest, a payroll floor relief for small markets, or a larger revenue pool. Needs the founder's judgment.
- **64-team economy rerun** with the final economy (seed 5, 2,622 s): passes. Debt average $332M, largest $2.33B (2.84x the cap), at most 50% of a club's assets; cash largest $1.89B; margin 6.5%; 23 different champions, most by one club 4.
- **Unit suite:** 627 tests passed when this report was written (2026-11-18; dated: the suite has grown since with Career Mode, see `docs/validation/` for the current count). The report's table below was measured at 597 before the Career Mode work.

## Verdict
**Conditional sign-off.** The foundation is stable in the sense the review asked for: tests, CI, long economy runs and the stress scenarios all pass, no run produced an integrity problem, and every defect the new tests found was fixed with a regression test. One finding is **not** resolved and needs a founder decision (section 4): in 3 of 5 seeds an owner who lets the general manager run a small-market club ends up in debt and is restructured several times in 50 seasons, even with sensible settings. The game stays valid and playable (D-029), but that is a balance question, not a bug.

## 1. Tests and checks (this commit)
| Check | Result |
|---|---|
| Unit suite, `tests/run_tests.gd` (local, idle machine) | **597 passed, 0 failed, 403 s** |
| Click test, 67 simulated mouse clicks | 0 problems |
| Simulation check, `simulate_games strict=1` at 1,000 / 3,000 / 6,000 games | 0 of 16 checks outside range each time, exit code 0 |
| CI run on this commit (ubuntu: import, tests, strict sim 1,000 games, 15-season economy check) | success: https://github.com/Novaeris/full-court-godot/actions/runs/44250960781 |
| Long checks workflow (50-season economy at 12 and 30 teams, owner stress) | success: https://github.com/Novaeris/full-court-godot/actions/runs/44252164125 |
| Windows build workflow (export, packaged exe `--selftest`, zip) | success: https://github.com/Novaeris/full-court-godot/actions/runs/44252167951 |

CI history, including a real failure that proved the gate works: the first long-checks run (44230952579) FAILED on the new debt rule of `economy_check` (AI clubs owing up to 12x the cap), which led to the AI fixes below; after the fix it passed.

## 2. What the review asked for, and what was done
1. **auto / reprice mismatch:** fixed. `ui_playthrough` now has explicit `pricing=inflation|suggested` (default inflation = the script never touches the owner's price), `levers=0|1` (the extra lever script, which deliberately includes money-losing settings) and prints a RUN line with every setting. `auto=1` no longer claims anything about prices.
2. **More seeds and a distressed owner:** done (sections 3 and 4). Distress rule implemented (D-036) with 12 tests including a club that never recovers; `tools/owner_stress` runs three fixed strategies.
3. **Documentation:** TESTING, PROGRESS_LOG, ARCHITECTURE, RELEASE, MILESTONE_PLAN and DECISIONS reconciled (the 542-test count, "planned" stress tools, 2.6%/4.0% overtime statements, the Credits note and the "M4 next" recommendation).
4. **CI:** `ci.yml`, `long-checks.yml`, `release.yml` added and verified by real runs. Failure conditions are exit codes (`simulate_games strict=1`, `economy_check`, `run_tests`, `--selftest`).
5. **This report.**

## 3. Defects found by the new checks (all fixed, each with a test)
| Found by | Defect | Fix |
|---|---|---|
| 50-season owner run (earlier) | Owner's ticket price ignored inflation: $251 against $945, $16B debt | Owner price and marketing indexed to inflation |
| `economy_check` DEBT line | Small-market AI clubs spent to the cap whatever they earned: debt up to 12x the cap | AI restructuring rule; clubs in debt sign minimum contracts only and keep payroll within 65% of revenue (largest debt now about 2x the cap, at most 45% of a club's assets) |
| 50-season owner run, seed 41 | A club cut to the hard limit, then refilled its roster with minimum contracts and went back over it | Cuts leave room for the refill; regression test `test_cutting_to_the_hard_limit_...` (fails with the old rule, passes with the new) |
| Parallel runs | Two playthroughs wrote the same save folder; one loaded the other's league and reported false integrity errors | One save folder per process |
| Strict sim check | Turnovers 12.97 against a minimum of 13.0 | `turnover_base` 0.155 to 0.163 (13.7 turnovers); side effect, overtime about 3.7% |

## 4. Owner results, 50 seasons, 12 teams (commit 805b22d, GM runs everything, balanced philosophy)
Operating profit and rescues are kept apart: "written off" is debt that lenders forgave, not profit.
| Run | Seed | Pricing | Levers | Final debt | Final cash | Franchise value | Restructurings (written off) | Problems |
|---|---|---|---|---|---|---|---|---|
| A | 41 | inflation | off | $148M | $0 | $4.80B | 0 | 0 |
| A | 42 | inflation | off | $1.58B | $0 | $2.49B | 4 ($3.67B) | 0 |
| A | 43 | inflation | off | $1.07B | $0 | $2.54B | 5 ($5.08B) | 0 |
| A | 44 | inflation | off | $0 | $3.17B | $5.87B | 0 | 0 |
| A | 45 | inflation | off | $953M | $0 | $3.40B | 1 ($1.46B) | 0 |
| B | 42 | suggested | off | $1.69B | $0 | $2.48B | 1 ($1.17B) | 0 |
| B | 43 | suggested | off | $1.50B | $0 | $2.22B | 5 ($5.36B) | 0 |
| B | 45 | suggested | off | $1.33B | $0 | $2.80B | 1 ($1.19B) | 0 |
| C (default: budgets cycle, levers on) | 42 | inflation | on | $1.05B | $0 | $2.35B | 5 ($4.83B) | 0 |
| C | 43 | inflation | on | $848M | $0 | $2.12B | 5 ($6.43B) | 0 |
| C | 45 | inflation | on | $1.28B | $0 | $3.08B | 2 ($2.95B) | 0 |
Also: a 30-team league (35 teams after expansion, seed 46, 5 franchise moves, run before the last two fixes): 0 problems, debt $0, cash $0.70B, value $6.34B.

**Finding (needs a decision).** Seeds 42, 43 and 45 are small markets for the owner's club. With the GM held to 65% of revenue while in debt, prices at the suggested level and no money-losing levers, they still lose money in late decades (an earlier 24-season books printout of seed 43: revenue about 1.3-1.7x the cap while payroll sits at the cap, with non-payroll costs near $100M). The AI small-market clubs live in the same squeeze, so the restructuring rule is doing real work there too (AI write-offs are not yet counted in `economy_check`). The league stays valid and the owner keeps control, but "cannot lose" turns into "is rescued every few years" for small markets. Options: (a) accept it as the intended small-market challenge, (b) grow revenue sharing with the cap, (c) lower the effective payroll floor or cap share for small markets, (d) show the owner a distress warning in the UI. I recommend (b) plus (d); changing the economy needs your approval, so nothing was tuned.

## 5. Stress test (`owner_stress`, 40 seasons, 12 teams, seeds 101-103, fixed strategies; local, commit 805b22d)
| Strategy | Restructurings (each seed) | Operating profit over 40 seasons | Final debt | Result |
|---|---|---|---|---|
| careful (GM normal budget, price follows suggestion) | 0, 0, 0 | $1.7B, $3.8B, $0.5B | $0 | profitable, cash piles up |
| naive (aggressive budget, price never touched, builds every season) | 0, 0, 0 | $2.3B, $5.5B, $1.0B | $0 | profitable |
| reckless (borrows to the limit, cheap tickets, 10 promotion nights, no marketing) | 6, 4, 6 | -$4.2B, -$3.8B, -$4.3B | $0.8-1.0B | restructured repeatedly, league valid, owner in control |
All 9 runs exit 0 (valid league, no negative money). The CI copy of this test (30 seasons, seeds 101 and 102) also passed.

## 6. AI-only economy, 50 seasons (`economy_check`, local, after the AI debt fix)
| Teams | Seed | Time | Debt (average / largest) | Highest debt share of assets | Cash (largest) | Margin (average) | Titles: champions / most by one club |
|---|---|---|---|---|---|---|---|
| 12 | 5 | 255 s | $167M / $732M | 43% | $1.75B | 7.1% | 12 / 8 |
| 12 | 6 | 259 s | $116M / $675M | 21% | $1.87B | 6.0% | 10 / 11 |
| 12 | 7 | 258 s | $102M / $1.20B | 33% | $2.10B | 6.5% | 12 / 9 |
| 30 | 5 | 1,496 s | $324M / $1.65B | 45% | $1.87B | 7.3% | 19 / 6 |
| 30 | 6 | 1,458 s | $137M / $1.23B | 36% | $1.63B | 4.8% | 25 / 4 |
All five pass the checks. The 64-team league was last run (2,403 s) BEFORE the debt measure and the AI debt rule existed; it was not rerun, so its debt behavior is unverified.
**Parity:** in 12-team leagues the most titles won by one club in 50 seasons were 8, 11, 9 (and 7 to 13 in four other runs earlier); in 30-team leagues 6 and 4. That is concentrated for 12 teams (random chance would give roughly 7-9), so it is recorded and not tuned.

## 7. Known risks and not done
- Small-market owners and AI clubs rely on restructuring (section 4). Decision needed.
- Small-market owners still need one or two rescues in 50 seasons (follow-up above).
- Games are a bit too close (decided by 5 or fewer: 26% against 20-24% real) and overtime is about 3.7% (real 5-6%).
- The unit suite needs about 7 minutes locally (CI: about 10-14 minutes). It is not split into parallel jobs.
- Career and Dynasty Modes are draft designs only; the visual redesign was deliberately kept out of this milestone; no release tag was created.
- The long-checks workflow runs only on demand or weekly, so a regression there is caught within a week, not on each push.

## 8. Sign-off checklist
- [x] auto/pricing semantics explicit and documented
- [x] 50-season human-owner runs on 5 seeds (plus a 30-team run) with 0 integrity problems
- [x] Distressed-owner rule, tests, a never-recovers scenario and a stress tool
- [x] Debt, cash, profit and valuation reported separately; restructuring kept out of operating profit
- [x] Multi-seed AI economy at 12 and 30 teams
- [x] Docs reconciled
- [x] CI with exit-code failure conditions, verified green on GitHub
- [x] Small-market finding: recommended option applied (see the follow-up); halved but not eliminated; further tuning is the founder's call
- [x] 64-team rerun (see the follow-up)
