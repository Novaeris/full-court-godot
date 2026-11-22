class_name FcOnlineServer
extends RefCounted
## The LOOPBACK server: the whole server-side of the online design running inside the game process, so the rules can be built and tested
## before any network or hosting is chosen (docs/ONLINE_ARCHITECTURE.md). The real server will be this same logic behind a transport.
##
## What it enforces, in this order, for every request envelope {account_id, command, params, request_id, nonce, issued_at, sig}:
##   1. the account exists and the signature matches the account's session key (nothing else about the request is trusted before this);
##   2. issued_at is within `max_skew` seconds of the server clock (an old captured request is refused);
##   3. the nonce was not seen before for this account (a replayed request is refused);
##   4. the account has rate-limit tokens left;
##   5. an already answered request_id returns the SAME answer without doing anything again (idempotency: a retry never double-spends);
##   6. only a whitelisted command runs, against the server-held profile, inside a transaction that is rolled back on failure.
## The profile lives on the server (authoritative): a client can ask for changes but never states a balance, a card or a result. Every
## answer carries a receipt signed with the server key. The clock is injectable (`now` Callable) so tests control time.

const MAX_SKEW := 120
const NONCE_MEMORY := 200
const ANSWER_MEMORY := 200
const RATE_CAPACITY := 20.0
const RATE_REFILL_PER_SECOND := 2.0

## Commands a client may ask for: command -> function name here. Anything else is refused.
const COMMANDS := {"get_profile": "_cmd_get_profile", "buy_pack": "_cmd_buy_pack", "play_quick_game": "_cmd_play_quick_game",
	"claim_goal": "_cmd_claim_goal", "claim_challenge": "_cmd_claim_challenge"}

var catalog: FcDynastyCatalog
var server_key: String = ""
## Returns the current time in whole seconds. Tests replace it.
var now: Callable = func() -> int: return int(Time.get_unix_time_from_system())

var _accounts: Dictionary = {}   # account_id -> FcOnlineAccount
var _profiles: Dictionary = {}   # account_id -> FcDynastyProfile (the authoritative copy)
var _revisions: Dictionary = {}  # account_id -> int (counts every accepted change)
var _nonces: Dictionary = {}     # account_id -> Array of nonces seen (newest last)
var _answers: Dictionary = {}    # account_id -> {request_id: response}
var _answer_order: Dictionary = {}   # account_id -> Array of request ids (oldest first)
var _buckets: Dictionary = {}    # account_id -> {tokens: float, at: int}


func _init(content_catalog: FcDynastyCatalog, key: String = "") -> void:
	catalog = content_catalog
	server_key = key if key != "" else FcOnlineCrypto.new_key()


## Creates an account with a fresh Dynasty profile (granted its starter collection by the normal onboarding). Returns the session the
## client must keep secret: {"account_id", "session_key"}.
func register(display_name: String, team_name: String, abbreviation: String) -> Dictionary:
	var account := FcOnlineAccount.create(display_name, int(now.call()))
	var problems := account.validate()
	if not problems.is_empty():
		return {"ok": false, "message": str(problems[0])}
	var profile := FcDynastyProfile.create(team_name, abbreviation, hash("%s:%d" % [account.account_id, int(now.call())]), catalog.release_id())
	var onboarded := FcDynastyOnboarding.grant_starter(profile, catalog)
	if not onboarded.ok:
		return {"ok": false, "message": onboarded.message}
	FcDynastyLineup.auto_fill(profile, catalog)
	_accounts[account.account_id] = account
	_profiles[account.account_id] = profile
	_revisions[account.account_id] = 0
	return {"ok": true, "account_id": account.account_id, "session_key": account.session_key}


func has_account(account_id: String) -> bool:
	return _accounts.has(account_id)


func profile_of(account_id: String) -> FcDynastyProfile:
	return _profiles.get(account_id)


func revision_of(account_id: String) -> int:
	return int(_revisions.get(account_id, 0))


