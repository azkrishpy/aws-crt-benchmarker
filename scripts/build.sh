#!/bin/bash
set -e  # Exit on any error

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$REPO_ROOT/install"
BUILD_DIR="$REPO_ROOT/build"
DEPS_SCRIPT="$REPO_ROOT/scripts/py/dependencies.py"

# Dependency build order for C (kept for 'build all' command)
C_DEPENDENCIES=(
    "aws-c-common"
    "aws-lc"
    "s2n"
    "aws-c-cal"
    "aws-c-io"
    "aws-checksums"
    "aws-c-compression"
    "aws-c-http"
    "aws-c-sdkutils"
    "aws-c-auth"
)

C_CLIENTS=(
    "aws-c-s3"
)

C_RUNNERS=(
    "s3-c"
)

# Check if a component is already built
is_component_built() {
    local component=$1
    python3 "$DEPS_SCRIPT" is-built "$component" "$INSTALL_DIR" > /dev/null 2>&1
    return $?
}

# Build a component with automatic dependency resolution
build_with_deps() {
    local component=$1
    
    echo "Resolving dependencies for $component..."
    local all_deps=$(python3 "$DEPS_SCRIPT" all-deps "$component")
    
    for dep in $all_deps; do
        if [ "$dep" = "$component" ]; then
            # Build the component itself
            build_single_component "$component"
        else
            # Check if dependency is already built
            if is_component_built "$dep"; then
                echo "  $dep already built, skipping..."
            else
                echo "  Building dependency: $dep"
                build_single_component "$dep"
            fi
        fi
    done
}

# Build a single component without dependency checking
build_single_component() {
    local component=$1
    
    case "$component" in
        # C dependencies and clients
        aws-c-common|aws-lc|s2n|aws-c-cal|aws-c-io|aws-checksums|aws-c-compression|aws-c-http|aws-c-sdkutils|aws-c-auth|aws-c-s3)
            local extra=""
            if [ "$component" = "aws-lc" ]; then
                extra="-DDISABLE_GO=ON -DBUILD_LIBSSL=OFF -DDISABLE_PERL=ON"
            fi
            
            local src_dir
            if [ "$component" = "aws-c-s3" ]; then
                src_dir="$REPO_ROOT/source/clients/$component"
            else
                src_dir="$REPO_ROOT/source/dependencies/$component"
            fi
            
            build_cmake_project "$component" "$src_dir" "$extra"
            ;;
        
        # C runners
        runner-s3-c)
            build_cmake_project "$component" "$REPO_ROOT/source/runners/s3-c"
            ;;
        
        # Rust client
        aws-s3-transfer-manager-rs)
            build_rust_client
            ;;
        
        # Rust runner
        runner-s3-rust)
            build_rust_runner
            ;;
        
        *)
            echo "Unknown component: $component"
            exit 1
            ;;
    esac
}

build_cmake_project() {
    local name=$1
    local src_dir=$2
    local extra_flags="${3:-}"
    
    echo "Building $name..."
    
    cmake -S "$src_dir" \
          -B "$BUILD_DIR/$name" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
          -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
          -DBUILD_TESTING=OFF \
          $extra_flags
    
    cmake --build "$BUILD_DIR/$name" --target install
}

build_c_dependencies() {
    for dep in "${C_DEPENDENCIES[@]}"; do
        local extra=""
        if [ "$dep" = "aws-lc" ]; then
            extra="-DDISABLE_GO=ON -DBUILD_LIBSSL=OFF -DDISABLE_PERL=ON"
        fi
        build_cmake_project "$dep" "$REPO_ROOT/source/dependencies/$dep" "$extra"
    done
}

build_c_clients() {
    for client in "${C_CLIENTS[@]}"; do
        build_cmake_project "$client" "$REPO_ROOT/source/clients/$client"
    done
}

build_c_runners() {
    for runner in "${C_RUNNERS[@]}"; do
        build_cmake_project "runner-$runner" "$REPO_ROOT/source/runners/$runner"
    done
}

