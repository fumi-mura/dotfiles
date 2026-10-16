#!/bin/bash
# shrink-image.py が、大きい画像だけを縮めた複製に差し替え、倍率を伝えるかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
HOOK="${ROOT_DIR}/shared/ai/hooks/shrink-image.py"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export SHRINK_IMAGE_CACHE_DIR="${WORK}/cache"

failures=0

check() {
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n     -> %s\n' "$1" "$3"
  fi
}

make_png() {
  python3 - "$1" "$2" "$3" <<'PY'
import struct, sys, zlib
path, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
row = b"\x00" + b"\x80\x80\x80" * width
raw = row * height
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
with open(path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
}

run() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Read","tool_input":{"file_path":sys.argv[1]}}))' "$1" | python3 "${HOOK}"
}

field() {
  python3 -c 'import json,sys; d=sys.stdin.read().strip(); o=json.loads(d)["hookSpecificOutput"] if d else {}; print(o.get("updatedInput",{}).get("file_path","") if sys.argv[1]=="path" else o.get("additionalContext",""))' "$1"
}

make_png "${WORK}/big.png" 1710 2146
out="$(run "${WORK}/big.png")"
path="$(printf '%s' "${out}" | field path)"
context="$(printf '%s' "${out}" | field context)"
if [[ -f "${path}" && "${path}" != "${WORK}/big.png" ]]; then
  size="$(sips -g pixelWidth -g pixelHeight "${path}" | awk '/pixel/ { print $2 }' | paste -sd x -)"
  [[ "${size}" == "797x1000" ]] && check "長い辺を1000pxに縮める" ok || check "長い辺を1000pxに縮める" ng "${size}"
else
  check "大きい画像は縮めた複製に差し替える" ng "${out}"
fi
[[ "${context}" == *"1710x2146"* && "${context}" == *"2.146"* ]] && check "元の大きさと倍率を伝える" ok || check "元の大きさと倍率を伝える" ng "${context}"

make_png "${WORK}/small.png" 800 600
[[ -z "$(run "${WORK}/small.png")" ]] && check "小さい画像はそのまま" ok || check "小さい画像はそのまま" ng "差し替えた"

make_png "${WORK}/detail.full.png" 1710 2146
[[ -z "$(run "${WORK}/detail.full.png")" ]] && check ".full の付いた画像はそのまま" ok || check ".full の付いた画像はそのまま" ng "差し替えた"

printf 'hello\n' >"${WORK}/note.txt"
[[ -z "$(run "${WORK}/note.txt")" ]] && check "画像以外はそのまま" ok || check "画像以外はそのまま" ng "差し替えた"

[[ -z "$(run "${WORK}/missing.png")" ]] && check "ないファイルはそのまま" ok || check "ないファイルはそのまま" ng "差し替えた"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
