# 3D overhaul, M2: animation

Written 2026-11-23. Pictures: `docs/validation/3d_overhaul/m2/` (`pose_sheet_0..4.png`: all 27 states, side view, real floor; `replay_free_throw.png`: the real replay screen). Made by `tools/character_showcase.gd poses=1`.

## What changed
- **27 states** (was 6): idle, walk, run, sprint, stop, turn, jump, land, fall, celebrate; dribble, dribble_run, crossover, hesitation, drive, post; shoot, three, layup, dunk; defend, shuffle, contest, steal, block, rebound, recover. Written in anatomical terms (forward, out, bend) and converted once, so a pose reads like the move it names.
- **More joints**: neck, wrists and ankles were added to the pose (16 joints), so heads, hands and feet can move on their own.
- **Foot placement**: a ground-contact pass puts the lower foot's sole on the floor in every grounded state (no floating, no sinking); airborne states (jump, jump shot, layup, dunk, contest, block, rebound) really leave the floor; planted feet are kept flat.
- **Hands on the ball**: `FcLimbIK` is a pure two-bone solver. In shots, dunks, rebounds and post moves both arms reach the ball with it (the pose carries a ball anchor and a grip amount that fades in and out). A dunk by a 6 ft 7 in player puts the hand above the 10 ft rim (tested).
- **No sliding**: a stride covers a fixed number of body heights per loop (run 1.3, sprint 1.5, walk 0.8, drive 1.1) and the view sets the animation speed to match the speed the body travels (clamped 0.55 to 1.6), so feet stay planted instead of skating.
- **Events to actions** (`FcBroadcast3DRules.action_for`, pure): a miss or make at the rim is a layup (some made ones, chosen by the player's id, a dunk), a three or a mid-range shot is a jump shot, a free throw is a set shot, a rebound is a rebound, a block is a block, the nearest defender to a shooter contests it, a thief steals, a passer on a basket celebrates. The simulation is only read, never asked: no outcome changes.
- **Defenders face the play** while they slide; everyone else faces where they go; turning is smoothed.

## A real bug found and fixed
Godot switches `_process` back on when a node enters the tree whatever `set_process(false)` said earlier, so every character advanced itself AND was advanced by the replay view: animations ran at twice the intended speed since B4. Fixed with an explicit `auto_advance` flag (`FcBroadcastCharacter`). Also found: `Skeleton3D.get_bone_global_pose` is stale until the skeleton refreshes, so ground contact and IK use a small forward-kinematics routine of our own.

## Tests (unit, headless)
`tests/unit/test_broadcast_animation.gd` (8): IK reaches 200 random reachable targets within 0.01 ft and stretches straight when out of reach; every state is a valid pose with air and grip as fractions; no foot sinks below the floor in any state and grounded states keep the lower foot on it; airborne states leave the floor and a dunk reaches the rim; the wrists are within 0.06 ft of their place on the ball whenever the grip is full (reachable cases); strides match ground speed under the reconstruction limit; events choose the right actions; left/right are anatomical. The 6 older `test_broadcast_character` tests (loop closure, no popping blends between ANY two of the 27 states, 0.42 rad per hundredth of a loop) pass unchanged. Live: `test_live_broadcast3d` 6 passed.

## Performance (same procedure as M1, 30 s, development machine only)
avg 3.13 ms, p95 4.04 ms, p99 4.58 ms, worst 12.37 ms, none over 16.6 ms; working set 307 MB; video memory 54 MB; draw calls about 580. Limits: p95 16.6 ms, p99 33.3 ms.

## Limits (honest)
- Poses are hand-tuned maths, not captured motion: they read as the right moves in the pictures but are not smooth like mocap; arm and leg arcs have not been checked frame by frame in motion by a person.
- Fingers are still a fixed open hand; the ball sits between the wrists but the hands do not wrap it.
- The shooter's hands are only checked against the ball anchor, not the real simulated ball path; the ball flight itself changes in M3.
- Only the right hand dribbles; a left-handed player is not drawn.
- Defenders slide in their direction of travel with their body facing the basket, which can look odd on long diagonals.

## Full-suite result
Unit suite after M2: 1,665 passed, 0 failed (one fresh run, `godot_console --headless --path . --script res://tests/run_tests.gd`). Live suite not re-run in full (only `test_live_broadcast3d`, 6 passed).
