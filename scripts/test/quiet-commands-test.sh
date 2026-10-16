#!/bin/bash
# quiet-commands.py が、テストとビルドのコマンドだけを quiet 経由に書き換え、自分で絞っているコマンドや他のコマンドはそのまま通すかを検証する

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
HOOK="${ROOT_DIR}/shared/ai/hooks/quiet-commands.py"

failures=0

# コマンドを渡し、書き換え後のコマンドを返す。書き換えないときは空
rewrite() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$1" \
    | python3 "${HOOK}" \
    | python3 -c 'import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)["hookSpecificOutput"]["updatedInput"]["command"] if d else "")'
}

expect_rewritten() {
  local result
  result="$(rewrite "$1")"
  if [[ "${result}" == *"/.local/bin/quiet "* && "${result}" == *"$2"* ]]; then
    printf '  ok   書き換える: %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL 書き換える: %s\n     -> %s\n' "$1" "${result}"
  fi
}

expect_untouched() {
  local result
  result="$(rewrite "$1")"
  if [[ -z "${result}" ]]; then
    printf '  ok   そのまま: %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL そのまま: %s\n     -> %s\n' "$1" "${result}"
  fi
}

expect_rewritten "swift test" "swift test"
expect_rewritten "swift test --filter LoupeGeometryTests" "--filter LoupeGeometryTests"
expect_rewritten "swift build" "swift build"
expect_rewritten "cd /tmp/app && swift test" "cd /tmp/app && swift test"
expect_rewritten "xcodebuild -scheme App -destination 'id=1' build" "xcodebuild"
expect_rewritten "npm test" "npm test"
expect_rewritten "npm run build" "npm run build"
expect_rewritten "pnpm test" "pnpm test"
expect_rewritten "pytest -q tests" "pytest"
expect_rewritten "cargo test" "cargo test"
expect_rewritten "make test" "make test"

expect_untouched "swift test 2>&1 | grep -E 'error|Executed'"
expect_untouched "swift test > /tmp/out.log"
expect_untouched "ls -la"
expect_untouched "git commit -m 'swift test を直す'"
expect_untouched "~/.local/bin/quiet swift test"
expect_untouched "swift run asc-screenshots generate"

# Bash 以外のツールは見ない
result="$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}' | python3 "${HOOK}")"
if [[ -z "${result}" ]]; then
  printf '  ok   Bash 以外は何も返さない\n'
else
  failures=$((failures + 1))
  printf '  FAIL Bash 以外は何も返さない\n     -> %s\n' "${result}"
fi

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi
