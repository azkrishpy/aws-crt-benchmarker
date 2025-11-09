#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$REPO_ROOT/files"
WORKLOADS_RUN_DIR="$REPO_ROOT/workloads/run"

# Load config if it exists
CONFIG_FILE="$REPO_ROOT/.crt-benchmarker.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Parse arguments (override config)
while [[ $# -gt 0 ]]; do
    case $1 in
        --workload) WORKLOAD="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$BUCKET" ] || [ -z "$REGION" ]; then
    echo "Usage: prep.sh [--workload {all|WORKLOAD}] [--bucket BUCKET] [--region REGION]"
    echo "Note: All options can be set in .crt-benchmarker.config"
    exit 1
fi

# Ensure files directory exists
mkdir -p "$FILES_DIR"

# Print configuration being used
echo "Using configuration:"
echo "  BUCKET=$BUCKET"
echo "  REGION=$REGION"
echo "  WORKLOAD=$WORKLOAD"
echo ""

if [ "$WORKLOAD" = "all" ]; then
    # Prep all workloads
    python3 "$REPO_ROOT/scripts/py/prep-s3-files.py" --bucket "$BUCKET" --region "$REGION" --files-dir "$FILES_DIR"
elif [ -n "$WORKLOAD" ]; then
    # Prep specific workload
    if [[ "$WORKLOAD" != *"/"* ]]; then
        WORKLOAD="$WORKLOADS_RUN_DIR/$WORKLOAD"
    fi
    python3 "$REPO_ROOT/scripts/py/prep-s3-files.py" --bucket "$BUCKET" --region "$REGION" --files-dir "$FILES_DIR" --workloads "$WORKLOAD"
else
    echo "Error: WORKLOAD not set. Set it in config or pass --workload"
    exit 1
fi

