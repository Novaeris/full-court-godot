class_name FcOnlineAccount
extends RefCounted
## An online account as the server knows it: a stable id, a display name and the session key its client signs requests with. The id is
## random-looking but derived only from non-secret inputs; the KEY is the secret (FcOnlineCrypto.new_key, never FcRng). No password,
## e-mail or personal data is modelled here: how a person proves who they are (sign-in provider) is an open decision in
## docs/ONLINE_ARCHITECTURE.md, and the design keeps it out of the game rules.

const NAME_MIN := 3
const NAME_MAX := 20

var account_id: String = ""
var display_name: String = ""
var created_at: int = 0
var session_key: String = ""


static func create(name: String, created_unix: int) -> FcOnlineAccount:
	var a := FcOnlineAccount.new()
	a.display_name = name.strip_edges()
	a.created_at = created_unix
	a.session_key = FcOnlineCrypto.new_key()
	a.account_id = "fca_%s" % FcOnlineCrypto.sha256_hex("%s:%d:%s" % [a.display_name, created_unix, a.session_key]).substr(0, 16)
	return a


## Problems with the account (empty when valid): the name must be 3-20 letters, digits, spaces, dashes or underscores.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if display_name.length() < NAME_MIN or display_name.length() > NAME_MAX:
		errors.append("the display name must be %d to %d characters" % [NAME_MIN, NAME_MAX])
	for i in display_name.length():
		var c := display_name.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 or c == 45 or c == 95
		if not ok:
			errors.append("the display name may only use letters, digits, spaces, dashes and underscores")
			break
	return errors
