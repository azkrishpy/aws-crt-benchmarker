#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$REPO_ROOT/files"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# Load config if it exists
CONFIG_FILE="$REPO_ROOT/.crt-benchmarker.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# First arg is the workload filename
WORKLOAD_NAME="$1"
shift

# Parse remaining arguments (override config)
while [[ $# -gt 0 ]]; do
    case $1 in
        --client) CLIENT="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        --throughput) THROUGHPUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required parameters
if [ -z "$WORKLOAD_NAME" ]; then
    echo "Usage: auto-test.sh WORKLOAD_NAME [OPTIONS]"
    echo ""
    echo "Example: auto-test.sh upload-15MiB-1x.json"
    echo ""
    echo "Workload naming convention: {action}-{size}-{count}x[-ram].json"
    echo "  action: upload or download"
    echo "  size: e.g., 5GiB, 256KiB, 15MiB"
    echo "  count: number of files (use underscores for thousands: 10_000x)"
    echo "  -ram: optional suffix for in-memory files"
    echo ""
    echo "Options (or set in .crt-benchmarker.config):"
    echo "  --client CLIENT               S3 client to use"
    echo "  --bucket BUCKET               S3 bucket name"
    echo "  --region REGION               AWS region"
    echo "  --throughput GBPS             Target throughput in Gbps"
    exit 1
fi

if [ -z "$CLIENT" ] || [ -z "$BUCKET" ] || [ -z "$REGION" ] || [ -z "$THROUGHPUT" ]; then
    echo "Error: Missing required test parameters (client, bucket, region, throughput)"
    echo "Set them in .crt-benchmarker.config or pass as arguments"
    exit 1
fi

# Generate temporary workload file
TMP_WORKLOAD="/tmp/tmp-workload-$$.json"

echo "Parsing workload name: $WORKLOAD_NAME"
python3 "$SCRIPTS_DIR/py/generate-tmp-workload.py" \
    --filename "$WORKLOAD_NAME" \
    --output "$TMP_WORKLOAD"

echo ""

# Prep the workload
echo "Preparing files..."
mkdir -p "$FILES_DIR"
python3 "$SCRIPTS_DIR/py/prep-s3-files.py" \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --files-dir "$FILES_DIR" \
    --workloads "$TMP_WORKLOAD"
echo ""

# Run the test
echo "Running test..."
cd "$FILES_DIR"

case "$CLIENT" in
    crt-c|c)
        "$REPO_ROOT/install/bin/s3-c" "crt-c" "$TMP_WORKLOAD" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    crt-python|boto3-crt|boto3-classic|cli-crt|cli-classic)
        "$REPO_ROOT/install/python-venv/bin/python3" \
            "$REPO_ROOT/source/runners/s3-python/main.py" \
            "$CLIENT" "$TMP_WORKLOAD" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    crt-java|sdk-java-client-crt|sdk-java-client-classic|sdk-java-tm-crt|sdk-java-tm-classic)
        java -jar "$REPO_ROOT/source/runners/s3-java/target/s3-benchrunner-java-1.0-SNAPSHOT.jar" \
            "$CLIENT" "$TMP_WORKLOAD" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    sdk-rust-tm|rust)
        AWS_REGION="$REGION" "$REPO_ROOT/source/runners/s3-rust/target/release/s3-benchrunner-rust" \
            "sdk-rust-tm" "$TMP_WORKLOAD" "$BUCKET" "$REGION" "$THROUGHPUT"
        ;;
    *)
        echo "Unknown client: $CLIENT"
        echo "Supported clients:"
        echo "  C: crt-c"
        echo "  Python: crt-python, boto3-crt, boto3-classic, cli-crt, cli-classic"
        echo "  Java: crt-java, sdk-java-client-crt, sdk-java-client-classic, sdk-java-tm-crt, sdk-java-tm-classic"
        echo "  Rust: sdk-rust-tm"
        rm -f "$TMP_WORKLOAD"
        exit 1
        ;;
esac

# Clean up temporary workload file
rm -f "$TMP_WORKLOAD"
echo ""
echo "Test complete. Files remain in $FILES_DIR for inspection."
