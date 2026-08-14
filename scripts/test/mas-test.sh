#!/bin/bash
# mas.sh が失敗しても最後まで実行し、サマリを出すかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MAS_SH="$(cd "${TEST_DIR}/.." && pwd)/mas.sh"
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

# 指定した ID だけ失敗する偽 mas を用意する
make_fake_mas() {
  local fail_ids="$1"

  mkdir -p "${WORK}/bin"
  cat > "${WORK}/bin/mas" <<FAKE
#!/bin/bash
echo "\$2" >> "${WORK}/calls.log"
for id in ${fail_ids}; do
  if [[ "\$2" == "\${id}" ]]; then
    echo "Error: No downloads initiated for ADAM ID \$2" >&2
    exit 1
  fi
done
echo "Warning: Already installed (\$2)"
FAKE
  chmod +x "${WORK}/bin/mas"
  : > "${WORK}/calls.log"
}

run_mas() {
  PATH="${WORK}/bin:${PATH}" /bin/bash "${MAS_SH}" 2>&1
}

expected_ids="$(grep -vE '^[[:space:]]*#' "${MAS_SH}" | grep -oE '[0-9]{9,10}')"
expected_count="$(printf '%s\n' "${expected_ids}" | grep -c '[0-9]')"

echo "case 1: 途中で失敗しても最後まで実行する"
{
  fail_id="$(printf '%s\n' "${expected_ids}" | head -1)"
  make_fake_mas "${fail_id}"
  out="$(run_mas)"; code=$?
  called="$(grep -c '[0-9]' "${WORK}/calls.log")"

  [[ "${called}" == "${expected_count}" ]] \
    && check "全 ${expected_count} 件が実行される" ok \
    || check "全 ${expected_count} 件が実行される" ng "実行されたのは ${called} 件"
  [[ "${code}" -ne 0 ]] && check "失敗があれば非ゼロ終了" ok || check "失敗があれば非ゼロ終了" ng "exit ${code}"
  grep -qE "^[[:space:]]+- .*${fail_id}" <<< "${out}" \
    && check "サマリに失敗した ID が出る" ok || check "サマリに失敗した ID が出る" ng "${out}"
  grep -qiE 'failed' <<< "${out}" \
    && check "サマリに失敗の見出しが出る" ok || check "サマリに失敗の見出しが出る" ng "${out}"
}

echo "case 2: 複数失敗をすべて報告する"
{
  fail_ids="$(printf '%s\n' "${expected_ids}" | head -2 | tr '\n' ' ')"
  make_fake_mas "${fail_ids}"
  out="$(run_mas)"; code=$?
  reported=0
  for id in ${fail_ids}; do
    grep -qE "^[[:space:]]+- .*${id}" <<< "${out}" && reported=$((reported + 1))
  done

  [[ "${reported}" == 2 ]] && check "失敗した 2 件ともサマリに出る" ok || check "失敗した 2 件ともサマリに出る" ng "${out}"
  [[ "${code}" -ne 0 ]] && check "非ゼロ終了" ok || check "非ゼロ終了" ng "exit ${code}"
}

echo "case 3: 全部成功なら正常終了"
{
  make_fake_mas ""
  out="$(run_mas)"; code=$?

  [[ "${code}" -eq 0 ]] && check "exit 0" ok || check "exit 0" ng "exit ${code}"
  grep -qiE 'failed' <<< "${out}" && check "失敗サマリは出ない" ng "${out}" || check "失敗サマリは出ない" ok
}

echo "case 4: mas 未インストールなら従来どおり失敗"
{
  out="$(PATH="/usr/bin:/bin" /bin/bash "${MAS_SH}" 2>&1)"; code=$?

  [[ "${code}" -ne 0 ]] && check "非ゼロ終了" ok || check "非ゼロ終了" ng "exit ${code}"
  grep -q "mas is not installed" <<< "${out}" && check "案内メッセージが出る" ok || check "案内メッセージが出る" ng "${out}"
}

if [[ "${failures}" -eq 0 ]]; then
  printf '\nAll tests passed\n'
  exit 0
fi

printf '\n%d test(s) failed\n' "${failures}"
exit 1
