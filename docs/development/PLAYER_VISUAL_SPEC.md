# Full Court player visual specification (M1)

Status: written 2026-11-24 at the start of Production Phase M1 (decision D-074). This is the art direction and the checklist a player model must pass. It changes only with a decision.

## 1. Target
Realistic-stylized basketball athletes: believable human proportions, a face you can tell apart from the next player's, detailed athletic clothing, the same person in every mode (Owner, Career, Dynasty, Broadcast, Creator Studio, portraits). Not photoreal, not cartoon: closer to a sports-game character at broadcast distance with enough detail to survive the player showcase and a head-and-shoulders portrait.

## 2. Baseline (the "before", `docs/validation/player_m1/before_*`)
- Procedural body (`FcBodyBuilder`, the default): smooth lofted torso and limbs, a jersey that is a flat tube with a floating hem, shorts as a blob, arms as tubes with mitten hands, a head with eye and mouth marks, a nose bump and ears, hair as one cap.
- Script-built Blender prototype (`fc_player_proto.glb`): the same body kit; simpler face; two hair styles; no facial hair; looks the same or slightly worse.
- Verdict: both read as mannequins. Weaknesses to fix, in order of visual impact: (1) head and face, (2) jersey and shorts shape (armholes, neckline, hem, folds), (3) hands, (4) shoes, (5) hair variety, (6) muscle definition and body types, (7) numbers and branding on the cloth.
- Camera rule (D-070): the 3D broadcast camera is never closer than 28 ft. The face matters most in the showcase, in portraits rendered from the model, and in medium shots on a large screen; the silhouette, the clothing and the hair matter in every shot.

## 3. Proportions
Height 1.60 to 2.45 m (the standard), scaled per player by the game; a heavier build is also a little wider. Head is about 1/7.5 of the height (0.128 H in the standard, kept). Shoulder width, wingspan (about 1.01 H) and leg ratio come from `rig_standard.json`. Three body types (lean, athletic, heavy) differ in torso depth, shoulder and thigh mass, and muscle definition, not in the skeleton.

## 4. Head and face standard
Required geometry (head surface about 2,000 to 3,000 triangles): defined jaw and chin, cheekbones, brow ridge, nose with bridge, tip, wings and nostrils, eye sockets with separate eyeballs (white, iris, pupil) and upper and lower eyelids, lips (upper, lower, mouth line), ears with inner detail, a neck that blends into the trapezius, and a hairline. Variation axes (all from `FcPlayerVisual.proportions` plus `face`): head width, jaw (round, square, pointed), eye gap and size, brow weight, nose style, mouth style, ear size, hairline height. Faces are build-time head variants blended by parameters, never one model per player.

## 5. Hair, facial hair, accessories
Hair styles exactly as in the identity data: bald, short, fade, afro, braids, locs, curly, long. Facial hair: none, stubble, goatee, beard. Accessories: headband (from `proportions.accessory`). Each is its own mesh named `hair_<style>`, `facial_<style>`, `acc_headband`, shown by name. Hair must read at close, medium and far: solid shapes with a few strand cards or ridges, no thousands of strands, minimal transparency.

## 6. Clothing
Jersey: armholes that follow the shoulder, scoop neckline, trim at neck and arm openings, side panels, a hem that sits on the shorts, subtle fabric normal. Shorts: waistband, drawcord, side trim, hem and a few folds. Socks with a cuff stripe. Shoes: upper panels, laces, tongue, midsole, outsole. Colours come from the team (primary, secondary); number, surname and wordmark come from a shared texture or shader (never per-number geometry); Label3D stays as a fallback.

## 7. Materials and budget
Target about 12,000 triangles per player (limit 20,000, unchanged). Aim for 4 to 6 shared material slots (skin, hair, cloth, shoes, plus eyes and trim where needed); 12 is a ceiling. Materials are shared between players; team colour, skin, hair colour, number and surname are shader or material parameters. Minimal transparency. Measured costs go in `docs/validation/player_m1/PERFORMANCE.md`.

## 8. Technical contract (unchanged unless stated)
Rig standard v1 and its 16 bones; optional `x_` extension bones (fingers) only; arms hang at rest; soles on y = 0; faces +Z; left is +X; skin weights at most 4 per vertex. Surface names are validated by `FcPlayerModelValidator`; new approved names are added to the validator explicitly (it is never weakened to fit a model). GLB export. The generated body stays the fallback; the new model is opt-in until the founder approves it as the default.

## 9. Quality rubric (what "visibly better" means, scored on real game screenshots)
1. Silhouette: neck, shoulders, waist, jersey hem and shorts shape read as a human athlete at far range.
2. Face: eyes, nose, mouth and jaw read at medium range; two players look different.
3. Clothing: armholes, neckline and folds read; the number is crisp.
4. Hair and facial hair: every catalogue style is recognisable.
5. Hands and shoes: fingers and a real shoe shape.
6. Motion: no tearing at shoulders, elbows, hips and knees through the 34 states; fingers close on the ball.
7. Consistency: the same key gives the same person everywhere.
8. Cost: no frame-time regression beyond the thresholds in `docs/validation/PERFORMANCE_THRESHOLDS.md`.
A person (the founder) approves the art direction; automation cannot.

## 10. Reusable versus basketball-specific
`tools/blender/fc_character/`: mesh, rig, weighting, material and export helpers (sport-agnostic). `tools/blender/basketball/`: bodies, heads, hair, jerseys, shorts, shoes, accessories. Runtime: `FcPlayerAssetLibrary` (registry and cache) consumes `FcPlayerVisual.resolve()`; it does not replace it.
