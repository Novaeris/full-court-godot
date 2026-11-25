# AI development toolkit for Full Court

Written 2026-11-24. This is the one place that says what tools Claude Code has for working on Full Court, why each was chosen or rejected, how to set it up on another machine, and what it costs. Details live in the companion documents: [MCP_INTEGRATIONS.md](MCP_INTEGRATIONS.md), [ASSET_PRODUCTION_PIPELINE.md](ASSET_PRODUCTION_PIPELINE.md), [PLAYER_ANIMATION_PIPELINE.md](PLAYER_ANIMATION_PIPELINE.md). Everything marked "verified" was run, and the evidence is named.

## 1. Environment audit (before any change)
| Area | Finding |
|---|---|
| Engine | Godot 4.7.2 stable, `gl_compatibility` (project.godot), command line `godot_console` (winget). Windows 11 development machine; Ubuntu in CI |
| Blender | **Not installed and never used.** No `.blend` or `.glb` files, no `assets/` 3D content: all characters were generated in code (D-072) |
| Asset workflow | Images through Godot import; brand images rebuilt by `tools/build_brand_assets.sh`; audio synthesised in code (`FcAudioSynth`, `data/ui/audio.json`); fonts and icons in `assets/` with `assets/ART_PROVENANCE.md` |
| Tests | 1,683 unit and 240 live tests (headless Godot), the Creator Studio smoke test, simulation, economy and playthrough tools; style lint; `tools/perf_benchmark.gd` and `tools/scene_benchmark.gd` for frame time (run by hand: they need a window) |
| CI | `.github/workflows/ci.yml` (unit, live, 1000-game simulation, economy), `long-checks.yml` (weekly), `release.yml` (Windows build on a version tag). No asset validation, no GDScript-error scan, no Studio smoke, no Blender |
| Claude Code configuration | No project `.claude` folder, no `.mcp.json`, no project skills. User settings: a few git permissions, model choice. One user-level MCP server (Neon, a database service, unrelated). CLAUDE.md holds the project rules |
| Tools on the machine | Node 18+, `uv`/`uvx`, ffmpeg, git, `gh`, winget, PowerShell. Python only inside another tool's virtualenv (the scripts here use the standard library) |
| Conventions kept | CLAUDE.md rules, docs updated in the same change, tests with fixed seeds, no placeholder systems, nothing pushed without being asked (this plan asked for pushes) |

## 2. What is installed now
| Integration | Version | Where it is declared | Verified by |
|---|---|---|---|
| **Godot MCP** (Coding-Solo/godot-mcp) | 0.1.1, MIT | `.mcp.json` | `python tools/mcp/probe_mcp.py godot --call get_godot_version` returned 4.7.2; 14 tools listed |
| **Blender** (portable, official zip) | 4.5.10 LTS, GPL | `tools/blender/install_blender.ps1` (checksum verified) | `blender --version`; headless builds; a clean Ubuntu runner rebuilt the player and clips (`pipeline.yml`, success) |
| **Blender MCP** (mcp-for-blender, formerly blender-mcp) | 2.3.1, MIT | `.mcp.json` | with Blender open, `get_scene_info` and `execute_blender_code` returned the scene and `4.5.10 LTS` |
| **Project skill** `full-court-verify` | n/a | `.claude/skills/full-court-verify/SKILL.md` | read-through against the commands it names |
| **MCP probe** | n/a | `tools/mcp/probe_mcp.py` | used for both servers above |
| **Project validator** | n/a | `tools/validate_project.gd`, `tests/support/project_validator.gd` | 7 unit tests prove each check; it found two real broken tools on the first run (fixed) |
| **Player and animation pipeline** | n/a | `tools/blender/*`, `tools/export_*.gd`, `tools/bake_clip_library.gd` | `test_player_pipeline` (14 tests), the round trip is exact |
| **Audio preparation** | n/a | `tools/audio/prepare_audio.ps1` | a -49.8 LUFS test tone came out at -15.96 LUFS (target -16), silence trimmed |
| **CI additions** | n/a | `ci.yml` (validate, Studio smoke), `pipeline.yml` | the pipeline run passed on a clean machine; the new CI steps pass locally and are watched on GitHub |

### Set up a new machine (reproducible)
1. Clone the repository; install Godot 4.7.2 (`winget install GodotEngine.GodotEngine`), Node 18+, `uv`.
2. `./tools/blender/install_blender.ps1` (Windows; downloads, verifies, unpacks Blender and installs and enables the MCP add-on).
3. Start Claude Code in the repository and approve the two project MCP servers it offers (`godot`, `blender`), or run `claude mcp list`.
4. `python tools/mcp/probe_mcp.py godot --call get_godot_version` and, with Blender open (`./tools/blender/run_blender.ps1`), `python tools/mcp/probe_mcp.py blender --call get_scene_info`.
5. `godot_console --headless --path . --import --quit`, then `godot_console --headless --path . --script res://tools/validate_project.gd` (exit 0).

