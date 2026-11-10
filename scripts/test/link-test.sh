#!/bin/bash

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
LINK_SH="$(cd "${TEST_DIR}/.." && pwd)/link.sh"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "${TEST_HOME}"' EXIT
mkdir -p "${TEST_HOME}/.agents/skills/external-sample"
touch "${TEST_HOME}/.agents/skills/external-sample/SKILL.md"

HOME="${TEST_HOME}" /bin/bash "${LINK_SH}" >/dev/null || exit 1

REPO_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
for pair in \
  ".claude-team/settings.json:ai/claude/.claude/settings.json" \
  ".claude-team/CLAUDE.md:shared/ai/AGENTS.md" \
  ".claude-team/skills/dotfiles/SKILL.md:shared/ai/skills/dotfiles/SKILL.md"; do
  if [[ "$(readlink "${TEST_HOME}/${pair%%:*}")" != "${REPO_DIR}/${pair#*:}" ]]; then
    echo "FAIL ${pair%%:*} を ${pair#*:} にリンクしていない"
    exit 1
  fi
done
if [[ "$(readlink "${TEST_HOME}/.claude-team/skills/external-sample")" != "${TEST_HOME}/.agents/skills/external-sample" ]]; then
  echo 'FAIL 外から入れたスキルをチームアカウントにリンクしていない'
  exit 1
fi
echo 'ok チームアカウントにも Claude の設定・指示・スキルをリンクする'

zsh_inode="$(stat -f '%i' "${TEST_HOME}/.zshrc")"
skill_inode="$(stat -f '%i' "${TEST_HOME}/.codex/skills/dotfiles")"

HOME="${TEST_HOME}" /bin/bash "${LINK_SH}" >/dev/null || exit 1

if [[ "$(stat -f '%i' "${TEST_HOME}/.zshrc")" != "${zsh_inode}" ]]; then
  echo 'FAIL 既存の正しいファイルリンクを張り直した'
  exit 1
fi
if [[ "$(stat -f '%i' "${TEST_HOME}/.codex/skills/dotfiles")" != "${skill_inode}" ]]; then
  echo 'FAIL 既存の正しいスキルリンクを張り直した'
  exit 1
fi

rm "${TEST_HOME}/.codex/skills/dotfiles"
HOME="${TEST_HOME}" /bin/bash "${LINK_SH}" >/dev/null || exit 1
if [[ "$(readlink "${TEST_HOME}/.codex/skills/dotfiles")" != "$(cd "${TEST_DIR}/../.." && pwd)/shared/ai/skills/dotfiles" ]]; then
  echo 'FAIL 不足しているスキルリンクを作成できなかった'
  exit 1
fi

echo 'ok 既存リンクを維持し、不足したリンクを作成する'
