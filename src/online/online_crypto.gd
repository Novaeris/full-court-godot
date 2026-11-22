class_name FcOnlineCrypto
extends RefCounted
## Signing for the online foundations, built only on Godot's own `Crypto` (no plugin, no new dependency). A signature is an HMAC-SHA256 over
## a CANONICAL text of the data (keys sorted, no spaces), so the same facts always give the same signature on every machine. Used for the
## request signature (client key) and the receipts the server hands back (server key). HMAC proves the sender knows the key and that
## nothing was changed on the way; it is not encryption (the transport, TLS, is a later decision: docs/ONLINE_ARCHITECTURE.md).


## The canonical text of a value: stable key order, so equal data is equal text. Whole numbers are always written as integers: Godot
## reads every JSON number back as a float, so without this a request signed as {"n": 5} would be seen as {"n": 5.0} after a trip over a
## real transport and fail its signature check (docs/STABILIZATION_AUDIT.md S1-ONL-1). Fractions keep their decimal form.
static func canonical(data: Variant) -> String:
	return JSON.stringify(_normalize(data), "", true)


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _normalize(value[k])
		return out
	if value is Array:
		var list: Array = []
		for item in value:
			list.append(_normalize(item))
		return list
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9007199254740992.0:
		return int(value)
	return value


## HMAC-SHA256 of `message` with `key`, as lowercase hex.
static func hmac_hex(key: String, message: String) -> String:
	var crypto := Crypto.new()
	return crypto.hmac_digest(HashingContext.HASH_SHA256, key.to_utf8_buffer(), message.to_utf8_buffer()).hex_encode()


## SHA-256 of text, as lowercase hex (used for result hashes in receipts).
static func sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


## The signature of a dictionary (its "sig" field, if present, is left out so signing is repeatable).
static func sign_dict(key: String, data: Dictionary) -> String:
	var body := data.duplicate(true)
	body.erase("sig")
	return hmac_hex(key, canonical(body))


## Whether `data["sig"]` is the right signature for the rest of the data. Compares in constant time over the whole text.
static func verify_dict(key: String, data: Dictionary) -> bool:
	var given := str(data.get("sig", ""))
	var expected := sign_dict(key, data)
	if given.length() != expected.length():
		return false
	var diff := 0
	for i in expected.length():
		diff |= given.unicode_at(i) ^ expected.unicode_at(i)
	return diff == 0


## A fresh random key as hex (for a new account or session). Uses the operating system's secure random numbers, never FcRng: keys must be
## unpredictable, while FcRng is deterministic on purpose.
static func new_key(bytes: int = 32) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()
