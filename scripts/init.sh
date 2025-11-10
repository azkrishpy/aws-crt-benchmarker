#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ""
echo "To use 'cb' command from anywhere, add this alias to your shell config:"
echo ""
echo "  alias cb='$REPO_ROOT/crt-benchmarker.sh'"
echo ""
echo "Run this to add it automatically:"
echo "  echo \"alias cb='$REPO_ROOT/crt-benchmarker.sh'\" >> ~/.bashrc"
echo "  source ~/.bashrc"
echo ""

echo "Installing system dependencies..."

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Check if Amazon Linux
    if [ -f /etc/os-release ] && grep -q "Amazon Linux" /etc/os-release; then
        echo "Detected Amazon Linux"
        sudo yum update -y
        sudo yum install -y \
            cmake3 \
            gcc \
            gcc-c++ \
            git \
            python3 \
            python3-devel \
            python3-pip \
            java-17-amazon-corretto-devel \
            maven \
            curl
        
        # Symlink cmake3 to cmake if needed
        if ! command -v cmake &> /dev/null; then
            sudo ln -s /usr/bin/cmake3 /usr/bin/cmake
        fi
    else
        echo "Detected Linux (assuming Ubuntu/Debian)"
        sudo apt-get update
        sudo apt-get install -y \
            cmake \
            gcc \
            g++ \
            git \
            python3 \
            python3-dev \
            python3-pip \
            openjdk-17-jdk \
            maven \
            curl
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found. Install from https://brew.sh"
        exit 1
    fi
    brew install cmake python openjdk@17 maven
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

# Install Rust
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Install Python packages
echo "Installing Python packages..."
pip3 install --user boto3 botocore

echo ""
echo "✓ System dependencies installed!"
echo ""
echo "Next steps:"
echo "  1. Initialize git submodules: git submodule update --init --recursive"
echo "  2. Build everything: ./crt-benchmarker.sh build all"
echo "  3. Generate workloads: ./crt-benchmarker.sh workload build"
