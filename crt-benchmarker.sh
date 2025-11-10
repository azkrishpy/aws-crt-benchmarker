#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$1" in
    init)      "$SCRIPT_DIR/scripts/init.sh" "${@:2}" ;;
    build)     "$SCRIPT_DIR/scripts/build.sh" "${@:2}" ;;
    clear)     "$SCRIPT_DIR/scripts/clear.sh" "${@:2}" ;;
    workload)  "$SCRIPT_DIR/scripts/workload.sh" "${@:2}" ;;
    prep)      "$SCRIPT_DIR/scripts/prep.sh" "${@:2}" ;;
    test)      "$SCRIPT_DIR/scripts/test.sh" "${@:2}" ;;
    tmp-test)  "$SCRIPT_DIR/scripts/tmp-test.sh" "${@:2}" ;;
    bootstrap) "$SCRIPT_DIR/scripts/cdk.sh" bootstrap "${@:2}" ;;
    deploy)    "$SCRIPT_DIR/scripts/cdk.sh" deploy "${@:2}" ;;
    destroy)   "$SCRIPT_DIR/scripts/cdk.sh" destroy "${@:2}" ;;
    *)         echo "Usage: ./crt-benchmarker.sh {init|build|clear|workload|prep|test|tmp-test|bootstrap|deploy|destroy} [args]" ;;
esac
