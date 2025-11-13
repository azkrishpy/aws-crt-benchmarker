#!/usr/bin/env python3
"""
Dependency graph for aws-crt-benchmarker components.
Handles dependency resolution for build and clear operations.
"""

import os
import sys
from typing import List, Set, Dict

# Dependency graph: component -> list of direct dependencies
DEPENDENCIES: Dict[str, List[str]] = {
    # C dependencies (in build order)
    "aws-c-common": [],
    "aws-lc": ["aws-c-common"],
    "s2n": ["aws-c-common"],
    "aws-c-cal": ["aws-c-common", "aws-lc", "s2n"],
    "aws-c-io": ["aws-c-common", "aws-c-cal", "s2n"],
    "aws-checksums": ["aws-c-common"],
    "aws-c-compression": ["aws-c-common"],
    "aws-c-http": ["aws-c-common", "aws-c-io", "aws-c-compression"],
    "aws-c-sdkutils": ["aws-c-common"],
    "aws-c-auth": ["aws-c-common", "aws-c-io", "aws-c-http", "aws-c-sdkutils", "aws-c-cal"],
    
    # C client
    "aws-c-s3": ["aws-c-common", "aws-lc", "s2n", "aws-c-cal", "aws-c-io", 
                 "aws-checksums", "aws-c-compression", "aws-c-http", 
                 "aws-c-sdkutils", "aws-c-auth"],
    
    # Rust client (standalone)
    "aws-s3-transfer-manager-rs": [],
    
    # C runner
    "runner-s3-c": ["aws-c-s3"],
    
    # Rust runner
    "runner-s3-rust": ["aws-s3-transfer-manager-rs"],
}


def get_dependencies(component: str) -> List[str]:
    """Get direct dependencies of a component."""
    return DEPENDENCIES.get(component, [])


def get_all_dependencies(component: str) -> List[str]:
    """
    Get all transitive dependencies in build order (bottom-up).
    Returns list with dependencies first, component last.
    """
    visited: Set[str] = set()
    result: List[str] = []
    
    def visit(comp: str):
        if comp in visited:
            return
        visited.add(comp)
        
        for dep in get_dependencies(comp):
            visit(dep)
        
        result.append(comp)
    
    visit(component)
    return result


def get_dependents(component: str) -> List[str]:
    """Get direct dependents of a component (things that depend on it)."""
    dependents = []
    for comp, deps in DEPENDENCIES.items():
        if component in deps:
            dependents.append(comp)
    return dependents


def get_all_dependents(component: str) -> List[str]:
    """
    Get all transitive dependents (things that depend on this component).
    Returns list in top-down order (furthest dependents first).
    """
    visited: Set[str] = set()
    result: List[str] = []
    
    def visit(comp: str):
        if comp in visited:
            return
        visited.add(comp)
        
        # Visit dependents first (top-down)
        for dependent in get_dependents(comp):
            visit(dependent)
        
        if comp != component:  # Don't include the component itself
            result.append(comp)
    
    visit(component)
    return result


def is_built(component: str, install_dir: str) -> bool:
    """
    Check if a component is already built.
    For C libraries: check if install/lib/cmake/{component}/ exists
    For Rust: check if target/release/ exists in the source directory
    """
    if component.startswith("runner-"):
        # Runners use different naming
        runner_name = component.replace("runner-", "")
        cmake_path = os.path.join(install_dir, "lib", "cmake", f"runner-s3-{runner_name}")
        return os.path.isdir(cmake_path)
    elif component == "aws-s3-transfer-manager-rs":
        # Rust client - check for cargo build output
        repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        rust_build = os.path.join(repo_root, "source", "clients", component, "target", "release")
        return os.path.isdir(rust_build)
    else:
        # C dependencies and clients
        cmake_path = os.path.join(install_dir, "lib", "cmake", component)
        return os.path.isdir(cmake_path)


def main():
    """CLI interface for dependency resolution."""
    if len(sys.argv) < 3:
        print("Usage: dependencies.py {deps|dependents|all-deps|all-dependents|is-built} <component> [install_dir]")
        sys.exit(1)
    
    command = sys.argv[1]
    component = sys.argv[2]
    
    if command == "deps":
        deps = get_dependencies(component)
        print(" ".join(deps))
    
    elif command == "all-deps":
        deps = get_all_dependencies(component)
        print(" ".join(deps))
    
    elif command == "dependents":
        dependents = get_dependents(component)
        print(" ".join(dependents))
    
    elif command == "all-dependents":
        dependents = get_all_dependents(component)
        print(" ".join(dependents))
    
    elif command == "is-built":
        if len(sys.argv) < 4:
            print("Usage: dependencies.py is-built <component> <install_dir>")
            sys.exit(1)
        install_dir = sys.argv[3]
        if is_built(component, install_dir):
            print("yes")
            sys.exit(0)
        else:
            print("no")
            sys.exit(1)
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