build_python_client() {
    echo "Building Python client..."
    
    local venv_dir="$INSTALL_DIR/python-venv"
    
    # Create venv if it doesn't exist
    if [ ! -d "$venv_dir" ]; then
        python3 -m venv "$venv_dir"
    fi
    
    local pip="$venv_dir/bin/pip"
    local python="$venv_dir/bin/python3"
    
    # Upgrade pip
    "$python" -m pip install --upgrade pip wheel
    
    # Install aws-crt-python FIRST (others depend on it)
    "$pip" install "$REPO_ROOT/source/clients/aws-crt-python"
    
    # Then install the rest
    "$pip" install "$REPO_ROOT/source/clients/botocore"
    "$pip" install "$REPO_ROOT/source/clients/s3transfer"
    "$pip" install "$REPO_ROOT/source/clients/boto3"
    "$pip" install "$REPO_ROOT/source/clients/aws-cli"
    
    echo "Python clients installed to $venv_dir"
}

build_python_runner() {
    echo "Python runner ready (no build needed - it's a script)"
}

build_java_client() {
    echo "Building Java client..."
    
    # Build aws-crt-java
    cd "$REPO_ROOT/source/clients/aws-crt-java"
    mvn clean install -Dmaven.test.skip
    
    # Build aws-sdk-java-v2
    cd "$REPO_ROOT/source/clients/aws-sdk-java-v2"
    mvn clean install \
        -pl :s3-transfer-manager,:s3,:bom-internal,:bom \
        -P quick \
        --am \
        -Dawscrt.version=1.0.0-SNAPSHOT
    
    echo "Java clients installed"
}

build_java_runner() {
    echo "Building Java runner..."
    
    cd "$REPO_ROOT/source/runners/s3-java"
    mvn clean package -Dawscrt.version=1.0.0-SNAPSHOT
    
    echo "Java runner built"
}

build_rust_client() {
    echo "Building Rust client..."
    
    cd "$REPO_ROOT/source/clients/aws-s3-transfer-manager-rs"
    cargo build --release
    
    echo "Rust client built"
}

build_rust_runner() {
    echo "Building Rust runner..."
    
    cd "$REPO_ROOT/source/runners/s3-rust"
    cargo build --release
    
    echo "Rust runner built"
}

# Parse arguments
COMPONENT_TYPE=""
COMPONENT_NAME=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        all)
            COMPONENT_TYPE="all"
            shift
            ;;
        -f|-F|--force)
            FORCE=true
            shift
            ;;
        -c|-C|--client)
            COMPONENT_TYPE="client"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        -r|-R|--runner)
            COMPONENT_TYPE="runner"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        -d|-D|--dep)
            COMPONENT_TYPE="dependency"
            COMPONENT_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: build.sh {all [-f|--force] | --client/-c <name> | --runner/-r <name> | --dep/-d <name>}"
            exit 1
            ;;
    esac
done

# Execute based on parsed arguments
case "$COMPONENT_TYPE" in
    all)
        if [ "$FORCE" = false ]; then
            read -p "Build all components? This will take a while and occupy a lot of space as it includes c, java, python and rust clients. (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Build cancelled"
                exit 0
            fi
        fi
        build_c_dependencies
        build_c_clients
        build_c_runners
        build_python_client
        build_python_runner
        build_java_client
        build_java_runner
        build_rust_client
        build_rust_runner
        echo "Build complete!"
        ;;
    client)
        if [ -z "$COMPONENT_NAME" ]; then
            echo "Usage: build.sh --client/-c <name>"
            exit 1
        fi
        case "$COMPONENT_NAME" in
            python)
                build_python_client
                ;;
            java)
                build_java_client
                ;;
            rust)
                build_with_deps "aws-s3-transfer-manager-rs"
                ;;
            aws-c-s3)
                build_with_deps "aws-c-s3"
                ;;
            *)
                echo "Unknown client: $COMPONENT_NAME"
                exit 1
                ;;
        esac
        ;;
    dependency)
        if [ -z "$COMPONENT_NAME" ]; then
            echo "Usage: build.sh --dep/-d <name>"
            exit 1
        fi
        build_with_deps "$COMPONENT_NAME"
        ;;
    runner)
        if [ -z "$COMPONENT_NAME" ]; then
            echo "Usage: build.sh --runner/-r <name>"
            exit 1
        fi
        case "$COMPONENT_NAME" in
            python)
                build_python_runner
                ;;
            java)
                build_java_runner
                ;;
            c)
                build_with_deps "runner-s3-c"
                ;;
            rust)
                build_with_deps "runner-s3-rust"
                ;;
            *)
                build_with_deps "runner-$COMPONENT_NAME"
                ;;
        esac
        ;;
    *)
        echo "Usage: build.sh {all [-f|-F|--force] | --client/-c/-C <name> | --runner/-r/-R <name> | --dep/-d/-D <name>}"
        exit 1
        ;;
esac
