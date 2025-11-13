#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEAR_SCRIPT="$REPO_ROOT/scripts/clear.sh"
BUILD_SCRIPT="$REPO_ROOT/scripts/build.sh"
DEPS_SCRIPT="$REPO_ROOT/scripts/py/dependencies.py"

rebuild_component() {
    local component_type=$1
    local component_name=$2
    
    echo "=== Rebuilding $component_name ==="
    echo ""
    
    # Step 1: Clear the component and all its dependents
    echo "Step 1: Clearing $component_name and dependents..."
    "$CLEAR_SCRIPT" "$component_type" "$component_name"
    echo ""
    
    # Step 2: Build the component (with automatic dependency resolution)
    echo "Step 2: Building $component_name with dependencies..."
    "$BUILD_SCRIPT" "$component_type" "$component_name"
    echo ""
    
    # Step 3: Build all dependents
    echo "Step 3: Building dependents..."
    
    local normalized_name="$component_name"
    if [ "$component_type" = "runner" ] && [[ "$component_name" != runner-* ]]; then
        normalized_name="runner-s3-$component_name"
    fi
    
    local all_dependents=$(python3 "$DEPS_SCRIPT" all-dependents "$normalized_name")
    
    if [ -z "$all_dependents" ]; then
        echo "  No dependents to rebuild"
    else
        for dependent in $all_dependents; do
            echo "  Building dependent: $dependent"
            
            # Determine the type and name for the build command
            if [[ "$dependent" == runner-* ]]; then
                local runner_name=$(echo "$dependent" | sed 's/runner-s3-//')
                "$BUILD_SCRIPT" runner "$runner_name"
            elif [ "$dependent" = "aws-c-s3" ]; then
                "$BUILD_SCRIPT" client "$dependent"
            elif [ "$dependent" = "aws-s3-transfer-manager-rs" ]; then
                "$BUILD_SCRIPT" client rust
            else
                # C dependency
                "$BUILD_SCRIPT" client "$dependent"
            fi
        done
    fi
    
    echo ""
    echo "=== Rebuild complete! ==="
}

case "$1" in
    client|dependency|runner)
        if [ -z "$2" ]; then
            echo "Usage: rebuild.sh {client|dependency|runner} <name>"
            exit 1
        fi
        rebuild_component "$1" "$2"
        ;;
    *)
        echo "Usage: rebuild.sh {client|dependency|runner} <name>"
        echo ""
        echo "Examples:"
        echo "  rebuild.sh client aws-c-s3"
        echo "  rebuild.sh dependency aws-c-common"
        echo "  rebuild.sh runner c"
        exit 1
        ;;
esac
