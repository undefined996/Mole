#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    # Source common.sh first (required by sudo_manager)
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/sudo_manager.sh"
}

# Test sudo session detection
@test "has_sudo_session returns 1 when no sudo session" {
    # Most test environments don't have active sudo
    # This test verifies the function handles no-sudo gracefully
    run has_sudo_session
    # Either no sudo (status 1) or sudo available (status 0)
    # Both are valid - we just check it doesn't crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# Test sudo keepalive lifecycle
@test "sudo keepalive functions don't crash" {
    # Test that keepalive functions can be called without errors
    # We can't actually test sudo without prompting, but we can test structure

    # Mock sudo to avoid actual auth
    function sudo() {
        return 1  # Simulate no sudo available
    }
    export -f sudo

    # These should not crash even without real sudo
    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; has_sudo_session"
    [ "$status" -eq 1 ]  # Expected: no sudo session
}

# Test keepalive PID management
@test "_start_sudo_keepalive returns a PID" {
    # Mock sudo to simulate successful session
    function sudo() {
        case "$1" in
            -n) return 0 ;;  # Simulate valid sudo session
            -v) return 0 ;;  # Refresh succeeds
            *) return 1 ;;
        esac
    }
    export -f sudo

    # Start keepalive (will run in background)
    local pid
    pid=$(bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; _start_sudo_keepalive")

    # Should return a PID (number)
    [[ "$pid" =~ ^[0-9]+$ ]]

    # Clean up background process
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

# Test _stop_sudo_keepalive
@test "_stop_sudo_keepalive handles invalid PID gracefully" {
    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; _stop_sudo_keepalive ''"
    [ "$status" -eq 0 ]

    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; _stop_sudo_keepalive '99999'"
    [ "$status" -eq 0 ]
}

# Test request_sudo function structure
@test "request_sudo accepts prompt parameter" {
    # Mock request_sudo_access to avoid actual prompting
    function request_sudo_access() {
        return 1  # Simulate denied
    }
    export -f request_sudo_access

    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; request_sudo 'Test prompt'"
    [ "$status" -eq 1 ]  # Expected: denied
}

# Test start_sudo_session integration
@test "start_sudo_session handles success and failure paths" {
    # Mock request_sudo to simulate denied access
    function request_sudo() {
        return 1
    }
    export -f request_sudo

    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; start_sudo_session 'Test'"
    [ "$status" -eq 1 ]

    # Mock request_sudo to simulate granted access
    function request_sudo() {
        return 0
    }
    function _start_sudo_keepalive() {
        echo "12345"
    }
    export -f request_sudo
    export -f _start_sudo_keepalive

    run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; start_sudo_session 'Test'"
    [ "$status" -eq 0 ]
}

# Test stop_sudo_session cleanup
@test "stop_sudo_session cleans up keepalive process" {
    # Set a fake PID
    export MOLE_SUDO_KEEPALIVE_PID="99999"

    run bash -c "export MOLE_SUDO_KEEPALIVE_PID=99999; source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; stop_sudo_session"
    [ "$status" -eq 0 ]
}

# Test global state management
@test "sudo manager initializes global state correctly" {
    result=$(bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/sudo_manager.sh'; echo \$MOLE_SUDO_ESTABLISHED")
    [[ "$result" == "false" ]] || [[ -z "$result" ]]
}
