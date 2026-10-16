#!/usr/bin/env python3
# Claude Code の Stop フック。最後の返答の本文がほぼ英語なら止めずに差し戻し、日本語で書き直させる。
# 長い作業のあとに英語で報告してしまい、指示（AGENTS.md の「常に日本語で会話する」）だけでは防げなかったため。
import json
import re
import sys

MIN_LATIN_LETTERS = 40
MIN_JAPANESE_RATIO = 0.2

JAPANESE = re.compile(r"[぀-ヿ㐀-䶿一-鿿ｦ-ﾟ]")
LATIN = re.compile(r"[A-Za-z]")
CODE_BLOCK = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE = re.compile(r"`[^`\n]*`")
URL = re.compile(r"https?://\S+")
PATH = re.compile(r"(?:~|\.{0,2})/[\w./-]+")

REASON = (
    "最後の返答が英語で書かれています。ユーザーへの文章は、途中経過、報告、質問、表を含めてすべて日本語で書く決まりです"
    "（~/.claude/CLAUDE.md の「常に日本語で会話する」）。同じ内容を日本語で書き直してください。コード、コマンド、識別子は英語のままでかまいません。"
)


def last_reply(transcript_path):
    try:
        with open(transcript_path, encoding="utf-8") as file:
            entries = [json.loads(line) for line in file if line.strip()]
    except (OSError, ValueError):
        return ""
    for entry in reversed(entries):
        message = entry.get("message") or {}
        content = message.get("content")
        if entry.get("type") == "user" and isinstance(content, str):
            return ""
        if entry.get("type") != "assistant" or not isinstance(content, list):
            continue
        texts = [block.get("text", "") for block in content if block.get("type") == "text"]
        if any(text.strip() for text in texts):
            return "\n".join(texts)
    return ""


def is_mostly_english(text):
    prose = PATH.sub(" ", URL.sub(" ", INLINE_CODE.sub(" ", CODE_BLOCK.sub(" ", text))))
    latin = len(LATIN.findall(prose))
    japanese = len(JAPANESE.findall(prose))
    if latin < MIN_LATIN_LETTERS:
        return False
    return japanese / (japanese + latin) < MIN_JAPANESE_RATIO


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    # 差し戻したあとの停止は通す。書き直しがまた英語でも、止め続けて会話が終わらなくなるのを防ぐ。
    if payload.get("stop_hook_active"):
        return
    text = payload.get("last_assistant_message") or last_reply(payload.get("transcript_path", ""))
    if is_mostly_english(text):
        print(json.dumps({"decision": "block", "reason": REASON}, ensure_ascii=False))


if __name__ == "__main__":
    main()
