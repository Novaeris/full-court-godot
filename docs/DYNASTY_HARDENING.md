# Dynasty technical hardening and test reliability

Status 2026-11-20 (milestone requested by the founder after a repository review; no features, no balance changes). Decision: D-052.
Validation record: `docs/validation/hardening/` (exact commands, exit codes, durations).

## 1. Dynasty save slots: discovery and recovery
**Problem.** `FcDynastyStore.load_slot()` could recover a profile from `<slot>.dyn`, `<slot>.dyn.tmp` or `<slot>.dyn.bak`, but `list_slots()`
only found `.dyn` files and `has_slot()` ignored `.tmp`. A profile that survived a crash only as a temp file or a backup was recoverable by
the store yet invisible to the profile picker, and `create_profile` could pick its slot name for a new profile and overwrite the temp file.

**Fix** (`src/dynasty/dynasty_store.gd`).
- `list_slots()` lists every valid slot name that has a `.dyn`, `.dyn.tmp` or `.dyn.bak` file, each once, sorted. Invalid names and unrelated files are ignored.
- `has_slot()` is true if any of the three exists, so new profiles never take a slot that still has a recoverable file.
- `load_slot()` keeps its order and now documents it: saved file, then temp file (newer than the backup), then backup; the first that passes the checksum, size and format checks wins. If a saved file AND a newer verified temp file both exist, the saved file wins (it is the last fully installed save).
- Discovery only reads the folder: it never deletes, repairs or renames. A slot that is listed but damaged loads as `corrupt` (so the player can see and delete it); verification was not weakened.

## 2. A release must be able to field a legal starting lineup
**Problem.** `FcDynastyCatalog.is_playable()` checked only "13 cards from 13 different players". Thirteen point guards pass that check but cannot fill PG, SG, SF, PF and C.

**Fix.** One pure, deterministic rule in `src/content/dynasty_content_rules.gd` (`match_starters`, `lineup_problem`), shared by:
- `FcDynastyCatalog.is_playable()` / `playable_problem()` / `lineup_problem()`: playable only if there are 13 different players AND the five starters can be matched;
- the publish validator (`FcContentValidator._check_lineup_coverage`): a release with 13 or more different players that cannot field a lineup is rejected before publication, with the same message;
- the automatic lineup (`FcDynastyLineup.recommend`): the greedy pass is kept (so existing lineups do not change); only when it leaves a starter slot empty although a legal five exists, the shared matching repairs it.

Rule: a starter must have the slot's position as primary or secondary; one real player fills at most one slot (several editions count once); the bench and reserve may be anyone, so only the five starters are matched (a maximum bipartite matching with augmenting paths, in candidate order, so the best players are preferred). The message names the positions that cannot be filled, how many players can start at each position, and what to add.

**Why releases below 13 players are still publishable.** A release may legitimately carry little or no Dynasty content (the bundled starter release has 2 cards). Rejecting it would break existing content, so the validator only rejects releases that look meant to be playable (13 or more players) but cannot field a team; the game's catalog refuses to treat any smaller release as playable anyway. Creator Studio gets the rule through the existing shared `src/content` code; no new dependency was added.

## 3. Economy idempotency is enforced centrally
**Problem.** `FcDynastyEconomy.apply()` recorded request ids but did not check them first; only some callers protected themselves.

**Contract** (`src/dynasty/dynasty_economy.gd`, documented on `apply`).
- A non-empty `request_id` that was not seen is applied and remembered, only after it succeeds (a failed request reserves nothing).
- The same id again with the same kind, ref, deltas and cards changes nothing (no balance change, no ledger entry, no counter increment) and returns success with `{"txn": <original entry>, "replayed": true}`. A fresh transaction returns `"replayed": false`.
- The same id with different parameters is refused with the code `request_conflict` (a misleading success would hide a bug).
- If the ledger already trimmed the original entry (it keeps the newest 400), only its id is known, so parameters cannot be compared and the repeat is treated as a replay.
- An empty request id is never remembered or matched.

Callers that do more than move currency check `replayed` and do not repeat their work: rewards (returns `repeated`, grants nothing), convert duplicate, mastery and direct purchase (return `repeated`), and pack opening, game rewards, the starter grant and tournament entry (return `duplicate_request`, which rolls back the session commit). Their own earlier protections (`previous`, `opening_for_request`) still run first, so behaviour is unchanged.

## 4. The test runners no longer let a script error pass silently
**Problem.** Godot aborts a function that raises a runtime script error; a test that hit one skipped its remaining assertions and was still counted as passed.

**Fix.** `tests/support/script_error_logger.gd` is a `Logger` (Godot 4.5+, `OS.add_logger`) that records runtime SCRIPT errors. Both runners clear it before each test and fail the test if it recorded any while the test (setup, body, teardown, and for live tests the time spent awaiting) ran. This uses the engine's own error channel, not parsing of console text. Other rules: a test file that cannot load, or that extends `FcTestCase` but defines no `test_` method, fails; `--dir=` lets the runner be pointed at a fixture folder; `--filter=` and exit codes are unchanged.

**Proof.** `tests/unit/test_runner_detection.gd` starts a second Godot process on `tests/runner_fixtures/*` (deliberately broken tests) and checks the exit codes: script error mid-test, error in setup, error in teardown, error after an `await`, file with no tests, a healthy folder, and an interrupted live run. The fixtures sit outside `tests/unit` and `tests/live` and both normal runners skip `runner_fixtures`, so they cannot turn the real suite red.

**Limitations (stated, not hidden).**
- Only runtime SCRIPT errors are failures. `push_error` calls and engine messages (such as "popup not inside the tree") appear in normal game code paths, are not counted as failures and are not reported individually.
- The unit runner runs synchronously, so a `quit()` inside a test cannot cut the run short (the runner's own final `quit` decides the exit code). The live runner sets exit code 2 if the run stops early (verified).
- An infinite loop, or an `await` that never resumes, is not detected by the runner; the CI job timeout ends it. An engine crash ends the process with a nonzero code by itself.
- A deliberate script error cannot be triggered inside a test in the same process (the runner's logger would count it), which is why the proof uses child processes.

## 5. Result of running the stricter runner on the existing suite
No existing test was hiding a runtime script error (the full suite passed with the new runner). The only script errors found in this period were in tests written during this UI milestone, which the old runner had also reported only as console text.
