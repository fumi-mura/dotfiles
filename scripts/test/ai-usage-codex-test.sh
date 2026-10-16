#!/bin/bash
# ai-usage-codex が、期間内の応答だけを、同じ応答を二重に数えずに集計するかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
USAGE="${ROOT_DIR}/bin/ai-usage-codex"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export CODEX_SESSIONS_DIR="${WORK}/sessions"
export TZ="Asia/Tokyo"

failures=0

check() {
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n     -> %s\n' "$1" "$3"
  fi
}

mkdir -p "${CODEX_SESSIONS_DIR}/2026/10/17"
python3 - "${CODEX_SESSIONS_DIR}/2026/10/17/rollout-2026-10-17T10-00-00-bbbbbbbb-2222.jsonl" <<'PY'
import json, sys
def user(ts, text):
    return {"timestamp": ts, "type": "event_msg", "payload": {"type": "item_completed", "item": {"type": "UserMessage", "content": [{"type": "text", "text": text}]}}}
def usage(ts, rid, inp, cached, out, reasoning):
    return {"timestamp": ts, "type": "token_usage_record", "payload": {"response_id": rid, "usage": {
        "input_tokens": inp, "cached_input_tokens": cached, "output_tokens": out, "reasoning_output_tokens": reasoning}}}
lines = [
    {"timestamp": "2026-10-16T14:00:00.000Z", "type": "session_meta", "payload": {"cwd": "/Users/me/Program/Reelo"}},
    # 前日（JST 10/16 23:00）は数えない
    user("2026-10-16T14:00:01.000Z", "前日の依頼"),
    usage("2026-10-16T14:00:05.000Z", "r0", 9000, 8000, 90, 9),
    user("2026-10-17T01:00:00.000Z", "リリースノートを書いて"),
    usage("2026-10-17T01:00:05.000Z", "r1", 2000, 1000, 10, 4),
    # 同じ応答の記録が重なっても1回と数える
    usage("2026-10-17T01:00:05.100Z", "r1", 2000, 1000, 10, 4),
    usage("2026-10-17T01:00:09.000Z", "r2", 4000, 3000, 20, 6),
    user("2026-10-17T02:00:00.000Z", "翻訳して"),
    usage("2026-10-17T02:00:05.000Z", "r3", 6000, 5000, 30, 8),
]
with open(sys.argv[1], "w") as f:
    for line in lines:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")
PY
# 実際の記録と同じく、ファイルの更新日時を最後の記録より後にする（集計は期間より前に更新されたファイルを読み飛ばす）
find "${WORK}" -name "*.jsonl" -exec touch -t 202610171200 {} +

out="$("${USAGE}" --since 2026-10-17 2>&1)"
status=$?
[[ ${status} -eq 0 ]] && check "正常に終わる" ok || check "正常に終わる" ng "${out}"
[[ "${out}" == *"応答 3 回"* ]] && check "同じ応答は1回、前日は除いて3回" ok || check "同じ応答は1回、前日は除いて3回" ng "${out}"
[[ "${out}" == *"キャッシュ済み入力 9.0k"* ]] && check "キャッシュ済み入力は 1000+3000+5000" ok || check "キャッシュ済み入力は 1000+3000+5000" ng "${out}"
[[ "${out}" == *"キャッシュなし入力 3.0k"* ]] && check "キャッシュなし入力は 12000-9000" ok || check "キャッシュなし入力は 12000-9000" ng "${out}"
[[ "${out}" == *"出力 60"* ]] && check "出力は 10+20+30" ok || check "出力は 10+20+30" ng "${out}"
[[ "${out}" == *"Reelo"* && "${out}" == *"bbbbbbbb"* ]] && check "プロジェクトとセッションを出す" ok || check "プロジェクトとセッションを出す" ng "${out}"

out="$("${USAGE}" --since 2026-10-17 --by prompt 2>&1)"
[[ "${out}" == *"リリースノートを書いて"* && "${out}" == *"翻訳して"* && "${out}" != *"前日の依頼"* ]] \
  && check "--by prompt は期間内の依頼ごとに出す" ok || check "--by prompt は期間内の依頼ごとに出す" ng "${out}"

out="$("${USAGE}" --since 2026-10-18 2>&1)"
[[ "${out}" == *"応答 0 回"* ]] && check "期間に応答がなければ0回" ok || check "期間に応答がなければ0回" ng "${out}"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
