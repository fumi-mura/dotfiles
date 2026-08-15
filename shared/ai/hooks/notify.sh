#!/bin/bash

# rbenv の shim を拾うと Ruby の入れ替えで消えるため、Homebrew のパスを既定にする
NOTIFIER="${TERMINAL_NOTIFIER:-/opt/homebrew/bin/terminal-notifier}"
TITLE="${NOTIFY_TITLE:-Claude Code}"

# symlink 経由で呼ばれるので、実体の場所からロゴを引く
SCRIPT="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
case $TITLE in
  "Codex") icon="$(dirname "$SCRIPT")/icons/codex.png" ;;
  *) icon="$(dirname "$SCRIPT")/icons/claude.png" ;;
esac

input=$(cat)
cwd=$(jq -r '.cwd // ""' <<< "$input")
project=$(basename "${cwd:-unknown}")
notification_type=$(jq -r '.notification_type // ""' <<< "$input")

notify() {
  local args=(-title "$TITLE" -subtitle "$project" -message "$1" -sound "$2")
  [[ -s "$icon" ]] && args+=(-contentImage "$icon")

  # 通知が固まってもターンを止めないよう、待たずに投げる
  "$NOTIFIER" "${args[@]}" >/dev/null 2>&1 &
}

case $notification_type in
  "permission_prompt")
    notify "許可待ち" "Ping"
    ;;
  "worker_permission_prompt")
    notify "許可待ち (並列実行)" "Ping"
    ;;
  "agent_needs_input")
    notify "エージェントが入力待ち" "Ping"
    ;;
  "elicitation_response")
    notify "応答待ち" "Ping"
    ;;
  "idle_prompt")
    notify "入力待ち" "Purr"
    ;;
  "stop")
    notify "タスク完了" "Glass"
    ;;
  "agent_completed")
    notify "エージェント完了" "Glass"
    ;;
  "auth_success" | "computer_use_enter" | "computer_use_exit" | "elicitation_complete" | "push_notification")
    notify "$notification_type" ""
    ;;
  *)
    # 未知の種別を取りこぼさないよう、控えめな音を鳴らす
    notify "通知 ($notification_type)" "Tink"
    ;;
esac
