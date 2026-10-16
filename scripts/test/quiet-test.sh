#!/bin/bash
# quiet が、長い出力を件数・エラー・末尾だけに絞り、全文をログに残し、終了コードをそのまま返すかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
QUIET="${ROOT_DIR}/bin/quiet"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export QUIET_LOG_DIR="${WORK}/logs"

failures=0

check() {
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n     -> %s\n' "$1" "$3"
  fi
}

# 成功: 500行の出力が短くなり、要約の行と末尾は残る
out="$("${QUIET}" bash -c 'for i in $(seq 1 500); do echo "compiling file $i"; done; echo "Executed 12 tests, with 0 failures"')"
status=$?
lines=$(printf '%s\n' "${out}" | wc -l | tr -d ' ')
[[ ${status} -eq 0 ]] && check "成功の終了コードは0" ok || check "成功の終了コードは0" ng "${status}"
[[ ${lines} -le 15 ]] && check "成功の出力は15行以内" ok || check "成功の出力は15行以内" ng "${lines}行"
[[ "${out}" == *"Executed 12 tests, with 0 failures"* ]] && check "テストの件数の行を残す" ok || check "テストの件数の行を残す" ng "${out}"
[[ "${out}" != *"compiling file 1"$'\n'* ]] && check "途中の行は出さない" ok || check "途中の行は出さない" ng "${out}"

log="$(printf '%s\n' "${out}" | sed -n 's/.*log: \(.*\)$/\1/p' | head -1)"
[[ -f "${log}" && $(wc -l <"${log}" | tr -d ' ') -ge 501 ]] && check "全文をログに残す" ok || check "全文をログに残す" ng "log=${log}"

# 失敗: 終了コードを返し、エラーの行を残す。とても長い行は切り詰め、色の制御文字は消す
long="$(printf 'x%.0s' $(seq 1 2000))"
out="$("${QUIET}" bash -c "for i in \$(seq 1 300); do echo noise \$i; done; printf '\033[31m/src/A.swift:28:10: error: no member cornerRadius\033[0m\n'; echo 'Failed frontend command: ${long}'; for i in \$(seq 1 300); do echo noise2 \$i; done; exit 3")"
status=$?
[[ ${status} -eq 3 ]] && check "失敗の終了コードを返す" ok || check "失敗の終了コードを返す" ng "${status}"
[[ "${out}" == *"/src/A.swift:28:10: error: no member cornerRadius"* ]] && check "エラーの行を残す" ok || check "エラーの行を残す" ng "${out}"
[[ "${out}" != *$'\033'* ]] && check "色の制御文字を消す" ok || check "色の制御文字を消す" ng "制御文字が残っている"
max=$(printf '%s\n' "${out}" | awk '{ if (length($0) > m) m = length($0) } END { print m }')
[[ ${max} -le 400 ]] && check "長い行を切り詰める" ok || check "長い行を切り詰める" ng "${max}文字"
total=$(printf '%s' "${out}" | wc -c | tr -d ' ')
[[ ${total} -le 4000 ]] && check "失敗の出力は4000文字以内" ok || check "失敗の出力は4000文字以内" ng "${total}文字"

# 短い出力はそのまま出す
out="$("${QUIET}" bash -c 'echo one; echo two')"
[[ "${out}" == *"one"* && "${out}" == *"two"* ]] && check "短い出力はそのまま出す" ok || check "短い出力はそのまま出す" ng "${out}"

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
