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
        --client) CLIENT="$2"; shift 2 ;;
        --workload) WORKLOAD="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        --throughput) THROUGHPUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$CLIENT" ] || [ -z "$WORKLOAD" ] || [ -z "$BUCKET" ] || [ -z "$REGION" ] || [ -z "$THROUGHPUT" ]; then
    echo "Usage: test.sh [--client CLIENT] [--workload WORKLOAD] [--bucket BUCKET] [--region REGION] [--throughput THROUGHPUT]"
    echo "Note: All options can be set in .crt-benchmarker.config"
    exit 1
fi

# If workload doesn't have a path, assume it's in workloads/run/
if [[ "$WORKLOAD" != *"/"* ]]; then
    WORKLOAD="$WORKLOADS_RUN_DIR/$WORKLOAD"
fi

# Convert to absolute path
WORKLOAD_PATH="$(cd "$(dirname "$WORKLOAD")" && pwd)/$(basename "$WORKLOAD")"

# Change to files directory
cd "$FILES_DIR"

# Print configuration being used
echo "Using configuration:"
echo "  CLIENT=$CLIENT"
echo "  WORKLOAD=$WORKLOAD"
echo "  BUCKET=$BUCKET"
echo "  REGION=$REGION"
echo "  THROUGHPUT=$THROUGHPUT"
echo ""

# Run the appropriate runner
case "$CLIENT" in
    crt-c)
        "$REPO_ROOT/install/bin/s3-c" "$CLIENT" "$WORKLOAD_PATH" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    crt-python|boto3-crt|boto3-classic|cli-crt|cli-classic)
        "$REPO_ROOT/install/python-venv/bin/python3" \
            "$REPO_ROOT/source/runners/s3-python/main.py" \
            "$CLIENT" "$WORKLOAD_PATH" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    crt-java|sdk-java-client-crt|sdk-java-client-classic|sdk-java-tm-crt|sdk-java-tm-classic)
        java -jar "$REPO_ROOT/source/runners/s3-java/target/s3-benchrunner-java-1.0-SNAPSHOT.jar" \
            "$CLIENT" "$WORKLOAD_PATH" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    sdk-rust-tm)
        AWS_REGION="$REGION" "$REPO_ROOT/source/runners/s3-rust/target/release/s3-benchrunner-rust" \
            "$CLIENT" "$WORKLOAD_PATH" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    *)
        echo "Unknown client: $CLIENT"
        echo "Supported clients:"
        echo "  C: crt-c"
        echo "  Python: crt-python, boto3-crt, boto3-classic, cli-crt, cli-classic"
        echo "  Java: crt-java, sdk-java-client-crt, sdk-java-client-classic, sdk-java-tm-crt, sdk-java-tm-classic"
        echo "  Rust: sdk-rust-tm"
        exit 1
        ;;
esac
