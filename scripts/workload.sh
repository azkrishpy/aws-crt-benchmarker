#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$1" in
    build)
        # Ensure run directory exists
        mkdir -p "$REPO_ROOT/workloads/run"
        
        if [ -z "$2" ]; then
            python3 "$REPO_ROOT/scripts/py/build-workloads.py"
        else
            python3 "$REPO_ROOT/scripts/py/build-workloads.py" "$REPO_ROOT/workloads/src/$2"
        fi
        ;;
    *)
        echo "Usage: workload.sh build [src-file]"
        exit 1
        ;;
esac
