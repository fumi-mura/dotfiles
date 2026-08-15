#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

link_file() {
  local source_path="$1"
  local target_path="$2"

  ensure_directory "$(dirname "${target_path}")"
  ln -fnsv "${source_path}" "${target_path}"
}

link_tree() {
  local source_root="$1"
  local target_root="$2"
  local source_path rel_path target_path

  while IFS= read -r -d '' source_path; do
    rel_path="${source_path#"${source_root}/"}"
    target_path="${target_root}/${rel_path}"
    link_file "${source_path}" "${target_path}"
  done < <(find "${source_root}" -type f -print0)
}

link_directory_tree() {
  local source_root="$1"
  local target_root="$2"
  local source_path rel_path target_path

  ensure_directory "${target_root}"

  # Codex only detects shared skills reliably when each skill directory is symlinked.
  while IFS= read -r -d '' source_path; do
    rel_path="${source_path#"${source_root}/"}"
    target_path="${target_root}/${rel_path}"
    rm -rf "${target_path}"
    ln -snfv "${source_path}" "${target_path}"
  done < <(find "${source_root}" -mindepth 1 -maxdepth 1 -type d -print0)
}

main() {
  log "Link zsh"
  link_tree "${ROOT_DIR}/zsh" "${HOME}"

  log "Link git"
  link_tree "${ROOT_DIR}/git" "${HOME}"

  log "Link karabiner"
  link_tree "${ROOT_DIR}/karabiner" "${HOME}"

  log "Link Claude settings"
  link_tree "${ROOT_DIR}/ai/claude" "${HOME}"
  link_file "${ROOT_DIR}/shared/ai/AGENTS.md" "${HOME}/.claude/CLAUDE.md"
  link_tree "${ROOT_DIR}/shared/ai/skills" "${HOME}/.claude/skills"
  link_file "${ROOT_DIR}/shared/ai/hooks/notify.sh" "${HOME}/.claude/hooks/notify.sh"

  log "Link Codex settings"
  link_tree "${ROOT_DIR}/ai/codex" "${HOME}"
  link_file "${ROOT_DIR}/shared/ai/AGENTS.md" "${HOME}/.codex/AGENTS.md"
  link_directory_tree "${ROOT_DIR}/shared/ai/skills" "${HOME}/.codex/skills"
  link_file "${ROOT_DIR}/shared/ai/hooks/notify.sh" "${HOME}/.codex/hooks/notify.sh"

  log "Link Gemini settings"
  link_tree "${ROOT_DIR}/ai/gemini" "${HOME}"
  link_file "${ROOT_DIR}/shared/ai/AGENTS.md" "${HOME}/.gemini/GEMINI.md"
  link_tree "${ROOT_DIR}/shared/ai/skills" "${HOME}/.gemini/skills"
}

main "$@"
