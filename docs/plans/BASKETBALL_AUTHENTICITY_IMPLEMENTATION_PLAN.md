# Basketball authenticity: implementation plan (from the Stage 2 audit)

Inputs: [../audits/BASKETBALL_AUTHENTICITY_AUDIT.md](../audits/BASKETBALL_AUTHENTICITY_AUDIT.md) and [../audits/BASKETBALL_DATA_INTEGRITY_MATRIX.md](../audits/BASKETBALL_DATA_INTEGRITY_MATRIX.md). This is a plan: nothing here is built yet. Constraints: no unnecessary abstraction, no new framework (extend `FcWorld.validate` and `FcContentValidator`), no save change without the safety conditions in section 4, simulation untouched.

## 1. Ownership decision: a jersey number belongs to the franchise tenure, not to `FcPlayer`
Reason (from the code): a number changes with a trade, can be taken or retired by a franchise, and differs between tenures; the code already separates the person (`FcPlayer`), team membership (`FcRoster.player_ids`, the chokepoint of every add and remove) and per-season team history (`world.careers`). Retired numbers are franchise-specific already (`retired_numbers_all` is keyed by team).

**Current assignment** lives beside roster membership: a `number_by_player` map on `FcRoster` (a field on an existing class, not a new class), changed only inside `FcRoster.add/remove` so membership and number can never disagree. **History**: season-level (the team and number of a player's last game of the season) is kept; the audit found that only the user's own mid-season moves can split a season (S2-HIS-1), so tenure-level history is **not** built unless a measurement shows a concrete problem. **Preference** (the existing hashed value, or the Career player's chosen number) is the first choice when assigning, never the source of truth. **Dynasty cards** keep a number as a content field of the card (a content-format change, deferred: cards have no franchise).

Range and convention (D-069): 0 to 99, "no number" stored separately from 0, no "00". Retired numbers block reuse **by that franchise only**.

## 2. Phases
| Phase | Work | Save change | Depends on | Complexity |
|---|---|---|---|---|
| V1 | Validator extensions (no save change): roster minimum, unique abbreviations and arena names per league, a contrast **warning** for team colours (S2-TEAM-1), identity-rule parity between `FcContentValidator` and generation (S2-XMODE-2) | none | none | small |
| V2 | Colour pairing fix at generation so primary and secondary have contrast of at least 3:1. **Changes generated leagues for a given seed**, so golden tests are re-baselined deliberately; existing saves are unaffected | none | V1 | small, but re-baselines tests |
| J1 | The jersey assignment: `number_by_player` on `FcRoster`; assignment at generation, draft, signing, trade, release (remove clears it), expansion and Career join; deterministic conflict rule (preferred number, else the lowest free number in a fixed order, skipping the franchise's retired numbers, never random, never iteration-order dependent); a defined outcome when no number is free; Career number respected, with a plain message if taken or retired; retired-number display numbers become the retiree's real tenure number | **yes** (`DATA_VERSION` bump, migration) | V1; Stage 1 | medium |
| J2 | Validators use J1: unique number per roster, no retired-number reuse inside a franchise, number range; a whole-league test | none | J1 | small |
| H1 | Decide tenure-level history from measurement (how often a user move splits a season); otherwise document "last team" as a limit | none unless needed | J1 | small |
| P1 | Presentation uses real numbers: lineup intros, lower thirds, uniforms (broadcast milestones). Until J1 exists the number slot is hidden for league players; the hashed value is never shown as a player's number | none | J1 | per broadcast milestone |

J1 is mandatory before the 3D uniforms (B4) if 3D proceeds; in the 2D-only path it runs only if the owner of the project wants numbers on league players.

## 3. Shared architecture (what is reused)
`FcRoster` (membership chokepoint), `FcWorld.validate` (already runs on save, load and in the app), `FcSaveMigrator` and `FcVersion.DATA_VERSION`, `FcFranchiseHistory.retired_numbers_all` (re-derived from real numbers), `FcContentValidator` (publishing). No new validation framework. Hooks: generation (assign), roster transactions (the `FcRoster` methods), save and load (existing `validate` call), season rollover (the existing validation in the stress tools), Studio publishing (`FcContentValidator`), tests.

## 4. Migration (J1 only) and the conditions that must all hold
1. Affected formats and consumers listed: the saved roster, `FcFranchiseHistory` (reads numbers), the Career profile, the Owner history screens.
2. Representative pre-migration saves kept as fixtures; a backup file is written by the migration path before rewriting.
3. Deterministic: each player on each roster is seeded with exactly today's value `jersey_for(id)` plus today's collision bump for **retired** numbers, and the remaining collisions are resolved by player id order. Repeating the migration gives the same result.
4. `DATA_VERSION` bumped; old saves load through `FcSaveMigrator`; old version fixtures still load.
5. Tests: a golden snapshot of `retired_numbers_all`, careers, awards and records **before and after** must be equal; repeat-migration identity; every roster unique after migration.
If any of these cannot be shown, J1 is not applied and 3D uniforms ship without league-player numbers.

## 5. Testing strategy
Unit: assignment and conflict rules (preferred taken, retired, none free), `FcRoster.add/remove` keep membership and numbers consistent, the Career join, whole-league validation over fixed seeds (20 leagues as in `tools/audit_identity.ps1`), migration tests above. Live: a roster screen and a lineup screen show the same number for the same player. Regression: the 13.3% collision measurement must become 0.0% by construction. Simulation untouched, so `simulate_games strict=1` must stay at 0 of 16 checks out of range.

## 6. Acceptance criteria
- Number assignment: 0 collisions per roster across 20 seeded leagues and after a played season; 0 retired-number reuse inside a franchise.
- Cross-surface: the same player shows the same number on every surface that shows one, in Owner and Career.
- Migration: all five conditions in section 4 hold, with the golden comparison equal.
- Validators: the new checks pass on generated leagues and fail on hand-broken fixtures.
- No simulation change; all suites and GitHub Actions green.

## 7. Risks
Re-baselining generation golden tests (V2); a migration that disagrees with the existing retired numbers (mitigated by the golden snapshot); scope creep into a uniforms data model (not planned: alternate kits and accessories stay design options).
