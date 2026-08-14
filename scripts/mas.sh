#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

APPS=(
  "937984704 Amphetamine"
  "424390742 Compressor"
  "424389933 Final Cut Pro"
  "682658836 GarageBand"
  "6447125648 Gestimer"
  "634148309 Logic Pro"
  "441258766 Magnet"
  "434290957 Motion"
  "1230394683 Photo Retouch"
  "6757801838 RunCat Neo"
)

main() {
  if ! command -v mas >/dev/null 2>&1; then
    error "mas is not installed. Run 'make brew' first."
    exit 1
  fi

  log "Install App Store applications"

  local failed_count=0
  local failed_list=""
  local app id name

  for app in "${APPS[@]}"; do
    id="${app%% *}"
    name="${app#* }"

    if ! mas install "${id}"; then
      warn "Failed to install ${name} (${id})"
      failed_count=$((failed_count + 1))
      failed_list="${failed_list}  - ${name} (${id})"$'\n'
    fi
  done

  if [[ "${failed_count}" -gt 0 ]]; then
    log "Failed to install ${failed_count} app(s)"
    printf '%s' "${failed_list}"
    printf '\nmas cannot install apps that have never been obtained with this Apple Account.\nGet them once from the App Store app, then run this again.\n'
    exit 1
  fi

  log "All App Store applications are installed"
}

main "$@"
