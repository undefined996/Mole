#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "run_with_timeout succeeds without GNU timeout" {
    run bash --noprofile --norc -c '
        set -euo pipefail
        PATH="/usr/bin:/bin"
        source "'"$PROJECT_ROOT"'/lib/common.sh"
        run_with_timeout 1 sleep 0.1
    '
    [ "$status" -eq 0 ]
}

@test "run_with_timeout enforces timeout and returns 124" {
    run bash --noprofile --norc -c '
        set -euo pipefail
        PATH="/usr/bin:/bin"
        source "'"$PROJECT_ROOT"'/lib/common.sh"
        run_with_timeout 1 sleep 5
    '
    [ "$status" -eq 124 ]
}
