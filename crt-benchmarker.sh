#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$1" in
    init)      "$SCRIPT_DIR/scripts/init.sh" "${@:2}" ;;
    build)     "$SCRIPT_DIR/scripts/build.sh" "${@:2}" ;;
    clear)     "$SCRIPT_DIR/scripts/clear.sh" "${@:2}" ;;
    rebuild)   "$SCRIPT_DIR/scripts/rebuild.sh" "${@:2}" ;;
    workload)  "$SCRIPT_DIR/scripts/workload.sh" "${@:2}" ;;
    prep)      "$SCRIPT_DIR/scripts/prep.sh" "${@:2}" ;;
    test)      "$SCRIPT_DIR/scripts/test.sh" "${@:2}" ;;
    tmp-test)  "$SCRIPT_DIR/scripts/tmp-test.sh" "${@:2}" ;;
    bootstrap) "$SCRIPT_DIR/scripts/cdk.sh" bootstrap "${@:2}" ;;
    deploy)    "$SCRIPT_DIR/scripts/cdk.sh" deploy "${@:2}" ;;
    destroy)   "$SCRIPT_DIR/scripts/cdk.sh" destroy "${@:2}" ;;
    alias)     
        ALIAS_NAME="${2:-cb}"
        ALIAS_CMD="alias $ALIAS_NAME='$SCRIPT_DIR/crt-benchmarker.sh'"
        SHELL_CONFIG="${HOME}/.bashrc"
        [ -f "${HOME}/.zshrc" ] && SHELL_CONFIG="${HOME}/.zshrc"
        
        if grep -q "alias $ALIAS_NAME=" "$SHELL_CONFIG" 2>/dev/null; then
            echo "Alias '$ALIAS_NAME' already exists in $SHELL_CONFIG"
        else
            echo "$ALIAS_CMD" >> "$SHELL_CONFIG"
            echo "Added alias to $SHELL_CONFIG. instead of ./crt-benchmark.sh use $ALIAS_NAME from anywhere. You're welcome."
            echo "Run: source $SHELL_CONFIG"
        fi
        ;;
    *)         echo "Usage: ./crt-benchmarker.sh {init|build|clear|rebuild|workload|prep|test|tmp-test|bootstrap|deploy|destroy|alias} [args]" ;;
esac
