#!/bin/bash

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../lib.sh
source "${TEST_DIR}/../lib.sh"

main() {
  local failed_count=0
  local failed_list=""
  local test_path test_name

  while IFS= read -r test_path; do
    test_name="$(basename "${test_path}")"
    log "${test_name}"

    if ! "${test_path}"; then
      failed_count=$((failed_count + 1))
      failed_list="${failed_list}  - ${test_name}"$'\n'
    fi
  done < <(find "${TEST_DIR}" -maxdepth 1 -name '*-test.*' -type f | sort)

  if [[ "${failed_count}" -gt 0 ]]; then
    log "Failed ${failed_count} test file(s)"
    printf '%s' "${failed_list}"
    exit 1
  fi

  log "All test files passed"
}

main "$@"
