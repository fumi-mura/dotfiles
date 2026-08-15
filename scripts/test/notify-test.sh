#!/bin/bash
# notify.sh が通知種別ごとに正しい文言・音・画像を選び、呼び出しで待たされないかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
NOTIFY_SH="${ROOT_DIR}/shared/ai/hooks/notify.sh"
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

# 引数をログに記録する偽 terminal-notifier。DELAY で遅い通知も再現する
cat > "${WORK}/fake-notifier" <<FAKE
#!/bin/bash
sleep "\${FAKE_DELAY:-0}"
printf '%s\n' "\$*" >> "${WORK}/calls.log"
FAKE
chmod +x "${WORK}/fake-notifier"

run() {
  local type="$1" cwd="${2:-/tmp/sample-project}"
  : > "${WORK}/calls.log"
  printf '{"cwd":"%s","notification_type":"%s"}' "${cwd}" "${type}" |
    TERMINAL_NOTIFIER="${WORK}/fake-notifier" "${NOTIFY_SH}"
  local i=0
  while [[ ! -s "${WORK}/calls.log" && ${i} -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
  cat "${WORK}/calls.log"
}

field() {
  sed -n "s/.*-$2 \\([^ ]*\\).*/\\1/p" <<< "$1"
}

echo 'case 1: 許可待ち系はすべて音が鳴る'
for type in permission_prompt worker_permission_prompt agent_needs_input elicitation_response; do
  out="$(run "${type}")"
  [[ -n "$(field "${out}" sound)" ]] && r=ok || r=ng
  check "${type} に音がある" "${r}" "${out}"
done

echo 'case 2: 完了系'
for type in stop agent_completed; do
  out="$(run "${type}")"
  [[ "$(field "${out}" sound)" == "Glass" ]] && r=ok || r=ng
  check "${type} が Glass で鳴る" "${r}" "${out}"
done

echo 'case 3: 入力待ち'
out="$(run idle_prompt)"
[[ "$(field "${out}" sound)" == "Purr" ]] && r=ok || r=ng
check "idle_prompt が Purr で鳴る" "${r}" "${out}"

echo 'case 4: 未知の種別でも取りこぼさない'
out="$(run some_future_type)"
[[ -n "$(field "${out}" sound)" ]] && r=ok || r=ng
check "未知の種別にも音がある" "${r}" "${out}"

echo 'case 5: 情報系は無音のまま'
for type in computer_use_enter auth_success; do
  out="$(run "${type}")"
  [[ -z "$(field "${out}" sound)" ]] && r=ok || r=ng
  check "${type} は無音" "${r}" "${out}"
done

echo 'case 6: 空白を含むパス'
out="$(run stop "/tmp/my project")"
grep -q 'my project' <<< "${out}" && r=ok || r=ng
check "プロジェクト名が壊れない" "${r}" "${out}"

echo 'case 7: タイトルとロゴの切り替え'
out="$(run stop)"
grep -q -- '-title Claude Code' <<< "${out}" && r=ok || r=ng
check "既定は Claude Code" "${r}" "${out}"
grep -q -- '-contentImage .*claude\.png' <<< "${out}" && r=ok || r=ng
check "Claude のロゴを渡す" "${r}" "${out}"

out="$(NOTIFY_TITLE=Codex; export NOTIFY_TITLE; run stop)"
grep -q -- '-title Codex' <<< "${out}" && r=ok || r=ng
check "NOTIFY_TITLE で切り替わる" "${r}" "${out}"
grep -q -- '-contentImage .*codex\.png' <<< "${out}" && r=ok || r=ng
check "Codex のロゴを渡す" "${r}" "${out}"

echo 'case 8: ロゴ画像が存在する'
for f in claude codex; do
  [[ -s "${ROOT_DIR}/shared/ai/hooks/icons/${f}.png" ]] && r=ok || r=ng
  check "${f}.png がある" "${r}" "${ROOT_DIR}/shared/ai/hooks/icons/${f}.png"
done

echo 'case 9: 通知が遅くてもフックを止めない'
: > "${WORK}/calls.log"
start=$(date +%s)
printf '{"cwd":"/tmp/x","notification_type":"stop"}' |
  FAKE_DELAY=5 TERMINAL_NOTIFIER="${WORK}/fake-notifier" "${NOTIFY_SH}"
elapsed=$(($(date +%s) - start))
[[ "${elapsed}" -lt 2 ]] && r=ok || r=ng
check "5 秒かかる通知でも即座に返る (${elapsed}s)" "${r}" "${elapsed}s かかった"

echo 'case 10: terminal-notifier のパス'
grep -q '/opt/homebrew/bin/terminal-notifier' "${NOTIFY_SH}" && r=ok || r=ng
check "Homebrew のパスを既定にしている" "${r}" "$(grep -n 'NOTIFIER' "${NOTIFY_SH}" | head -2)"

if [[ "${failures}" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "${failures}"
  exit 1
fi

printf '\nAll tests passed\n'
