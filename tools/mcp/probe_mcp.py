#!/usr/bin/env python3
"""Probe an MCP server over stdio: start it, do the real MCP handshake, list its tools, stop it.

Why this exists: an entry in .mcp.json proves nothing until the server starts and answers. This performs the same first steps Claude Code does
(initialize, notifications/initialized, tools/list) and prints what the server really offers, so an installation can be VERIFIED and re-verified on
any machine. Standard library only. Exit code 0 = the server answered and listed at least one tool; 1 = it did not.

Usage:
    python tools/mcp/probe_mcp.py <server name in .mcp.json>          # reads ./.mcp.json
    python tools/mcp/probe_mcp.py --command npx --args -y @coding-solo/godot-mcp@0.1.1
Options: --timeout SECONDS (default 90, the first run of npx or uvx downloads the package), --env KEY=VALUE (repeatable), --json (print the tool list as JSON).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time


def expand(value: str, env: dict) -> str:
    """Expand ${VAR} and ${VAR:-default} the way Claude Code does for .mcp.json."""
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}", lambda m: env.get(m.group(1)) or (m.group(2) or ""), value)


def read_config(name: str) -> dict:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    with open(os.path.join(root, ".mcp.json"), encoding="utf-8") as handle:
        servers = json.load(handle).get("mcpServers", {})
    if name not in servers:
        sys.exit("no server called %r in .mcp.json (have: %s)" % (name, ", ".join(servers)))
    return servers[name]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("name", nargs="?")
    parser.add_argument("--command")
    parser.add_argument("--args", nargs=argparse.REMAINDER, default=[])
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--call", help="after listing, call this tool once (for example get_godot_version) and print its text result")
    parser.add_argument("--call-args", default="{}", help="JSON arguments for --call")
    options = parser.parse_args()
    env = dict(os.environ)
    if options.name:
        config = read_config(options.name)
        command, args = expand(config["command"], env), [expand(a, env) for a in config.get("args", [])]
        env.update({k: expand(str(v), env) for k, v in config.get("env", {}).items()})
    elif options.command:
        command, args = options.command, options.args
    else:
        parser.error("give a server name or --command")
    for pair in options.env:
        key, _, value = pair.partition("=")
        env[key] = value
    resolved = shutil.which(command) or command
    process = subprocess.Popen([resolved] + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True, encoding="utf-8", bufsize=1)
    replies: dict = {}
    stderr_lines: list = []

    def pump_out() -> None:
        for line in process.stdout:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if "id" in message:
                replies[message["id"]] = message

    def pump_err() -> None:
        for line in process.stderr:
            stderr_lines.append(line.rstrip())

    threading.Thread(target=pump_out, daemon=True).start()
    threading.Thread(target=pump_err, daemon=True).start()

    def send(message: dict) -> None:
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def wait_for(request_id: int) -> dict:
        deadline = time.time() + options.timeout
        while time.time() < deadline:
            if request_id in replies:
                return replies[request_id]
            if process.poll() is not None and request_id not in replies:
                break
            time.sleep(0.05)
        return {}

    code = 1
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "full-court-probe", "version": "1"}}})
        init = wait_for(1)
        if not init:
            print("FAIL: no answer to initialize within %.0f s" % options.timeout)
            print("\n".join(stderr_lines[-15:]))
            return 1
        info = init.get("result", {}).get("serverInfo", {})
        print("server: %s %s (protocol %s)" % (info.get("name", "?"), info.get("version", "?"), init.get("result", {}).get("protocolVersion", "?")))
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        listed = wait_for(2)
        tools = listed.get("result", {}).get("tools", [])
        if options.json:
            print(json.dumps([{"name": t["name"], "description": t.get("description", "")} for t in tools], indent=2))
        else:
            print("%d tools:" % len(tools))
            for tool in tools:
                print("  %-34s %s" % (tool["name"], tool.get("description", "").split("\n")[0][:90]))
        code = 0 if tools else 1
        if options.call and code == 0:
            send({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": options.call, "arguments": json.loads(options.call_args)}})
            answer = wait_for(3)
            content = answer.get("result", {}).get("content", [])
            text = " ".join(str(c.get("text", "")) for c in content).strip()
            print("call %s -> %s%s" % (options.call, "ERROR " if answer.get("result", {}).get("isError") or "error" in answer else "", text[:400] or str(answer)[:400]))
            if answer.get("result", {}).get("isError") or "error" in answer or not answer:
                code = 1
    finally:
        try:
            process.stdin.close()
        except OSError:
            pass
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
    return code


if __name__ == "__main__":
    sys.exit(main())
