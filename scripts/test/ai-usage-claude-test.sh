#!/bin/bash
# ai-usage-claude が、期間内の返答だけを、同じメッセージを二重に数えずに集計するかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
USAGE="${ROOT_DIR}/bin/ai-usage-claude"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export CLAUDE_PROJECTS_DIR="${WORK}/projects"
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

mkdir -p "${CLAUDE_PROJECTS_DIR}/-Users-me-Program-app"
python3 - "${CLAUDE_PROJECTS_DIR}/-Users-me-Program-app/aaaaaaaa-1111.jsonl" <<'PY'
import json, sys
def assistant(ts, mid, read, out, content):
    return {"type": "assistant", "timestamp": ts, "message": {"id": mid, "role": "assistant", "content": content,
            "usage": {"input_tokens": 1, "cache_creation_input_tokens": 100, "cache_read_input_tokens": read, "output_tokens": out}}}
lines = [
    # 前日（JST 10/16 23:00）は数えない
    {"type": "user", "timestamp": "2026-10-16T14:00:00.000Z", "message": {"role": "user", "content": "前日の依頼"}},
    assistant("2026-10-16T14:00:05.000Z", "m0", 9000, 9, [{"type": "text", "text": "前日"}]),
    # 10/17 の依頼1。同じ id の返答は分割して記録されるので1回と数える
    {"type": "user", "timestamp": "2026-10-17T01:00:00.000Z", "message": {"role": "user", "content": "テストを直して"}},
    assistant("2026-10-17T01:00:05.000Z", "m1", 1000, 10, [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "swift test"}}]),
    assistant("2026-10-17T01:00:05.500Z", "m1", 1000, 10, [{"type": "text", "text": "実行します"}]),
    {"type": "user", "timestamp": "2026-10-17T01:00:09.000Z", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t1", "content": "x" * 4000}]}},
    assistant("2026-10-17T01:00:10.000Z", "m2", 3000, 20, [{"type": "text", "text": "直しました"}]),
    # 10/17 の依頼2
    {"type": "user", "timestamp": "2026-10-17T02:00:00.000Z", "message": {"role": "user", "content": "画面を見て"}},
    assistant("2026-10-17T02:00:05.000Z", "m3", 5000, 30, [{"type": "text", "text": "見ました"}]),
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
[[ "${out}" == *"返答 3 回"* ]] && check "同じ id は1回、前日は除いて3回" ok || check "同じ id は1回、前日は除いて3回" ng "${out}"
[[ "${out}" == *"キャッシュ読み込み 9.0k"* ]] && check "キャッシュ読み込みは 1000+3000+5000" ok || check "キャッシュ読み込みは 1000+3000+5000" ng "${out}"
[[ "${out}" == *"出力 60"* ]] && check "出力は 10+20+30" ok || check "出力は 10+20+30" ng "${out}"
[[ "${out}" == *"app"* && "${out}" == *"aaaaaaaa"* ]] && check "プロジェクトとセッションを出す" ok || check "プロジェクトとセッションを出す" ng "${out}"

out="$("${USAGE}" --since 2026-10-17 --by prompt 2>&1)"
[[ "${out}" == *"テストを直して"* && "${out}" == *"画面を見て"* && "${out}" != *"前日の依頼"* ]] \
  && check "--by prompt は期間内の依頼ごとに出す" ok || check "--by prompt は期間内の依頼ごとに出す" ng "${out}"

out="$("${USAGE}" --since 2026-10-17 --breakdown 2>&1)"
[[ "${out}" == *"Bashの出力"* ]] && check "--breakdown は読み直しの内訳を出す" ok || check "--breakdown は読み直しの内訳を出す" ng "${out}"

out="$("${USAGE}" --since 2026-10-18 2>&1)"
[[ "${out}" == *"返答 0 回"* ]] && check "期間に返答がなければ0回" ok || check "期間に返答がなければ0回" ng "${out}"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