## Builds a signed request (what a client does). `request_id` is the idempotency key: reuse it to retry the same action safely.
static func make_request(session: Dictionary, command: String, params: Dictionary, request_id: String, nonce: String, issued_at: int) -> Dictionary:
	var env := {"account_id": str(session["account_id"]), "command": command, "params": params.duplicate(true), "request_id": request_id, "nonce": nonce, "issued_at": issued_at}
	env["sig"] = FcOnlineCrypto.sign_dict(str(session["session_key"]), env)
	return env


## Handles one request. Always returns {"ok", "code", "message", "data", "revision", "receipt"} (a receipt only when the request was accepted).
func handle(env: Dictionary) -> Dictionary:
	var account_id := str(env.get("account_id", ""))
	var account: FcOnlineAccount = _accounts.get(account_id)
	if account == null:
		return _refuse("unknown_account", "That account does not exist.")
	if not FcOnlineCrypto.verify_dict(account.session_key, env):
		return _refuse("bad_signature", "The request signature is not valid.")
	var t := int(now.call())
	if absi(t - int(env.get("issued_at", 0))) > MAX_SKEW:
		return _refuse("stale_request", "The request is too old or from the future.")
	var nonce := str(env.get("nonce", ""))
	if nonce == "":
		return _refuse("bad_nonce", "A nonce is required.")
	var seen: Array = _nonces.get(account_id, [])
	if seen.has(nonce):
		return _refuse("replayed", "That request was already received.")
	seen.append(nonce)
	while seen.size() > NONCE_MEMORY:
		seen.pop_front()
	_nonces[account_id] = seen
	var request_id := str(env.get("request_id", ""))
	var kept: Dictionary = _answers.get(account_id, {})
	if request_id != "" and kept.has(request_id):
		var again: Dictionary = (kept[request_id] as Dictionary).duplicate(true)
		again["repeated"] = true
		return again
	if not _take_token(account_id, t):
		return _refuse("rate_limited", "Too many requests: wait a moment.")
	var command := str(env.get("command", ""))
	if not COMMANDS.has(command):
		return _refuse("unknown_command", "That command is not allowed.")
	var profile: FcDynastyProfile = _profiles[account_id]
	var before := profile.to_dict()
	var result: FcDynastyResult = call(COMMANDS[command], profile, env.get("params", {}) if env.get("params") is Dictionary else {}, request_id)
	if result == null or not result.ok:
		_profiles[account_id] = FcDynastyProfile.from_dict(before)   # roll back: a failed command changes nothing
		return _refuse(result.code if result != null else "internal", result.message if result != null else "The command failed.")
	if command != "get_profile":
		_revisions[account_id] = revision_of(account_id) + 1
	var response := {"ok": true, "code": "", "message": "", "data": result.data, "revision": revision_of(account_id)}
	response["receipt"] = _receipt(account_id, request_id, command, response)
	if request_id != "":
		kept[request_id] = response.duplicate(true)
		_answers[account_id] = kept
		var order: Array = _answer_order.get(account_id, [])
		order.append(request_id)
		while order.size() > ANSWER_MEMORY:
			kept.erase(order.pop_front())
		_answer_order[account_id] = order
	return response


## Whether a receipt really came from this server for these facts.
func verify_receipt(receipt: Dictionary) -> bool:
	return FcOnlineCrypto.verify_dict(server_key, receipt)


