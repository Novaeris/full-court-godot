# Feature matrix (current implementation status)

This is the one place that says what is built. `ROADMAP.md`, `RELEASE_READINESS.md` and the mode plans describe history and intent; if they disagree with this file, this file wins. Update it in the same change as the feature.

- **Last verified:** 2026-11-21, tree of commit `1e80edf` (code unchanged since `5700ac9`). Every test named below passed in that run (unit 1,303, live 125, Studio smoke PASS: totals live in [TESTING.md](TESTING.md)).
- **Status words:** **Built** = implemented and covered by the named automated test(s). **Partial** = some of it is built or it is only checked by tools or by eye; the note says what is missing. **Planned** = not implemented (a design direction only). **n/a** = does not apply to that area, by design.
- A cell with no evidence is never "Built". Tools marked *(not re-run)* are historical results kept in their own reports, not Phase 1 evidence.
- Layout: one table per area instead of one wide grid. **Shared systems** are the simulation, league and UI core the modes reuse (a feature there is available to every mode unless its row says otherwise); then **Owner**, **Career**, **Dynasty** and **Creator Studio** each have their own table, so a feature appears in the area that owns it.

## Shared systems

| Feature | Status | Evidence (test files in `tests/unit` unless noted) |
|---|---|---|
| Seeded RNG, stable ID generation | Built | `test_rng`, `test_id_generator` |
| Data model: attributes, player, team, contract, league, world integrity, dates | Built | `test_attributes`, `test_player`, `test_team`, `test_contract`, `test_league`, `test_world`, `test_repository`, `test_date` |
| Save system: slots, checksums, backups, corruption recovery, migrations | Built | `test_save`, `test_game_state` (Owner and Career share it; Dynasty has its own store, see Dynasty) |
| Procedural generation: names, players, staff, cities, whole leagues (original, no real IP) | Built | `test_generation`, `test_league_generation`, `test_player_variety` |
| League structure and rules: sizes 4-64, conferences, divisions, cap presets, salary rules, playoff formats, 80-game schedule | Built | `test_league_rules`, `test_schedule`, `test_cap_extras` |
| Basketball simulation: possessions, rotations, fatigue, box scores, advanced stats, three era presets | Built | `test_simulation`; `tools/simulate_games.ps1` *(not re-run)* |
| Season engine: calendar, standings and tiebreakers, playoffs, champions, awards, statistics | Built | `test_season`, `test_standings` |
| Offseason: progression, retirement, draft and lottery, free agency, re-signing | Built | `test_offseason`, `test_progression`, `test_draft`, `test_draft_lottery`, `test_free_agent_signing` |
| Injuries and medical staff effects | Built | `test_injuries`, `test_medical`, `test_injury_history` (written for league play; whether Dynasty games use injuries was not checked in Phase 1) |
| Career statistics, archives, records and Hall of Fame | Built | `test_careers`, `test_records` |
| Timeouts, intentional fouling, play types in the simulation | Planned | Documented as not modelled (`ARCHITECTURE.md`) |
| Player identity and portraits (one resolver for every mode) | Built | `test_player_identity`, `test_player_identity_golden`, `test_player_visual_sources`, `live/test_live_player`, `live/test_live_player_hd`, `live/test_live_portrait_bake` |
| Player dossier: stats, history, awards, 18 achievements, relationships, similar players, health (achievements, relationships and health are Owner and Career only; "plays like" works in every mode) | Built | `test_player_dossier`, `test_achievements`, `test_player_relationships`, `test_player_similarity`, `test_injury_history` |
| One post-game screen for all three modes (score, line score, performers, season implications) | Built | `test_post_game` |
| Play-by-play recording and narration (`FcGameEventLog`, `FcPlayByPlay`): every shot, rebound, foul, turnover, free throw, substitution and injury written down without changing the game | Built | `test_game_events`, `test_game_history`. Stored with the box of every watched game in Owner and Career saves (data version 3) and passed through Career and Dynasty results. |
| Game replay screen (`FcReplayScreen`, `FcCourtView`, `FcReplayModel`): court picture, scoreboard, play-by-play feed, play/pause, step, speed, filters, period jump, scrubber; opened from the post-game of Owner, Career and Dynasty games | Built | `test_replay_model`, `live/test_live_replay`; pictures in `docs/validation/ui/replay/`. The court is illustrative (the simulation has no positions). Dynasty replays live in memory until you leave (Phase 2E will keep the last few). |
| Game-day preview (`FcGameDay`): next game, records, ranks, projected starters (the same five the game starts), injuries, and Play this game then summary and replay; from the Owner dashboard and the Career hub, plus a Career recent-games picker with replay | Built | `test_game_day`, `live/test_live_game_day`; picture in `docs/validation/ui/replay/`. Lineups stay with the coaches in Owner Mode by design (D-029); Career asks for a role in its own screen; Dynasty has its own lineup screen. Not in Dynasty (it has no schedule). |
| Box score storage and game history | Partial | Owner and Career keep the owner team's last 20 boxes, with their play-by-play, in the season (`test_news`, `test_game_history`); Dynasty keeps a summary only and its replay lives in memory until you leave; boxes are dropped when a season is archived. No full game history for all games. |
| Design system, component kit, shell and navigation, ratchets | Built | `test_ui_design_system`, `test_ui_kit`, `test_ui_shell`, `test_ui_style_lint`, `test_ui_layout`, `test_ui_motion`, `test_ui_states`, `live/test_live_kit`, `live/test_live_shell`, `live/test_live_motion` |
| Team identity (crests, colours), brand assets, tables, charts | Built | `test_ui_team_identity`, `test_brand_assets`, `test_ui_table`, `test_ui_table_extras`, `live/test_live_table` |
| Audio (synthesized cues, no licensed audio) | Built | `test_audio`, `live/test_live_audio` |
| Accessibility basics (contrast, text size, reduced motion, keyboard reach) | Partial | `test_ui_accessibility`, `live/test_live_screen_matrix`; no screen-reader work, no hardware check |
| Screen matrix and release checks | Built | `test_release_readiness`, `test_release_fixes`, `live/test_live_screen_matrix` ("fits" is tested, "feels right" is a person's judgement) |
| Content publishing: manifest, validator, publisher, loader, fallback, rollback | Built | `test_content_format`, `test_content_publish`, `test_content_loader`, `test_content_link` |
| Cross-mode integrity: shared definitions, positions, ratings, references; mode hand-over | Built | `test_ecosystem_integrity`, `live/test_live_mode_transitions`; findings in [INTEGRATION_AUDIT.md](INTEGRATION_AUDIT.md) |
| Test runner reliability | Built | `test_runner_detection` |

## Owner Mode (PC only)

| Feature | Status | Evidence |
|---|---|---|
| Create a league, choose a team, dashboard with the Owner tabs, tutorial | Built | `test_ui`, `test_ui_owner`, `test_tab_pages`, `test_tutorial`, `test_controller` |
| Business model: pricing, demand, revenue and expense lines, debt, valuation, arena and facility projects, loans, sponsorships | Built | `test_finance` (including its sponsorship contract tests), `test_economy`, `test_ticket_plan` |
| Hiring, firing, staff negotiation, staff chemistry, GM direction and delegation | Built | `test_staff`, `test_staff_chemistry`, `test_staff_negotiation`, `test_delegation` |
| Trades (human and AI), trade desk, pick trading, AI-proposed offers | Built | `test_trades`, `test_trade_desk`, `test_trade_offers`, `test_pick_trades`, `test_ai_reactions` |
| Contract negotiation, re-sign decisions, interactive scouted draft, free agency, offseason window | Built | `test_negotiation`, `test_draft`, `test_free_agent_signing`, `test_controller` |
| Owners meeting, relocation, expansion, lobbying | Built | `test_owners_meeting`, `test_relocation`, `test_expansion` |
| Owner career: reputation, job offers, transfer once a season, up to 50 years | Built | `test_owner_career`; stability results in `STABILITY_REPORT.md` *(not re-run)* |
| Distress events and AI reactions | Built | `test_distress`, `test_ai_reactions` |
| Real-click and long-run playthrough tools | Partial | `tools/owner_stress`, `tools/ui_playthrough`, `tools/click_test` *(not re-run)* |
| Historical franchise records, retired jerseys, team rivalries, league storylines | Planned | Only league records and the Hall of Fame exist (`test_records`) |

## Career Mode (PC only)

| Feature | Status | Evidence |
|---|---|---|
| Create-a-player with build rules, archetypes, validation | Built | `test_career_creator`, `test_career_foundation` |
| Progression, skill points, badges, potential cap, overall | Built | `test_career_progression`, `test_career_overall` |
| Season play inside a league, rewards from real games, save and resume | Built | `test_career_season` |
| Decisions and events, relationships, rival, role, contracts, sponsorships | Built | `test_career_events`, `test_career_relationships`, `test_career_rival`, `test_career_role`, `test_career_contract`, `test_career_sponsor` |
| Career hub and Owner-style dossier | Built | `test_ui_career_hub`, `test_player_dossier` |
| Balance and full-run checks | Partial | `tools/career_balance`, `tools/career_playthrough` *(not re-run)* |
| Career timeline, media and public reputation, wider life decisions, legacy presentation | Planned | Not implemented |
| Online team play | Planned | Not planned for Career; see `CAREER_MULTIPLAYER_READINESS.md` |

## Dynasty Mode (PC and mobile)

| Feature | Status | Evidence |
|---|---|---|
| Profile, ledger, idempotent requests, atomic commit, store recovery and migrations | Built | `test_dynasty_domain`, `test_dynasty_hardening` |
| Content from releases: cards, editions, market, unavailable-card placeholders | Built | `test_dynasty_content`, `test_ecosystem_integrity` |
| Bundled Founding Series (46 cards, 40 original players, challenges, season, tournaments) | Built | `test_dynasty_founding`; the founder's own content is still to come |
| 13-slot lineup, positions, rotation, team overall, simulated games | Built | `test_dynasty_lineup_match` |
| Packs, odds, guarantees, pity, duplicates, shards, mastery | Built | `test_dynasty_packs_economy` |
| Challenges, season points, tournaments, save and reload mid-run | Built | `test_dynasty_progression`, `test_dynasty_founding` |
| Screens: collection, cards, packs and reveal, lineup, bracket | Built | `test_dynasty_ui`, `test_ui_cards`, `test_ui_collection`, `test_ui_packs`, `test_ui_bracket`, `live/test_live_cards`, `live/test_live_collection`, `live/test_live_packs`, `live/test_live_pack_cinematic`, `live/test_live_pack_reveal_production` |
| Mobile touch layouts | Partial | `test_ui_dynasty_mobile`, `live/test_live_dynasty_mobile` check a phone-sized window; no physical device yet (`DEVICE_VALIDATION.md`) |
| Paid features and monetization | Planned | None by design until there is a clear reason |
| More collections, wider card mastery, more seasonal content, competitive rankings, deeper tournaments | Planned | Not implemented |

## Creator Studio

| Feature | Status | Evidence |
|---|---|---|
| Opens against the game's code and data (junctions), drafts, checks, approval-gated publish, two releases, loader reads the newest | Built | `creator_studio/tools/studio_smoke.gd` (13 checks, PASS), `test_content_link`, `test_content_publish` |
| Studio screens and restyle | Partial | Smoke test only; no per-screen tests. Visual review is manual. |
| Remote hosting of releases | Planned | Not built; releases are local and offline |

## Platforms and release

| Item | Status | Evidence |
|---|---|---|
| Windows export and packaged self-test | Partial | `tools/export_windows.ps1`, `FullCourse.exe --headless -- --selftest` *(not re-run; see `RELEASE_READINESS.md`)* |
| Android and iOS export, physical devices | Planned | Android emulator only; `DEVICE_VALIDATION.md` is entirely outstanding |
| Legal review before release | Planned | `LEGAL_CHECKLIST.md` |

## Future phases (design directions, none implemented)

| Phase | Items | Status |
|---|---|---|
| 2 Game presentation | Play-by-play, visual replay, lineup selection before games, full box scores and game history in all modes | Planned |
| 3 Franchise immersion | Retired jerseys, historical franchise records, league storylines, rivalry development, richer histories | Planned |
| 4 Career expansion | Timeline, media and reputation, life decisions, legacy | Planned |
| 5 Dynasty expansion | Collections, mastery, seasons, rankings, tournament depth | Planned |
| 6 Online foundations | Accounts, server-authoritative profiles, persistent collections, matchmaking, security and transactions | Planned |
