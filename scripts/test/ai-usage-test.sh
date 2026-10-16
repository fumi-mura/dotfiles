#!/bin/bash
# ai-usage が、AI の指定に応じて ai-usage-claude と ai-usage-codex に引数を渡し、指定がなければ両方を出すかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
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

# 入口だけを、受け取った引数を出す偽の集計スクリプトと並べて動かす
cp "${ROOT_DIR}/bin/ai-usage" "${WORK}/ai-usage" 2>/dev/null
printf '#!/bin/bash\necho "claude:$*"\n' >"${WORK}/ai-usage-claude"
printf '#!/bin/bash\necho "codex:$*"\n' >"${WORK}/ai-usage-codex"
chmod +x "${WORK}"/ai-usage*

out="$("${WORK}/ai-usage" claude --since 2026-10-17 2>&1)"
[[ "${out}" == "claude:--since 2026-10-17" ]] && check "claude を指定すると Claude だけ" ok || check "claude を指定すると Claude だけ" ng "${out}"

out="$("${WORK}/ai-usage" codex --by prompt 2>&1)"
[[ "${out}" == "codex:--by prompt" ]] && check "codex を指定すると Codex だけ" ok || check "codex を指定すると Codex だけ" ng "${out}"

out="$("${WORK}/ai-usage" --since 2026-10-17 2>&1)"
[[ "${out}" == *"claude:--since 2026-10-17"* && "${out}" == *"codex:--since 2026-10-17"* ]] \
  && check "指定しなければ両方" ok || check "指定しなければ両方" ng "${out}"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