## 3. Evaluation of every candidate
Each entry: what it provides; how it connects to Claude Code; fit with this project; licence; cost; security; verdict.

### 3D and animation
**Blender 4.5 LTS: INSTALLED.** Full 3D suite with a Python API and headless mode, so Claude Code can build and rework assets by script (`blender -b --python`). Connects through the shell (scripts) and, optionally, the MCP below. Fits: its glTF exporter is the one Godot documents; LTS is supported until 2027. Licence GPL: free for any use, and what you create is yours. Cost: none. Security: it runs Python by design; scripts here are in the repository and reviewed; the installer verifies the SHA-256 that blender.org publishes. Verdict: essential.

**Blender MCP (mcp-for-blender): INSTALLED, with limits.** Lets Claude Code inspect and edit a live Blender session (scene info, run Python, viewport screenshots). MCP over stdio to a socket add-on inside Blender. Fits: useful for exploring and fixing a model; **not** used for production builds, which are headless scripts (repeatable, in CI). Licence MIT. Cost none. Security: `execute_blender_code` runs any Python with the user's rights over a socket; the add-on binds to localhost and refuses remote connections unless a setting is ticked (never tick it); telemetry was switched off with the server's own tool, though the server states minimal anonymous usage counts (tool, success, duration) remain; its asset and generation tools need the owner's own keys and none are configured. Close Blender when idle. Verdict: worthwhile, used carefully.

**Meshy and Tripo (AI text/image to 3D): NOT installed.** They generate meshes from prompts through a website or a paid API (credits). A generated mesh has arbitrary topology, no standard rig, inconsistent proportions and no weights, so it cannot feed the player pipeline (16 standard bones, named surfaces, validated weights); it could suit one-off props (a trophy, a mascot) after clean-up. Licensing: the free tiers give CC BY 4.0 (attribution required) and paid tiers add commercial rights, per their own pages, which disagree with third-party summaries, so every use needs the exact terms read first; the IP rule of this project (original assets, no unlicensed likenesses) needs provenance for each file. Cost: Meshy about 20 dollars a month for commercial rights, Tripo about 20, API prepaid. Security: uploads prompts or images to a third party. Needs an account and a key, which this plan does not authorise. Verdict: no, revisit for props only if the founder wants them.

