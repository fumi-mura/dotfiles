#!/usr/bin/env python3
# Claude Code の PreToolUse フック。Read で大きい画像を開くとき、長い辺を1000pxに縮めた複製を読ませる。
# 画像は会話に残り、以降の返答のたびに読み直されるため。細部を見たいときはファイル名に .full を付ける。
import hashlib
import json
import os
import subprocess
import sys
import tempfile

MAX_SIDE = 1000
EXTENSIONS = {".png", ".jpg", ".jpeg", ".heic", ".tif", ".tiff", ".bmp", ".gif"}


def image_size(path):
    result = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True)
    values = [int(line.split()[-1]) for line in result.stdout.splitlines() if "pixel" in line]
    return tuple(values) if len(values) == 2 else None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name") != "Read":
        return
    tool_input = payload.get("tool_input") or {}
    path = os.path.expanduser(tool_input.get("file_path", ""))
    name, extension = os.path.splitext(os.path.basename(path))
    if extension.lower() not in EXTENSIONS or name.endswith(".full") or not os.path.isfile(path):
        return
    size = image_size(path)
    if not size or max(size) <= MAX_SIDE:
        return
    cache_dir = os.environ.get("SHRINK_IMAGE_CACHE_DIR") or os.path.join(tempfile.gettempdir(), "shrink-image")
    os.makedirs(cache_dir, exist_ok=True)
    key = hashlib.sha1(f"{path}:{os.path.getmtime(path)}".encode()).hexdigest()[:12]
    output = os.path.join(cache_dir, f"{name}-{key}.png")
    if not os.path.exists(output):
        subprocess.run(["sips", "-s", "format", "png", "-Z", str(MAX_SIDE), path, "--out", output], capture_output=True)
    shrunk = image_size(output) if os.path.exists(output) else None
    if not shrunk:
        return
    ratio = max(size) / max(shrunk)
    context = (
        f"{os.path.basename(path)} は {size[0]}x{size[1]} から {shrunk[0]}x{shrunk[1]} に縮めて表示している。"
        f"画像上の座標を元の画像の座標にするには ×{ratio:.3f} する。"
        f"細部が要るときは shot file --crop で一部を切り出すか、名前に .full を付けた複製を読む。"
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": dict(tool_input, file_path=output),
        "additionalContext": context,
    }}, ensure_ascii=False))


if __name__ == "__main__":
    main()
