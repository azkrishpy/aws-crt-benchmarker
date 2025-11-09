#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CDK_DIR="$REPO_ROOT/cdk"
SETTINGS_FILE="$REPO_ROOT/.settings.json"

cd "$CDK_DIR"

# Check if settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: .settings.json not found in repo root"
    echo "Create it from the example:"
    echo "  cp cdk/example.settings.json .settings.json"
    echo "  # Edit .settings.json with your values"
    exit 1
fi

case "$1" in
    bootstrap)
        shift
        cdk bootstrap -c settings="$SETTINGS_FILE" "$@"
        ;;
    deploy)
        shift
        cdk deploy -c settings="$SETTINGS_FILE" "$@"
        ;;
    destroy)
        shift
        cdk destroy -c settings="$SETTINGS_FILE" "$@"
        ;;
    synth)
        shift
        cdk synth -c settings="$SETTINGS_FILE" "$@"
        ;;
    *)
        echo "Usage: cdk.sh {bootstrap|deploy|destroy|synth} [cdk-args]"
        exit 1
        ;;
esac