**Mixamo (Adobe, free retargetable human animations): NOT installed; documented as an optional source.** A website that auto-rigs a character and serves FBX animations. Fits: a source of raw motion (it needs a free Adobe account and manual downloads, so it cannot be automated by Claude Code). Licence (forum summaries of Adobe's terms, the official text could not be retrieved): characters and animations may be used in commercial projects when embedded, but the raw files may not be redistributed or resold; check the current terms before shipping. Cost: free with an account. Retargeting to our 16 bones is described in the animation pipeline document. Verdict: not needed now (the procedural library plus Blender authoring covers the states); worth it later for natural-looking locomotion.

### Godot development
**Godot MCP (Coding-Solo): INSTALLED** (details in MCP_INTEGRATIONS.md). Launch and run the project, read its debug output, create scenes and nodes. File-level, works with the stock editor, no plugin. It does not replace the headless test runner. Verdict: worthwhile.

**Other Godot MCP servers (GDAI MCP plugin, godot-ai): NOT installed.** Both add an editor plugin and overlap with the server above; GDAI's price is reported inconsistently. Revisit only if live editor control becomes necessary.

**Godot-specific Claude skills (godogen, GodotPrompter, Godot-Claude-Skills, others): NOT installed.** They are aimed at generating whole games or generic GDScript help; this project has conventions, a test suite and CLAUDE.md, and third-party skills are instructions an agent follows, which is a supply-chain risk unless reviewed line by line. **"GameDev Skills by Setcode" could not be found** in a search, so it was not evaluated. The needed knowledge is in the project skill `full-court-verify` (and CLAUDE.md), which also records Godot pitfalls already hit in this repository.

**Scene validation and automated playtesting: BUILT IN-HOUSE.** `tools/validate_project.gd` (GDScript compile errors, broken scenes, missing or unimported assets, invalid JSON and audio data, invalid player models and clips; run in CI); the live tests (real scene tree, input, focus); `tools/screenshot.gd` and `tools/character_showcase.gd` (pictures of the real screens); `tools/click_test.gd` and `tools/ui_playthrough.gd` (scripted playthroughs); Godot MCP `run_project`/`get_debug_output` for ad-hoc runs. Verdict: sufficient; a gameplay bot is not justified yet.

### Audio
**ElevenLabs: NOT installed.** Text-to-speech, voice cloning and sound-effect generation by API (sound effects 0.12 dollars per generated minute; its free plan is non-commercial per third-party summaries, the Starter plan at about 6 dollars a month is the minimum for commercial licensing). Fits the commentary design: `FcCommentarySink` is a swappable interface (captions today), so recorded voice lines generated with the owner's own account could be a sink. Needs an account, an API key and a decision about synthetic voices that are not this plan's to make. Security: sends text to a third party; a key must never be committed. Verdict: not now; the path is documented (generate offline, run `prepare_audio.ps1`, add the file with a provenance line, keep the synth recipe as fallback).

**Audacity: NOT installed.** GPL audio editor for hand editing. Everything it would do for the game (trim, normalise, convert) is scripted with ffmpeg (`tools/audio/prepare_audio.ps1`), which is repeatable and can run in CI; a GUI editor is a manual step Claude Code cannot drive. Install it only if a person wants to edit by ear.

**AI-generated sound effects and music: policy.** The game makes every sound itself (`data/ui/audio.json`, `FcAudioSynth`, no unlicensed audio, decision D4). External or AI-generated audio may be added only with the founder's approval, a provenance line, a licence that allows commercial use, loudness preparation by the script, and a synth fallback so a missing file never breaks the game. The audio validator (`check_audio`) enforces buses, gain range, fallbacks and loop rules.

### Development infrastructure
**GitHub Actions: IMPROVED.** `ci.yml` now also runs the project validator and the Creator Studio smoke test; `pipeline.yml` rebuilds the Blender player and the animation clips from the rig standard on a clean machine (Blender downloaded and checksum-verified) and runs the pipeline tests. Free on a public repository, so no cost. Security: no secrets are used.

**Automated testing, build automation, asset validation: IN PLACE** (above). Not added: a frame-time gate in CI (it needs a GPU; `tests/unit/test_3d_budget.gd` guards the size of the work instead, see QA below).

**Claude Code skills and MCP integrations:** project-scoped, committed, pinned, no credentials. One project skill was written; more are added only when a repeated task earns one.

## 4. Quality assurance now available
| Risk | Check | Where |
|---|---|---|
| GDScript errors | every `.gd` must compile | `validate_project.gd`; found two real broken dev tools |
| Broken scenes and resources | every `.tscn`/`.tres` loads, dependencies exist | same |
| Missing imported assets | every asset has an `.import` leading to an imported copy (folders with `.gdignore` are skipped, as Godot does) | same |
| Invalid player models | the player validator (bones, parents, rest pose, left/right, floor, surfaces, materials, skinning, weights, height, budget) | `FcPlayerModelValidator`, 14 tests |
| Animation compatibility | the clip validator (names, bones, translation only on the pelvis, no scale, lengths, quaternions) | `FcAnimationClipValidator`, tests |
| Audio data | buses, gains, fallbacks, loops, volume setting per bus | `check_audio`, tests |
| Performance regressions | triangle budget per player, nodes per scene, one crowd MultiMesh, loose timing guards (about 10 times the measured cost) | `test_3d_budget.gd` (3 tests); frame time itself by hand with `scene_benchmark.gd` and `perf_benchmark.gd` |
| Test regressions | unit, live, Studio smoke, simulation, economy | `ci.yml` |
| Export failures | the Windows export runs on a version tag (`release.yml`); **not** on every push (it needs 700 MB of templates) | `release.yml` |

## 5. Remaining manual setup and decisions for the owner
- Approve the two project MCP servers the first time Claude Code asks.
- On macOS or Linux: install Blender yourself (the installer script is Windows PowerShell) and set `BLENDER_PATH`; the build scripts themselves are cross-platform Python.
- The portable Blender was unpacked in the user folder because the winget installer wants administrator rights; if a system-wide copy is wanted, install it with winget and set `BLENDER_PATH`.
- Decisions that are NOT mine to make and were not made: paying for ElevenLabs, Meshy or Tripo; using AI-generated or synthetic-voice audio; making the Blender-built player the default look (the generated body still is); a Mixamo account.
- The animation clips are not played by the game yet (migration plan in PLAYER_ANIMATION_PIPELINE.md).

## 6. Costs
Spent: nothing. Needed: nothing. Optional: ElevenLabs from about 6 dollars a month, Meshy or Tripo from about 20 dollars a month, neither recommended now.

## MPFB (MakeHuman for Blender), added 2026-11-24 (D-075)
MPFB 2.0.18 (GPL-3, a build tool: nothing of it ships) and the CC0 `makehuman_system_assets` pack, installed into the portable Blender's user profile by `tools/blender/install_mpfb.ps1` with pinned SHA-256 checksums. Used headlessly by `tools/blender/v2/` to generate the V2 players ([PLAYER_V2.md](PLAYER_V2.md)). Only CC0 data is used; CC-BY packs are not.

