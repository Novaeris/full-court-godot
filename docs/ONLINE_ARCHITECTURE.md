# Online architecture (foundations, phase 6)

**Status: foundations built and tested locally. No network code, no backend and no new dependency exists.** The founder answered the open
questions on 2026-11-22 (D-066): Supabase and Resend, WebSocket with TLS, Owner multiplayer (shared league, one host) and Career 5v5/3v3
team play, Dynasty online-first, no trading or real-money purchases yet. Section "Founder answers" at the end lists what is still open. CLAUDE.md rule 7
(no dependencies without approval) is why nothing past the local layer was built.

Online play is a **Dynasty-side track only** (D-030, D-029): Owner and Career stay single-player.

## The idea in one paragraph
The server owns the truth. A client never says "I have 5,000 credits" or "I won 101-98"; it asks the server to do something ("buy this
pack", "play this game", "claim this goal") and the server runs the **same Dynasty domain services the offline game uses**
(`FcDynastyPacks`, `FcDynastyPlay`, `FcDynastyGoals`, `FcDynastyChallenges`) against the profile it holds, then answers with the
result and a signed receipt. Because the rules are the same code, offline and online can never drift apart.

## What is built (all in `src/online/`, pure GDScript, tested in `tests/unit/test_online.gd`)

| Piece | Class | What it does |
|---|---|---|
| Signing | `FcOnlineCrypto` | HMAC-SHA256 over canonical JSON using Godot's own `Crypto`; constant-time compare; secure random keys (never `FcRng`, which is deterministic on purpose). |
| Accounts | `FcOnlineAccount` | Stable `fca_...` id, validated display name, a secret session key. Holds no password, e-mail or personal data. |
| Server rules | `FcOnlineServer` (loopback) | The whole server side running in-process. See the request pipeline below. |
| Matchmaking | `FcOnlineMatchmaker` | Rating-based queue, window widens with waiting time, deterministic pairing, server-issued seeds. |
| Matches | `FcOnlineMatch` | The server copies both rosters, simulates with the server seed, moves both ladder ratings (Elo, equal and opposite) and issues receipts. A client's claimed score is **checked by re-simulating** the same record. |

### Request pipeline (every request, in this order)
1. Account exists and the **signature** matches the account's session key. Nothing else is trusted before this.
2. `issued_at` is within 120 s of the server clock (**stale/future requests refused**).
3. The **nonce** was not seen before for this account (**replay refused**).
4. Per-account **rate limit** (token bucket: 20 burst, 2 per second).
5. An already answered `request_id` returns the **same answer** and does nothing again (**idempotency**: a retry never double-spends).
6. Only a **whitelisted command** runs (`get_profile`, `buy_pack`, `play_quick_game`, `claim_goal`, `claim_challenge`), inside a transaction that is **rolled back** if it fails.
7. The answer carries a **receipt** signed with the server key: account, request id, command, revision, hash of the result.

### Persistent collections
The server-held `FcDynastyProfile` is the persistent collection. It already serialises (`to_dict` / `from_dict`) and is versioned
(`FcVersion.DYNASTY_DATA_VERSION` + `FcDynastyMigrator`), so a database only has to store that document per account plus a revision
counter. Nothing in the profile format had to change for online.

### Why re-simulation is the anti-cheat
Dynasty games are deterministic from rosters + seed (`FcDynastyMatch.simulate`). For a head-to-head match the server issues the seed, so a
cheating client cannot pick a lucky one, and any result a client reports can be recomputed and compared (`FcOnlineMatch.verify_claim`).
The play-by-play recorder never touches the random generator (tested), so recording does not change results.

## Security properties and their limits (honest list)
- **Proven by tests:** tampered, replayed (including after 200+ newer requests, see the stabilization review below), stale, mis-signed and unknown-command requests are refused; a failed command changes nothing;
  receipts cannot be edited; two accounts cannot touch each other's data; the rate limit holds and refills.
- **Not solved here (needs the real deployment):** transport security (TLS), how the session key reaches the client and is stored, sign-in
  (who a person is), account recovery, abuse reporting, real-money payment verification, server-side secrets storage, DDoS protection,
  clock trust across machines, and any legal/privacy requirements (age rules, data deletion). These are deliberately not guessed at.
- The signature key is symmetric (HMAC): a client that steals its own key can only act as itself. A later move to asymmetric device keys is possible without changing the pipeline.

## Decisions needed from the founder (nothing below is started)
1. **Backend technology and hosting.** Options: (a) a small Godot headless server (same code, easiest, you operate it); (b) a managed backend
   service with a database; (c) a custom service in another language. Recommendation: (a) for the first online release, because the rules are
   already GDScript, then revisit. This also decides the cost of running it.
2. **Sign-in provider** (platform accounts, e-mail, or a third-party login).
3. **Transport** (WebSocket/HTTPS via Godot's built-in networking is the default recommendation: no new dependency).
4. **Which online features ship first.** Recommendation: server-held collection + ranked head-to-head; trading and a real-money store last, and
   only after a lawyer reviews payments and the card-collecting rules (see CLAUDE.md rule 9).

Until these are answered, the right next step is only more local hardening, not network code.

## Founder answers (2026-11-22, D-066) and what is still open
- **Services chosen:** Supabase (accounts, storage, realtime) and Resend (e-mail, usable as Supabase's sign-in SMTP). Godot talks to them with
  its built-in `HTTPRequest`/WebSocket, so no plugin is needed. Transport: WebSocket with TLS.
- **Modes:** Owner and Career stay fully playable offline with an optional online layer; Dynasty is online-first.
  - **Owner multiplayer:** one shared league, each person owns one team, invites, one host who simulates the whole league. This is
    host-authoritative: the host's game decides, so it is for friends' leagues. The server-authoritative design above is for Dynasty and ranked play.
  - **Career online:** a person brings their created player into others' 5v5 and 3v3 games; still the text and box-score simulation, with a
    visual presentation wanted later.
- **Build order:** accounts first, then Owner multiplayer, then Career team play.
- **Still open:** whether the live-match server is a small Godot headless server on a VPS (recommended, about $5 to 15 a month) or something else;
  how a person's offline Owner/Career save becomes a shared league (host uploads or hosts live); what Career 5v5/3v3 lets a person control; the
  privacy and age rules for accounts. Nothing past the local layer is built.

## Answers on 2026-11-22 (D-068)
- Headless Godot server for live matches: accepted for now. Career 5v5/3v3: chosen at queue time, almost no extra gameplay, cosmetics (arm sleeves and the like) later. Owner leagues: hosted live.
- **Built next to these:** `FcOnlineConfig` (URL and public key from `user://online_config.json`, never committed; refuses a service-role key), `FcSupabaseAuth` (pure request builders and answer readers), `FcOnlineSession`, `FcOnlineHttp` (the only code that touches the network).
- **Founder setup needed before sign-in can be tested for real:** create a Supabase project, copy its URL and the public **anon** key (never the service-role key) into `user://online_config.json` as `{"url": "...", "anon_key": "..."}`, and in the Supabase dashboard set Resend as the custom SMTP sender.
- **Still open:** what the live Owner league lobby looks like (invite code or friend list), cosmetics design, and privacy and age rules.

## Stabilization review (2026-11-22)
Status words: **implemented** = code exists; **tested** = a named test covers it; **local-only** = runs inside one process with no transport, storage or deployment.

**Implemented and tested (local-only):** HMAC-SHA256 over a canonical text, constant-time compare, OS secure random for keys (`FcOnlineCrypto`); accounts; the loopback server pipeline (signature, clock window, nonce, rate limit, idempotency, whitelist, rollback, signed receipts); matchmaking by rating with server-issued seeds; server-decided matches checked by re-simulation. Tests: `test_online.gd`, `test_online_auth.gd`, `test_online_controller.gd`, `test_live_online_screen.gd`.

**Defects found and fixed in this review** (details and regression tests in `STABILIZATION_AUDIT.md`): S1-ONL-1 signatures did not survive a JSON round trip (Godot reads all JSON numbers as floats; `canonical` now writes whole numbers as integers); S1-ONL-2 a captured request could be replayed after 200 newer requests pushed its nonce out (nonces are now kept until they are too old to pass the clock window, with a hard cap that refuses rather than forgets); S1-ONL-3 a request id reused for a different command returned the first command's answer (now `request_conflict`); S1-ONL-4 no length limit on nonce and request id (64 characters).

**Limits of the security claims:** HMAC proves the sender holds the key; it is not encryption (TLS is a transport decision). An identical envelope re-sent after a lost answer is refused as replayed, so a client must re-sign with a new nonce and the same request id (idempotency then returns the original answer). `register` is unthrottled and unauthenticated; `play_match` has no concurrency control; session keys sit in memory in plaintext (needed for HMAC).

**Matchmaking and competitive integrity (verified by test and by reading):** duplicate queue entries are rejected, leaving works, the window widens with waiting time, pairing is deterministic (rating, join time, account id), a player cannot be paired with themselves, rosters are copied from the server-held profiles when the match is made, the seed comes from the server key, the result is the authoritative simulation, and both sides get equal and opposite rating changes (except where the floor clamps the loser) and a signed receipt. Not verified (no transport): `join` does not check that the account exists, and nothing was tested under concurrent requests.

**What a restart loses today (everything):** accounts, session keys, server profiles, revisions, nonces, saved answers (idempotency), rate-limit buckets, the matchmaker queue and match counter, match records, receipt history, and the server key itself (so previously issued receipts and match seeds become unverifiable).

**Persistence requirements (for a future store; no provider is chosen):** durable account identity separate from the display name; profile ownership and recovery that does not depend on the session key; atomic profile updates (the whole command in one transaction, rolled back on failure) with a revision checked on write; idempotency records stored with the transaction so a retry after a restart returns the same answer; nonce memory that survives a restart for at least twice the clock window; match history and signed receipts per account; encrypted backups and a tested restore; a stable server key (with rotation) so old receipts verify; match ids that never repeat after a restart; account deletion and data-retention rules (a legal review is needed before a commercial release); per-account serialisation of commands and of matches touching the same account.

**Deployment requirements:** TLS; sign-in through Supabase (D-068) bound to the game account; encrypted storage of session keys; rate limits on registration and sign-in; monitoring and alerts; secrets only in the server environment (the game must never ship a service-role key, enforced by the config guard); a server-time endpoint or clock synchronisation for client clocks outside 120 seconds; a client library that signs every request and re-signs retries.

**Still open (not decided here):** hosting and cost beyond D-068's rented server, the persistence provider and schema, the data-retention policy, which online features ship first, and any real-money feature.
