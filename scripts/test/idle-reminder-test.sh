#!/bin/bash
# idle-reminder.py が、前の返答から1時間以上空いたときだけ /new を勧めるかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
HOOK="${ROOT_DIR}/shared/ai/hooks/idle-reminder.py"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failures=0

check() {
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n     -> %s\n' "$1" "$3"
  fi
}

# 最後の返答が $1 分前の transcript でフックを動かす
run() {
  python3 - "${WORK}/transcript.jsonl" "$1" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
path, minutes = sys.argv[1], int(sys.argv[2])
now = datetime.now(timezone.utc)
stamp = lambda m: (now - timedelta(minutes=m)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
lines = [
    {"type": "user", "timestamp": stamp(minutes + 1), "message": {"role": "user", "content": "直して"}},
    {"type": "assistant", "timestamp": stamp(minutes), "message": {"role": "assistant", "content": [{"type": "text", "text": "直しました"}]}},
]
with open(path, "w") as f:
    for line in lines:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")
PY
  printf '{"transcript_path":"%s","prompt":"次"}' "${WORK}/transcript.jsonl" | python3 "${HOOK}"
}

out="$(run 90)"
[[ "${out}" == *"systemMessage"* && "${out}" == *"/new"* ]] && check "90分空いたら /new を勧める" ok || check "90分空いたら /new を勧める" ng "${out}"

out="$(run 10)"
[[ -z "${out}" ]] && check "10分なら何も出さない" ok || check "10分なら何も出さない" ng "${out}"

out="$(printf '{"transcript_path":"%s/none.jsonl","prompt":"x"}' "${WORK}" | python3 "${HOOK}")"
[[ -z "${out}" ]] && check "記録がなければ何も出さない" ok || check "記録がなければ何も出さない" ng "${out}"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
