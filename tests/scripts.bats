#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-scripts-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    export TERM="dumb"
    rm -rf "${HOME:?}"/*
    mkdir -p "$HOME"
}

@test "format.sh --check validates script formatting" {
    if ! command -v shfmt > /dev/null 2>&1; then
        skip "shfmt not installed"
    fi

    run "$PROJECT_ROOT/scripts/format.sh" --check
    # May pass or fail depending on formatting, but should not error
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "format.sh --help shows usage information" {
    run "$PROJECT_ROOT/scripts/format.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "check.sh runs all quality checks" {
    run "$PROJECT_ROOT/scripts/check.sh"
    # May pass or fail, but should complete
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" == *"Quality Checks"* ]]
}

@test "build-analyze.sh detects missing Go toolchain" {
    if command -v go > /dev/null 2>&1; then
        skip "Go is installed, cannot test missing toolchain"
    fi

    run "$PROJECT_ROOT/scripts/build-analyze.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Go not installed"* ]]
}

@test "build-analyze.sh shows version and build time" {
    if ! command -v go > /dev/null 2>&1; then
        skip "Go not installed"
    fi

    run "$PROJECT_ROOT/scripts/build-analyze.sh"
    [[ "$output" == *"Version:"* ]]
    [[ "$output" == *"Build time:"* ]]
}

@test "setup-quick-launchers.sh detects mole binary" {
    # Create a fake mole binary
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/mole" << 'EOF'
#!/bin/bash
echo "fake mole"
EOF
    chmod +x "$HOME/.local/bin/mole"

    run env HOME="$HOME" PATH="$HOME/.local/bin:$PATH" "$PROJECT_ROOT/scripts/setup-quick-launchers.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected Mole binary"* ]]
}

@test "setup-quick-launchers.sh creates Raycast scripts" {
    if [[ ! -d "$HOME/Library/Application Support/Raycast" ]]; then
        mkdir -p "$HOME/Library/Application Support/Raycast/script-commands"
    fi

    # Create a fake mole binary
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/mole" << 'EOF'
#!/bin/bash
echo "fake mole"
EOF
    chmod +x "$HOME/.local/bin/mole"

    run env HOME="$HOME" PATH="$HOME/.local/bin:$PATH" "$PROJECT_ROOT/scripts/setup-quick-launchers.sh"
    [ "$status" -eq 0 ]

    # Check if scripts were created
    [[ -f "$HOME/Library/Application Support/Raycast/script-commands/mole-clean.sh" ]] || \
    [[ -f "$HOME/Documents/Raycast/Scripts/mole-clean.sh" ]]
}
