#!/bin/bash
# shot file が、画像を長い辺1000px以内に縮め、縮めた画像の座標で切り出した部分を元の解像度で出すかを検証する
# ウィンドウとシミュレーターの撮影は画面と権限に依存するため、ここでは確かめない

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
SHOT="${ROOT_DIR}/bin/shot"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export SHOT_OUTPUT_DIR="${WORK}/out"

failures=0

check() {
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n     -> %s\n' "$1" "$3"
  fi
}

size() {
  sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ { print $2 }' | paste -sd x -
}

# 左半分が赤、右半分が青の 2000x1000 の画像
python3 - "${WORK}/source.png" <<'PY'
import struct, sys, zlib
path, width, height = sys.argv[1], 2000, 1000
row = b"\x00" + b"\xff\x00\x00" * (width // 2) + b"\x00\x00\xff" * (width // 2)
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
with open(path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))
PY

out="$("${SHOT}" file "${WORK}/source.png")"
path="$(printf '%s\n' "${out}" | head -1)"
[[ -f "${path}" && "$(size "${path}")" == "1000x500" ]] && check "全体は長い辺1000pxに縮める" ok || check "全体は長い辺1000pxに縮める" ng "${out}"

# 縮めた画像の (500,0) から 250x250 = 元の (1000,0) から 500x500。右半分なので青だけ
out="$("${SHOT}" file "${WORK}/source.png" --crop 500,0,250,250)"
path="$(printf '%s\n' "${out}" | head -1)"
[[ -f "${path}" && "$(size "${path}")" == "500x500" ]] && check "切り出しは元の解像度で出す" ok || check "切り出しは元の解像度で出す" ng "${out}"
color="$(python3 - "${path}" <<'PY'
import subprocess, sys
# sips で BMP にすると、画素をそのまま読める
bmp = sys.argv[1] + ".bmp"
subprocess.run(["sips", "-s", "format", "bmp", sys.argv[1], "--out", bmp], capture_output=True)
data = open(bmp, "rb").read()
offset = int.from_bytes(data[10:14], "little")
b, g, r = data[offset], data[offset + 1], data[offset + 2]
print("blue" if b > 200 and r < 50 else f"{r},{g},{b}")
PY
)"
[[ "${color}" == "blue" ]] && check "指定した位置を切り出す" ok || check "指定した位置を切り出す" ng "${color}"

"${SHOT}" file "${WORK}/source.png" --crop 900,0,500,500 >/dev/null 2>&1
[[ $? -ne 0 ]] && check "はみ出す切り出しは失敗にする" ok || check "はみ出す切り出しは失敗にする" ng "成功した"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
