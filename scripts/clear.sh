#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$REPO_ROOT/install"
BUILD_DIR="$REPO_ROOT/build"
DEPS_SCRIPT="$REPO_ROOT/scripts/py/dependencies.py"

# Clear a single component's build artifacts
clear_single_component() {
    local component=$1
    
    echo "Clearing $component..."
    
    # Clear build directory
    rm -rf "$BUILD_DIR/$component"
    
    # Clear install artifacts for C libraries
    if [ -d "$INSTALL_DIR/lib/cmake/$component" ]; then
        rm -rf "$INSTALL_DIR/lib/cmake/$component"
    fi
    
    # Clear library files
    if [ -f "$INSTALL_DIR/lib/lib${component}.a" ]; then
        rm -f "$INSTALL_DIR/lib/lib${component}.a"
    fi
    
    # Clear header files
    local header_name=$(echo "$component" | sed 's/aws-//')
    if [ -d "$INSTALL_DIR/include/aws/$header_name" ]; then
        rm -rf "$INSTALL_DIR/include/aws/$header_name"
    fi
    
    # Special handling for runners
    if [[ "$component" == runner-* ]]; then
        local runner_name=$(echo "$component" | sed 's/runner-s3-//')
        rm -rf "$BUILD_DIR/runner-s3-$runner_name"
        
        # Clear runner binary
        if [ -f "$INSTALL_DIR/bin/s3-$runner_name-runner" ]; then
            rm -f "$INSTALL_DIR/bin/s3-$runner_name-runner"
        fi
    fi
    
    # Special handling for Rust
    if [ "$component" = "aws-s3-transfer-manager-rs" ]; then
        rm -rf "$REPO_ROOT/source/clients/$component/target"
    fi
    
    if [ "$component" = "runner-s3-rust" ]; then
        rm -rf "$REPO_ROOT/source/runners/s3-rust/target"
    fi
}

# Clear a component and all its dependents
clear_with_dependents() {
    local component=$1
    
    echo "Resolving dependents for $component..."
    local all_dependents=$(python3 "$DEPS_SCRIPT" all-dependents "$component")
    
    # Clear dependents first (top-down)
    for dependent in $all_dependents; do
        echo "  Clearing dependent: $dependent"
        clear_single_component "$dependent"
    done
    
    # Then clear the component itself
    clear_single_component "$component"
}

case "$1" in
    all)
        rm -rf "$BUILD_DIR" "$INSTALL_DIR"
        echo "Cleared all build and install directories"
        ;;
    client|dependency|runner)
        if [ -z "$2" ]; then
            echo "Usage: clear.sh {client|dependency|runner} <name>"
            exit 1
        fi
        
        local component="$2"
        
        # Normalize runner names
        if [ "$1" = "runner" ] && [[ "$component" != runner-* ]]; then
            component="runner-s3-$component"
        fi
        
        # Clear with automatic dependent resolution
        clear_with_dependents "$component"
        echo "Cleared $component and all its dependents"
        ;;
    *)
        echo "Usage: clear.sh {all|client <name>|dependency <name>|runner <name>}"
        exit 1
        ;;
esac
