class_name FcApproval
extends RefCounted
## The owner's explicit sign-off for ONE release of ONE draft.
##
## WHY: saving, editing and validating must never put content in front of players. A release
## is only written when the publisher receives an approval that (1) names who approved and why,
## (2) is bound to the exact content of the draft (its hash), and (3) has not been used before.
## Creator Studio creates one only when the owner presses the approval button.

var approver: String = ""
var note: String = ""
var draft_hash: String = ""
var _used: bool = false


## Returns null unless the approver and note are filled in (an approval is a deliberate act).
static func grant(approver_name: String, approval_note: String, hash_of_draft: String) -> FcApproval:
	if approver_name.strip_edges().is_empty() or approval_note.strip_edges().is_empty() or hash_of_draft.is_empty():
		return null
	var a := FcApproval.new()
	a.approver = approver_name.strip_edges()
	a.note = approval_note.strip_edges()
	a.draft_hash = hash_of_draft
	return a


func is_used() -> bool:
	return _used


## True only for the draft content this approval was given for, and only once.
func covers(hash_of_draft: String) -> bool:
	return not _used and not draft_hash.is_empty() and draft_hash == hash_of_draft


## Called by FcPublisher after the release is stored. An approval never publishes twice.
func consume() -> void:
	_used = true
