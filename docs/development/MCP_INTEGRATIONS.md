# MCP integrations

An MCP server gives Claude Code extra tools. This file lists what is installed for Full Court, exactly how, how to verify it, and what is deliberately NOT installed. Project servers are declared in [`.mcp.json`](../../.mcp.json) at the repository root (version pinned, no credentials), so a fresh clone gets them. Claude Code asks for approval the first time it sees a project server: approve it (or run `claude mcp list`).

Verification for every server is the same real handshake Claude Code performs: `python tools/mcp/probe_mcp.py <name> [--call TOOL --call-args JSON]` starts the server from `.mcp.json`, initialises it, lists its tools and optionally calls one. Exit code 0 means it answered. Standard library only.

## Installed

### godot (Coding-Solo/godot-mcp 0.1.1, MIT)
- **What it gives:** 14 tools: launch the Godot editor for a project, run the project and capture its output, read the debug output and errors, stop it, get the Godot version, list projects, read project info, create a scene, add a node, save a scene, export a MeshLibrary, load a sprite, get a file's UID and update UID references (Godot 4.4+).
- **Install (reproducible):** nothing to install by hand. `.mcp.json` runs `npx -y @coding-solo/godot-mcp@0.1.1` (Node 18 or newer) with `GODOT_PATH` defaulting to `godot_console`, which is on the PATH on the development machine (installed by winget). Set the environment variable `GODOT_PATH` to another Godot executable to override.
- **Verified (2026-11-24):** `python tools/mcp/probe_mcp.py godot --call get_godot_version` printed 14 tools and `4.7.2.stable.official.ed1daf0bf`; `get_project_info` on this repository returned its metadata.
- **How it is used here:** run the real game from the agent and read the errors (`run_project`, `get_debug_output`), create or inspect scenes without opening the editor. It does NOT replace the headless test runner (`tests/run_tests.gd`), which is the authority for pass or fail, and it cannot take pictures; for pictures use `tools/character_showcase.gd` and `tools/screenshot.gd`.
- **Security:** it runs local commands (the Godot executable) with the agent's rights and writes scene files in the project. It makes no network calls of its own beyond the one-time npm download. Pinned to an exact version so an upstream release cannot change it silently. Review the version before bumping it.
- **Cost and licence:** free, MIT.

## Not installed, and why
| Candidate | Decision |
|---|---|
| GDAI MCP (editor plugin) | Not installed. Sources disagree on whether it is paid; it adds an editor plugin to the project; the free server above covers the file-level needs, and the headless test and screenshot tools cover verification. Revisit if live editor control is needed. |
| godot-ai (Python server plus editor plugin) | Not installed. Redundant with the server above and adds a plugin and a second server on a port. |
| Third-party Godot skill packs (godogen, GodotPrompter, Godot-Claude-Skills and others) | Not installed. They target building a whole game from a prompt or generic GDScript help; this project has its own conventions, tests and CLAUDE.md, and an unreviewed skill pack is a supply-chain risk. Project skills live in `.claude/skills/` instead. A "Setcode GameDev Skills" pack could not be found, so it was not evaluated. |
