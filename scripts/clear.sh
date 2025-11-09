#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$REPO_ROOT/install"
BUILD_DIR="$REPO_ROOT/build"

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
        rm -rf "$BUILD_DIR/$2"
        echo "Cleared $2 (you may need to rebuild dependents)"
        ;;
    *)
        echo "Usage: clear.sh {all|client <name>|dependency <name>|runner <name>}"
        exit 1
        ;;
esac
