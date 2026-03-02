#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${ANSIBLE_RUNNER_MODE:-docker}"

if [[ "${MODE}" == "local" ]]; then
    cd "${REPO_ROOT}/ansible"
    exec uv run "$@"
fi

# Execute ansible-runner command using bash shell with login option
# runner user profile is loaded
CMD="docker exec -it ansible-runner \
     /bin/bash -lic"

# Execute docker run command
$CMD "$(printf ' %q' "$@")"