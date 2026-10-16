#!/bin/bash
# japanese-reply.py が、英語の返答だけを差し戻し、日本語や短い返答、2回目の停止は通すかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
HOOK="${ROOT_DIR}/shared/ai/hooks/japanese-reply.py"
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

# 最後のアシスタントの文章が $1 の transcript を作り、フックの出力を返す
run() {
  local text="$1" active="${2:-false}"
  python3 - "${WORK}/transcript.jsonl" "${text}" <<'PY'
import json, sys
path, text = sys.argv[1], sys.argv[2]
lines = [
    {"type": "user", "message": {"role": "user", "content": "ツールバーを直して"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}},
]
with open(path, "w") as f:
    for line in lines:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")
PY
  printf '{"transcript_path":"%s","stop_hook_active":%s}' "${WORK}/transcript.jsonl" "${active}" | python3 "${HOOK}"
}

english="I tried it, but the template still merges into the undo and redo frame even with a fixed spacer. I reverted the change and restarted Studio."
japanese="試しましたが、固定スペーサーを置いてもテンプレートは取り消し・やり直しの枠にまとまりました。変更を戻して Studio を再起動しています。"
japanese_with_code=$'テンプレートだけ高さを指定しています。\n\n```swift\nButton { workspace.isTemplatePickerPresented = true } label: { Label("Template", systemImage: "square.grid.2x2") }\n    .buttonStyle(.glass)\n    .frame(height: 16)\n```\n\n`EditorShell.swift` の204行目です。'

out="$(run "${english}")"
if [[ "${out}" == *'"decision": "block"'* ]]; then check "英語の返答は差し戻す" ok; else check "英語の返答は差し戻す" ng "${out}"; fi

out="$(run "${japanese}")"
if [[ -z "${out}" ]]; then check "日本語の返答は通す" ok; else check "日本語の返答は通す" ng "${out}"; fi

out="$(run "${japanese_with_code}")"
if [[ -z "${out}" ]]; then check "コードを含む日本語の返答は通す" ok; else check "コードを含む日本語の返答は通す" ng "${out}"; fi

out="$(run "OK, done.")"
if [[ -z "${out}" ]]; then check "短い返答は通す" ok; else check "短い返答は通す" ng "${out}"; fi

out="$(run "${english}" true)"
if [[ -z "${out}" ]]; then check "差し戻し後の停止は通す" ok; else check "差し戻し後の停止は通す" ng "${out}"; fi

out="$(printf '{"transcript_path":"%s/missing.jsonl","stop_hook_active":false}' "${WORK}" | python3 "${HOOK}"; echo "exit=$?")"
if [[ "${out}" == "exit=0" ]]; then check "transcript がなくても止めない" ok; else check "transcript がなくても止めない" ng "${out}"; fi

exit $(( failures > 0 ))
