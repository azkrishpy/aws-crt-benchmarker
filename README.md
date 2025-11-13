# CRT Benchmarker

A streamlined tool for benchmarking S3 clients across multiple languages (C, Python, Java, Rust).

## Quick Start

### 1. Clone and Initialize

```bash
git clone <your-repo-url>
cd crt-benchmarker
git submodule update --init --recursive
./crt-benchmarker.sh init
```

The init script installs system dependencies and sets up the `cb` alias.

Add the alias to your shell:

```bash
# The init script will print the exact command, something like:
alias cb='/path/to/crt-benchmarker.sh'
```

### 2. Configure Defaults

```bash
cp .crt-benchmarker.config.example .crt-benchmarker.config
# Edit .crt-benchmarker.config with your bucket, region, etc.
```

### 3. Build Everything

```bash
cb build all
```

This builds:
- C dependencies and runners
- Python clients (boto3, awscli, aws-crt-python)
- Java clients (aws-crt-java, aws-sdk-java-v2)
- Rust clients (aws-s3-transfer-manager-rs)

### 4. Generate Workloads

```bash
cb workload build
```

This converts `.src.json` files in `workloads/src/` to `.run.json` files in `workloads/run/`.

### 5. Prepare Files

```bash
cb prep all
```

This creates local files for uploads and uploads files to S3 for downloads.

### 6. Run Benchmarks

```bash
cb test
```

Uses defaults from `.crt-benchmarker.config`. Or override:

```bash
cb test --client boto3-crt --workload download-5GiB-1x.json
```

## Commands

### Build Commands

```bash
cb build all                    # Build everything (prompts for confirmation)
cb build all -f                 # Build everything (skip confirmation)
cb build --client aws-c-s3      # Build specific C client
cb build -c python              # Build Python clients
cb build -c java                # Build Java clients
cb build -c rust                # Build Rust clients
cb build --dep aws-c-common     # Build specific C dependency
cb build -d aws-c-io            # Build specific C dependency (short flag)
cb build --runner c             # Build C runner
cb build -r python              # Build Python runner
cb build -r java                # Build Java runner
cb build -r rust                # Build Rust runner
```

### Clear Commands

```bash
cb clear all                    # Delete all build artifacts
cb clear --client aws-c-s3      # Clear specific client
cb clear -c python              # Clear Python client
cb clear --dep aws-c-common     # Clear specific dependency
cb clear -d aws-c-io            # Clear specific dependency (short flag)
cb clear --runner c             # Clear specific runner
cb clear -r python              # Clear Python runner
```

### Rebuild Commands

```bash
cb rebuild --client aws-c-s3    # Rebuild client and all dependents
cb rebuild -c python            # Rebuild Python client
cb rebuild --dep aws-c-common   # Rebuild dependency and all dependents
cb rebuild -d aws-c-io          # Rebuild dependency (short flag)
cb rebuild --runner c           # Rebuild runner and dependencies
cb rebuild -r python            # Rebuild Python runner
```

### Workload Commands

```bash
cb workload build               # Build all workloads
cb workload build upload-5GiB-1x.json  # Build specific workload (automatically checks workloads/src)
```

### Prep Commands

```bash
cb prep all                     # Prep all workloads
cb prep upload-5GiB-1x.json     # Prep specific workload
cb prep --workload all --bucket my-bucket --region us-west-2  # Override config
```

### Test Commands

```bash
cb test                         # Use defaults from config
cb test --client crt-c          # Override client
cb test --workload upload-5GiB-1x.json --bucket my-bucket  # Override multiple
```

### Tmp-Test Commands

Quick one-shot testing without creating workload files:

```bash
cb tmp-test upload-15MiB-1x.json                    # Quick test with defaults
cb tmp-test download-5GiB-10x.json --client crt-c   # Override client
cb tmp-test upload-256KiB-10_000x.json              # Many small files
cb tmp-test upload-30GiB-1x-ram.json                # In-memory test
```

Naming convention: `{action}-{size}-{count}x[-ram].json`
- `action`: upload or download
- `size`: e.g., 5GiB, 256KiB, 15MiB
- `count`: number of files (use underscores for thousands: 10_000x)
- `-ram`: optional suffix for in-memory files

This skips creating files in `workloads/src/` and running `cb workload build`. Files are prepped in `files/` and remain for inspection.

### CDK Commands

```bash
# First time setup
cp cdk/example.settings.json .settings.json
# Edit .settings.json with your AWS account, region, etc.

cb bootstrap                    # Bootstrap CDK (one-time)
cb deploy                       # Deploy infrastructure
cb destroy                      # Destroy infrastructure
```

## Supported S3 Clients

### C
- `crt-c` - aws-c-s3

### Python
- `crt-python` - aws-crt-python
- `boto3-crt` - boto3 with CRT
- `boto3-classic` - boto3 with pure-python transfer manager
- `cli-crt` - AWS CLI with CRT
- `cli-classic` - AWS CLI with pure-python transfer manager

### Java
- `crt-java` - aws-crt-java
- `sdk-java-client-crt` - AWS SDK Java v2 S3AsyncClient with CRT
- `sdk-java-client-classic` - AWS SDK Java v2 S3AsyncClient pure-java
- `sdk-java-tm-crt` - AWS SDK Java v2 S3TransferManager with CRT
- `sdk-java-tm-classic` - AWS SDK Java v2 S3TransferManager pure-java

### Rust
- `sdk-rust-tm` - aws-s3-transfer-manager-rs

## Directory Structure

```
crt-benchmarker/
├── crt-benchmarker.sh          # Main entry point
├── scripts/                    # Shell scripts for each command
│   ├── build.sh
│   ├── test.sh
│   ├── prep.sh
│   └── py/                     # Python utilities
├── source/
│   ├── dependencies/           # C dependencies (submodules)
│   ├── clients/                # S3 clients (submodules)
│   └── runners/                # Benchmark runners
├── workloads/
│   ├── src/                    # Human-readable workload definitions
│   └── run/                    # Generated workload files (gitignored)
├── build/                      # Build artifacts (gitignored)
├── install/                    # Installed binaries and libraries (gitignored)
├── files/                      # Workload files for benchmarks (gitignored)
└── cdk/                        # AWS CDK infrastructure
```

## Configuration

`.crt-benchmarker.config` sets defaults:

bash
BUCKET=my-benchmark-bucket
REGION=us-west-2
THROUGHPUT=100.0
CLIENT=crt-c
WORKLOAD=upload-5GiB-1x.json

All commands respect these defaults but allow CLI overrides.

## Creating New Workloads

Create a `.json` file in `workloads/src/`:

json
{
   "action": "upload",
   "fileSize": "10GiB",
   "numFiles": 5,
   "filesOnDisk": true,
   "checksum": null,
   "maxRepeatCount": 10,
   "maxRepeatSecs": 600
}

Then build it:
```bash
cb workload build
```
