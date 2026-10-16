#!/usr/bin/env python3
# Claude Code の PreToolUse フック。テストとビルドのコマンドを ~/.local/bin/quiet 経由に書き換え、会話に入る出力を絞る。
# 失敗したコマンドの出力は PostToolUse で差し替えられないため、実行前に書き換える。
# 自分で | や > で出力を絞っているコマンドは、意図があるのでそのまま通す。
import json
import re
import shlex
import sys

QUIET = "~/.local/bin/quiet"
NOISY = [
    re.compile(r"^swift (test|build)\b"),
    re.compile(r"^xcodebuild\b"),
    re.compile(r"^(npm|pnpm|yarn|bun) (test|run (test|build|lint)|build)\b"),
    re.compile(r"^(pytest|python3? -m pytest)\b"),
    re.compile(r"^cargo (test|build)\b"),
    re.compile(r"^go (test|build)\b"),
    re.compile(r"^make (test|build)\b"),
]
SEGMENT = re.compile(r"\s*(?:&&|\|\||;)\s*")


def should_quiet(command):
    plain = command.replace("||", "").replace("2>&1", "")
    if "|" in plain or ">" in plain or "quiet" in command:
        return False
    return any(pattern.search(segment) for segment in SEGMENT.split(command.strip()) for pattern in NOISY)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name") != "Bash":
        return
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command", "")
    if not should_quiet(command):
        return
    updated = dict(tool_input, command=f"{QUIET} /bin/zsh -c {shlex.quote(command)}")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": updated}}, ensure_ascii=False))


if __name__ == "__main__":
    main()
