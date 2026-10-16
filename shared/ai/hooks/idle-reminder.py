#!/usr/bin/env python3
# Claude Code の UserPromptSubmit フック。前の返答から1時間以上空いていたら、/new を勧める一言を利用者に表示する。
# プロンプトのキャッシュは約1時間で切れ、再開すると会話全体を書き直すため、別の作業なら新しく始めたほうが安い。
import json
import sys
from datetime import datetime, timezone

IDLE_MINUTES = 60


def last_reply_time(transcript_path):
    try:
        with open(transcript_path, encoding="utf-8") as file:
            lines = file.readlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") == "assistant" and entry.get("timestamp"):
            return datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00"))
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    last = last_reply_time(payload.get("transcript_path", ""))
    if not last:
        return
    minutes = (datetime.now(timezone.utc) - last).total_seconds() / 60
    if minutes < IDLE_MINUTES:
        return
    message = (
        f"前の返答から {int(minutes)} 分空いています。キャッシュが切れているので、"
        "別の作業なら /new で始めたほうがトークンを節約できます。"
    )
    print(json.dumps({"systemMessage": message}, ensure_ascii=False))


if __name__ == "__main__":
    main()
