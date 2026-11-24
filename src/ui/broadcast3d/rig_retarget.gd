class_name FcRigRetarget
extends RefCounted
## The one piece of maths that lets ANY rig with the standard bone names wear the Full Court pose library (FcBroadcastPose), pure so it is tested without a
## model. The pose maths describe every bone rotation `q` in a frame whose axes are aligned with the world at rest (the generated skeleton is built that
## way). A rig exported from Blender has its own rest rotation on each bone (its bones point along their own axis, so an arm hangs with its bone turned
## 180 degrees), which would turn every pose into nonsense if `q` were applied as it is.
##
## The rule, for a bone with local rest rotation R whose parent has GLOBAL rest rotation G: the local rotation to set is  (G^-1 * q * G) * R.
## Why: the pose wants the bone to end up with global orientation Qg * Grest (the world-aligned rotation Qg of the chain, on top of the global rest
## orientation Grest = G * R). Going down the chain, the local rotation that achieves that from the parent global pose (Qg_parent * G) is
## (Qg_parent * G)^-1 * Qg * G * R, and with Qg = Qg_parent * q this simplifies to G^-1 * q * G * R. For a rig whose rest rotations are all the identity the
## result is q itself, so the generated body needs no retargeting.


## The local rotation to give a bone for the world-aligned pose rotation `q`.
static func local_rotation(parent_rest_global: Quaternion, rest_local: Quaternion, q: Quaternion) -> Quaternion:
	return (parent_rest_global.inverse() * q * parent_rest_global) * rest_local


## The global rest rotation of every bone (parents first) from the local rest rotations and parent indices.
static func global_rest_rotations(rest_local: Array, parents: Array) -> Array:
	var out: Array = []
	for i in rest_local.size():
		var parent := int(parents[i])
		out.append(rest_local[i] if parent < 0 else (out[parent] as Quaternion) * (rest_local[i] as Quaternion))
	return out
