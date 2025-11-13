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
    "$CLEAR_SCRIPT" "--$component_type" "$component_name"
    echo ""
    
    # Step 2: Build the component (with automatic dependency resolution)
    echo "Step 2: Building $component_name with dependencies..."
    "$BUILD_SCRIPT" "--$component_type" "$component_name"
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
                "$BUILD_SCRIPT" --runner "$runner_name"
            elif [ "$dependent" = "aws-c-s3" ]; then
                "$BUILD_SCRIPT" --client "$dependent"
            elif [ "$dependent" = "aws-s3-transfer-manager-rs" ]; then
                "$BUILD_SCRIPT" --client rust
            else
                # C dependency
                "$BUILD_SCRIPT" --dep "$dependent"
            fi
        done
    fi
    
    echo ""
    echo "=== Rebuild complete! ==="
}

# Parse arguments
COMPONENT_TYPE=""
COMPONENT_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|-C|--client)
            COMPONENT_TYPE="client"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        -r|-R|--runner)
            COMPONENT_TYPE="runner"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        -d|-D|--dep)
            COMPONENT_TYPE="dep"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: rebuild.sh {--client/-c/-C <name> | --runner/-r/-R <name> | --dep/-d/-D <name>}"
            exit 1
            ;;
    esac
done

# Execute based on parsed arguments
if [ -z "$COMPONENT_TYPE" ] || [ -z "$COMPONENT_NAME" ]; then
    echo "Usage: rebuild.sh {--client/-c <name> | --runner/-r <name> | --dep/-d <name>}"
    echo ""
    echo "Examples:"
    echo "  rebuild.sh --client aws-c-s3"
    echo "  rebuild.sh --dep aws-c-common"
    echo "  rebuild.sh --runner c"
    exit 1
fi

rebuild_component "$COMPONENT_TYPE" "$COMPONENT_NAME"