## Plays a ranked match between two accounts, decided entirely here: rosters are copied from the server-held profiles, the seed comes from
## the matchmaker, the result is simulated, both ladders move by the Elo change, and each side gets a signed receipt. Returns
## {"ok", "message", "record", "result", "changes": {"a", "b"}, "receipts": {account_id: receipt}}.
func play_match(account_a: String, account_b: String, matchmaker: FcOnlineMatchmaker) -> Dictionary:
	if account_a == account_b or not _profiles.has(account_a) or not _profiles.has(account_b):
		return {"ok": false, "message": "Both players must be different, existing accounts."}
	var pa: FcDynastyProfile = _profiles[account_a]
	var pb: FcDynastyProfile = _profiles[account_b]
	for p in [pa, pb]:
		var problems := FcDynastyLineup.problems(p, catalog)
		if not problems.is_empty():
			return {"ok": false, "message": "A lineup is not ready: %s" % problems[0]}
	var issued := matchmaker.next_match(server_key)
	var record := FcOnlineMatch.make(str(issued["match_id"]), account_a, pa, account_b, pb, int(issued["seed"]))
	var result := FcOnlineMatch.result_of(catalog, record)
	var changes := FcOnlineMatch.rating_changes(int(pa.ladder["rating"]), int(pb.ladder["rating"]), result["winner"] == "a")
	var receipts := {}
	for side in [["a", account_a, pa], ["b", account_b, pb]]:
		var profile: FcDynastyProfile = side[2]
		var won: bool = result["winner"] == side[0]
		profile.ladder["rating"] = maxi(FcOnlineMatch.RATING_FLOOR, int(profile.ladder["rating"]) + int(changes[side[0]]))
		profile.ladder["peak"] = maxi(int(profile.ladder["peak"]), int(profile.ladder["rating"]))
		profile.ladder["games"] = int(profile.ladder["games"]) + 1
		profile.ladder["wins"] = int(profile.ladder["wins"]) + (1 if won else 0)
		_revisions[side[1]] = revision_of(side[1]) + 1
		receipts[side[1]] = _receipt(side[1], str(record["match_id"]), "ranked_match", {"revision": revision_of(side[1]), "data": {"record": record["match_id"], "result": result, "change": changes[side[0]]}})
	return {"ok": true, "message": "", "record": record, "result": result, "changes": changes, "receipts": receipts}


# --- commands: each runs the normal Dynasty domain service against the server's own profile ----------------------------------

func _cmd_get_profile(profile: FcDynastyProfile, _params: Dictionary, _request_id: String) -> FcDynastyResult:
	return FcDynastyResult.success({"profile": profile.to_dict()})


func _cmd_buy_pack(profile: FcDynastyProfile, params: Dictionary, request_id: String) -> FcDynastyResult:
	var r := FcDynastyPacks.buy_and_open(profile, catalog, str(params.get("pack_id", "")), request_id if request_id != "" else "buy:%d" % (profile.opening_counter + 1))
	if r.ok:
		FcDynastyMarket.collection_changed(profile, catalog)
	return r


func _cmd_play_quick_game(profile: FcDynastyProfile, params: Dictionary, _request_id: String) -> FcDynastyResult:
	var r := FcDynastyPlay.quick_game(profile, catalog, str(params.get("level_id", "even")))
	if r.ok:
		r.data.erase("box")      # the server keeps the heavy play-by-play; the client gets the facts
		r.data.erase("events")
		r.data.erase("cards")
	return r


func _cmd_claim_goal(profile: FcDynastyProfile, params: Dictionary, _request_id: String) -> FcDynastyResult:
	return FcDynastyGoals.claim(profile, catalog, str(params.get("goal_id", "")))


func _cmd_claim_challenge(profile: FcDynastyProfile, params: Dictionary, _request_id: String) -> FcDynastyResult:
	return FcDynastyChallenges.claim(profile, catalog, str(params.get("challenge_id", "")))


# --- helpers -------------------------------------------------------------------------------------------------------------------

func _refuse(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "data": {}, "revision": 0}


func _receipt(account_id: String, request_id: String, command: String, response: Dictionary) -> Dictionary:
	var receipt := {"account_id": account_id, "request_id": request_id, "command": command, "revision": int(response["revision"]),
		"result_hash": FcOnlineCrypto.sha256_hex(FcOnlineCrypto.canonical(response["data"])), "issued_at": int(now.call())}
	receipt["sig"] = FcOnlineCrypto.sign_dict(server_key, receipt)
	return receipt


## A token bucket per account: RATE_CAPACITY at most, refilled RATE_REFILL_PER_SECOND, one token per accepted request.
func _take_token(account_id: String, t: int) -> bool:
	var b: Dictionary = _buckets.get(account_id, {"tokens": RATE_CAPACITY, "at": t})
	var tokens := minf(RATE_CAPACITY, float(b["tokens"]) + float(maxi(0, t - int(b["at"]))) * RATE_REFILL_PER_SECOND)
	if tokens < 1.0:
		_buckets[account_id] = {"tokens": tokens, "at": t}
		return false
	_buckets[account_id] = {"tokens": tokens - 1.0, "at": t}
	return true
