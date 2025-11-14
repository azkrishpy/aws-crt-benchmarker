#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# Load config if it exists
CONFIG_FILE="$REPO_ROOT/.crt-benchmarker.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Parse arguments
CLIENT1=""
CLIENT2=""
PAYLOAD=()
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c1|--client1) CLIENT1="$2"; shift 2 ;;
        -c2|--client2) CLIENT2="$2"; shift 2 ;;
        -p|--payload) 
            shift
            # Collect all payload arguments until we hit another flag
            while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; do
                PAYLOAD+=("$1")
                shift
            done
            ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        --throughput) THROUGHPUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required parameters
if [ -z "$CLIENT1" ] || [ -z "$CLIENT2" ]; then
    echo "Usage: compare.sh --client1/-c1 CLIENT1[:BRANCH] --client2/-c2 CLIENT2[:BRANCH] --payload/-p PAYLOAD... [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  compare.sh -c1 crt-c:main -c2 crt-c:test-branch -p upload-5GiB-10x"
    echo "  compare.sh -c1 boto3-crt -c2 crt-python:feature -p upload-1GiB-10x download-500MiB-5x"
    echo "  compare.sh -c1 crt-c:main -c2 rust-sdk:main -p payload.json"
    echo ""
    echo "Options:"
    echo "  -c1, --client1 CLIENT[:BRANCH]   First client to compare (branch defaults to main)"
    echo "  -c2, --client2 CLIENT[:BRANCH]   Second client to compare (branch defaults to main)"
    echo "  -p, --payload PAYLOAD...         Workload spec(s) or JSON file"
    echo "  -v, --verbose                    Show all logs (default: suppress, show only comparison)"
    echo "  --bucket BUCKET                  S3 bucket name (or set in config)"
    echo "  --region REGION                  AWS region (or set in config)"
    echo "  --throughput GBPS                Target throughput in Gbps (or set in config)"
    exit 1
fi

if [ ${#PAYLOAD[@]} -eq 0 ]; then
    echo "Error: --payload/-p is required"
    exit 1
fi

if [ -z "$BUCKET" ] || [ -z "$REGION" ] || [ -z "$THROUGHPUT" ]; then
    echo "Error: Missing required parameters (bucket, region, throughput)"
    echo "Set them in .crt-benchmarker.config or pass as arguments"
    exit 1
fi

# Function to get repo path for a client
# Returns the submodule path that needs branch checkout
get_client_repo() {
    local client=$1
    case "$client" in
        crt-c) echo "source/clients/aws-c-s3" ;;
        crt-python) echo "source/clients/aws-crt-python" ;;
        boto3-crt|boto3-classic) echo "source/clients/boto3" ;;
        cli-crt|cli-classic) echo "source/clients/aws-cli" ;;
        crt-java|sdk-java-client-crt|sdk-java-client-classic|sdk-java-tm-crt|sdk-java-tm-classic) 
            echo "source/clients/aws-crt-java" ;;
        rust|sdk-rust-tm) echo "source/clients/aws-s3-transfer-manager-rs" ;;
        *) echo ""; return 1 ;;
    esac
}

# Parse client:branch format
parse_client_spec() {
    local spec=$1
    if [[ "$spec" == *":"* ]]; then
        echo "${spec%%:*}" "${spec#*:}"
    else
        echo "$spec" "main"
    fi
}

# Parse client1 and client2
read CLIENT1_NAME CLIENT1_BRANCH <<< $(parse_client_spec "$CLIENT1")
read CLIENT2_NAME CLIENT2_BRANCH <<< $(parse_client_spec "$CLIENT2")

# Get repo paths
CLIENT1_REPO=$(get_client_repo "$CLIENT1_NAME")
CLIENT2_REPO=$(get_client_repo "$CLIENT2_NAME")

if [ -z "$CLIENT1_REPO" ]; then
    echo "Error: Unknown client: $CLIENT1_NAME"
    exit 1
fi

if [ -z "$CLIENT2_REPO" ]; then
    echo "Error: Unknown client: $CLIENT2_NAME"
    exit 1
fi

# Save current branches
CLIENT1_ORIGINAL_BRANCH=""
CLIENT2_ORIGINAL_BRANCH=""

if [ -d "$REPO_ROOT/$CLIENT1_REPO/.git" ]; then
    CLIENT1_ORIGINAL_BRANCH=$(cd "$REPO_ROOT/$CLIENT1_REPO" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

if [ -d "$REPO_ROOT/$CLIENT2_REPO/.git" ]; then
    CLIENT2_ORIGINAL_BRANCH=$(cd "$REPO_ROOT/$CLIENT2_REPO" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

# Cleanup function to restore branches
cleanup() {
    local exit_code=$?
    
    if [ -n "$CLIENT1_ORIGINAL_BRANCH" ] && [ -d "$REPO_ROOT/$CLIENT1_REPO/.git" ]; then
        if [ "$VERBOSE" = true ]; then
            echo "Restoring $CLIENT1_REPO to $CLIENT1_ORIGINAL_BRANCH..."
        fi
        cd "$REPO_ROOT/$CLIENT1_REPO" && git checkout "$CLIENT1_ORIGINAL_BRANCH" >/dev/null 2>&1 || true
    fi
    
    if [ -n "$CLIENT2_ORIGINAL_BRANCH" ] && [ -d "$REPO_ROOT/$CLIENT2_REPO/.git" ]; then
        if [ "$VERBOSE" = true ]; then
            echo "Restoring $CLIENT2_REPO to $CLIENT2_ORIGINAL_BRANCH..."
        fi
        cd "$REPO_ROOT/$CLIENT2_REPO" && git checkout "$CLIENT2_ORIGINAL_BRANCH" >/dev/null 2>&1 || true
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Call Python script to do the actual comparison
python3 "$SCRIPTS_DIR/py/compare.py" \
    --client1 "$CLIENT1_NAME" \
    --client1-branch "$CLIENT1_BRANCH" \
    --client1-repo "$CLIENT1_REPO" \
    --client2 "$CLIENT2_NAME" \
    --client2-branch "$CLIENT2_BRANCH" \
    --client2-repo "$CLIENT2_REPO" \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --throughput "$THROUGHPUT" \
    --verbose "$VERBOSE" \
    --payload "${PAYLOAD[@]}"
