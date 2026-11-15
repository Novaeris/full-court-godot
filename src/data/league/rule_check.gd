class_name FcRuleCheck
extends RefCounted
## Answer to "is this move allowed under the league rules?" with a reason that
## can be shown to the player.

var allowed: bool = true
var reason: String = ""


static func ok() -> FcRuleCheck:
	return FcRuleCheck.new()


static func denied(why: String) -> FcRuleCheck:
	var c := FcRuleCheck.new()
	c.allowed = false
	c.reason = why
	return c
