#!/usr/bin/env python3
"""
Compare two S3 clients by running benchmarks and displaying side-by-side results.

This script:
1. Parses payload (workload names or JSON file) into a combined workload
2. Preps files once (creates local files, uploads to S3)
3. For each client: checkout branch, rebuild, run benchmark, capture output
4. Parses metrics from both runs
5. Displays comparison table
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# Constants
VERSION = 2
DEFAULT_MAX_REPEAT_COUNT = 10
DEFAULT_MAX_REPEAT_SECS = 600

# Get repo root
REPO_ROOT = Path(__file__).parent.parent.parent.absolute()
FILES_DIR = REPO_ROOT / "files"
SCRIPTS_DIR = REPO_ROOT / "scripts"


def log(msg, verbose=True):
    """Print message if verbose mode is enabled"""
    if verbose:
        print(msg, flush=True)


def run_command(cmd, cwd=None, capture=False, verbose=True):
    """
    Run a shell command.
    
    Args:
        cmd: Command as list or string
        cwd: Working directory
        capture: If True, capture and return output; if False, stream to stdout
        verbose: If True, show command output
    
    Returns:
        If capture=True, returns (stdout, stderr, returncode)
        If capture=False, returns returncode
    """
    if isinstance(cmd, str):
        cmd = [cmd]
    
    if verbose:
        log(f"Running: {' '.join(cmd)}", verbose=True)
    
    if capture:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return result.stdout, result.stderr, result.returncode
    else:
        if verbose:
            result = subprocess.run(cmd, cwd=cwd)
        else:
            result = subprocess.run(cmd, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return result.returncode


def size_from_str(size_str: str) -> int:
    """Return size in bytes, given string like '5GiB' or '10KiB' or '1byte'"""
    m = re.match(r"(\d+)(KiB|MiB|GiB|bytes|byte)$", size_str)
    if m:
        size = int(m.group(1))
        unit = m.group(2)
        if unit == "KiB":
            size *= 1024
        elif unit == "MiB":
            size *= 1024 * 1024
        elif unit == "GiB":
            size *= 1024 * 1024 * 1024
        return size
    else:
        raise Exception(f'Illegal size "{size_str}". Expected something like "1KiB"')


def parse_workload_name(name: str):
    """
    Parse workload name like 'upload-15MiB-1x' or 'download-5GiB-10_000x-ram'.
    
    Returns:
        (action, file_size_str, num_files, files_on_disk)
    """
    # Remove .json extension if present
    name = name.replace('.json', '')
    
    # Check for -ram suffix
    files_on_disk = True
    if name.endswith('-ram'):
        files_on_disk = False
        name = name[:-4]
    
    # Parse pattern: {action}-{size}-{count}x
    parts = name.split('-')
    if len(parts) < 3:
        raise Exception(f'Invalid workload name: {name}. Expected: {{action}}-{{size}}-{{count}}x[-ram]')
    
    action = parts[0]
    if action not in ('upload', 'download'):
        raise Exception(f'Invalid action: {action}. Must be "upload" or "download"')
    
    file_size_str = parts[1]
    count_part = '-'.join(parts[2:])
    
    if not count_part.endswith('x'):
        raise Exception(f'Invalid count format: {count_part}. Must end with "x"')
    
    num_files = int(count_part[:-1].replace('_', ''))
    
    return action, file_size_str, num_files, files_on_disk


def generate_tasks_from_workload_name(name: str):
    """Generate task list from a workload name"""
    action, file_size_str, num_files, files_on_disk = parse_workload_name(name)
    file_size = size_from_str(file_size_str)
    
    # Build directory name
    dirname = f'{file_size_str}-{num_files:_}x'
    
    # Format filenames
    int_width = int(math.log10(num_files)) + 1 if num_files > 1 else 1
    int_fmt = f"{{:0{int_width}}}"
    
    tasks = []
    for i in range(num_files):
        filename = int_fmt.format(i + 1)
        task = {
            'action': action,
            'key': f'{action}/{dirname}/{filename}',
            'size': file_size,
        }
        tasks.append(task)
    
    return tasks, files_on_disk


def parse_payload(payload_args, verbose):
    """
    Parse payload arguments into a workload JSON structure.
    
    Args:
        payload_args: List of payload arguments (workload names or JSON file path)
        verbose: Verbose mode flag
    
    Returns:
        (workload_dict, files_on_disk)
    """
    log("Parsing payload...", verbose)
    
    # Check if it's a JSON file
    if len(payload_args) == 1 and payload_args[0].endswith('.json'):
        json_path = Path(payload_args[0])
        if not json_path.exists():
            raise Exception(f'Payload file not found: {json_path}')
        
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        # If it's an array, combine all tasks
        if isinstance(data, list):
            all_tasks = []
            files_on_disk = True
            for item in data:
                if 'tasks' in item:
                    all_tasks.extend(item['tasks'])
                    if 'filesOnDisk' in item:
                        files_on_disk = files_on_disk and item['filesOnDisk']
                else:
                    # Assume it's a workload spec like {"action": "upload", "fileSize": "1GiB", "numFiles": 10}
                    action = item['action']
                    file_size_str = item['fileSize']
                    num_files = item['numFiles']
                    files_on_disk = item.get('filesOnDisk', True)
                    
                    # Generate tasks
                    name = f"{action}-{file_size_str}-{num_files}x"
                    tasks, _ = generate_tasks_from_workload_name(name)
                    all_tasks.extend(tasks)
            
            workload = {
                'version': VERSION,
                'filesOnDisk': files_on_disk,
                'checksum': None,
                'maxRepeatCount': DEFAULT_MAX_REPEAT_COUNT,
                'maxRepeatSecs': DEFAULT_MAX_REPEAT_SECS,
                'tasks': all_tasks,
            }
        else:
            # Single workload object
            workload = data
            files_on_disk = workload.get('filesOnDisk', True)
    else:
        # Parse as workload names
        all_tasks = []
        files_on_disk = True
        
        for name in payload_args:
            log(f"  Parsing: {name}", verbose)
            tasks, fod = generate_tasks_from_workload_name(name)
            all_tasks.extend(tasks)
            files_on_disk = files_on_disk and fod
        
        workload = {
            'version': VERSION,
            'filesOnDisk': files_on_disk,
            'checksum': None,
            'maxRepeatCount': DEFAULT_MAX_REPEAT_COUNT,
            'maxRepeatSecs': DEFAULT_MAX_REPEAT_SECS,
            'tasks': all_tasks,
        }
    
    log(f"  Total tasks: {len(workload['tasks'])}", verbose)
    log(f"  Files on disk: {workload['filesOnDisk']}", verbose)
    
    return workload, workload['filesOnDisk']


def prep_files(workload_path, bucket, region, verbose):
    """Prepare files for the workload"""
    log("\nPreparing files...", verbose)
    
    FILES_DIR.mkdir(exist_ok=True)
    
    cmd = [
        'python3',
        str(SCRIPTS_DIR / 'py' / 'prep-s3-files.py'),
        '--bucket', bucket,
        '--region', region,
        '--files-dir', str(FILES_DIR),
        '--workloads', str(workload_path),
    ]
    
    returncode = run_command(cmd, capture=False, verbose=verbose)
    if returncode != 0:
        raise Exception('File preparation failed')


def checkout_branch(repo_path, branch, verbose):
    """Checkout a branch in a git repository"""
    log(f"\nChecking out {branch} in {repo_path}...", verbose)
    
    repo_full_path = REPO_ROOT / repo_path
    
    # Fetch latest
    cmd = ['git', 'fetch', 'origin']
    returncode = run_command(cmd, cwd=repo_full_path, capture=False, verbose=verbose)
    if returncode != 0:
        raise Exception(f'Git fetch failed in {repo_path}')
    
    # Checkout branch
    cmd = ['git', 'checkout', branch]
    returncode = run_command(cmd, cwd=repo_full_path, capture=False, verbose=verbose)
    if returncode != 0:
        raise Exception(f'Git checkout failed for branch {branch} in {repo_path}')


def get_build_type(client_name):
    """Determine build type based on client name"""
    if client_name == 'crt-c':
        return 'aws-c-s3'
    elif client_name in ['crt-python', 'boto3-crt', 'boto3-classic', 'cli-crt', 'cli-classic']:
        return 'python'
    elif client_name in ['crt-java', 'sdk-java-client-crt', 'sdk-java-client-classic', 'sdk-java-tm-crt', 'sdk-java-tm-classic']:
        return 'java'
    elif client_name == 'sdk-rust-tm':
        return 'rust'
    else:
        raise Exception(f'Unknown client: {client_name}')


def rebuild_client(client_name, verbose):
    """Rebuild a client"""
    log(f"\nRebuilding {client_name}...", verbose)
    
    build_type = get_build_type(client_name)
    
    # Clear first
    cmd = [str(SCRIPTS_DIR / 'clear.sh'), '--client', build_type]
    returncode = run_command(cmd, capture=False, verbose=verbose)
    if returncode != 0:
        log(f"Warning: Clear failed for {client_name}", verbose)
    
    # Build
    cmd = [str(SCRIPTS_DIR / 'build.sh'), '--client', build_type]
    returncode = run_command(cmd, capture=False, verbose=verbose)
    if returncode != 0:
        raise Exception(f'Build failed for {client_name}')


def run_benchmark(client_name, workload_path, bucket, region, throughput, verbose):
    """
    Run benchmark for a client and capture output.
    
    Returns:
        stdout as string
    """
    log(f"\nRunning benchmark for {client_name}...", verbose)
    
    # Change to files directory
    os.chdir(FILES_DIR)
    
    # Determine runner command
    if client_name == 'crt-c':
        cmd = [
            str(REPO_ROOT / 'install' / 'bin' / 's3-c'),
            client_name,
            str(workload_path),
            bucket,
            region,
            str(throughput),
        ]
    elif client_name in ['crt-python', 'boto3-crt', 'boto3-classic', 'cli-crt', 'cli-classic']:
        cmd = [
            str(REPO_ROOT / 'install' / 'python-venv' / 'bin' / 'python3'),
            str(REPO_ROOT / 'source' / 'runners' / 's3-python' / 'main.py'),
            client_name,
            str(workload_path),
            bucket,
            region,
            str(throughput),
        ]
    elif client_name in ['crt-java', 'sdk-java-client-crt', 'sdk-java-client-classic', 'sdk-java-tm-crt', 'sdk-java-tm-classic']:
        cmd = [
            'java',
            '-jar',
            str(REPO_ROOT / 'source' / 'runners' / 's3-java' / 'target' / 's3-benchrunner-java-1.0-SNAPSHOT.jar'),
            client_name,
            str(workload_path),
            bucket,
            region,
            str(throughput),
        ]
    elif client_name == 'sdk-rust-tm':
        env = os.environ.copy()
        env['AWS_REGION'] = region
        cmd = [
            str(REPO_ROOT / 'source' / 'runners' / 's3-rust' / 'target' / 'release' / 's3-benchrunner-rust'),
            client_name,
            str(workload_path),
            bucket,
            region,
            str(throughput),
        ]
    else:
        raise Exception(f'Unknown client: {client_name}')
    
    # Run and capture output
    if verbose:
        log(f"Running: {' '.join(cmd)}", verbose=True)
        result = subprocess.run(cmd, capture_output=True, text=True)
        # Print output in real-time for verbose mode
        print(result.stdout, flush=True)
        if result.stderr:
            print(result.stderr, file=sys.stderr, flush=True)
    else:
        result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error running benchmark for {client_name}:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise Exception(f'Benchmark failed for {client_name}')
    
    return result.stdout


def parse_metrics(output):
    """
    Parse metrics from benchmark output.
    
    Returns:
        dict with keys: throughput_median, throughput_mean, throughput_min, throughput_max,
                       duration_median, duration_mean, duration_min, duration_max,
                       peak_rss, runs
    """
    metrics = {
        'runs': [],
        'throughput_median': None,
        'throughput_mean': None,
        'throughput_min': None,
        'throughput_max': None,
        'duration_median': None,
        'duration_mean': None,
        'duration_min': None,
        'duration_max': None,
        'peak_rss': None,
    }
    
    # Parse individual runs: "Run:1 Secs:0.5 Gb/s:10.2"
    for line in output.split('\n'):
        run_match = re.search(r'Run:(\d+)\s+Secs:([\d.]+)\s+Gb/s:([\d.]+)', line)
        if run_match:
            run_num = int(run_match.group(1))
            secs = float(run_match.group(2))
            gbps = float(run_match.group(3))
            metrics['runs'].append({'run': run_num, 'secs': secs, 'gbps': gbps})
        
        # Parse overall throughput: "Overall Throughput (Gb/s) Median:45.2 Mean:44.9 Min:42.1 Max:46.8 ..."
        throughput_match = re.search(r'Overall Throughput \(Gb/s\)\s+Median:([\d.]+)\s+Mean:([\d.]+)\s+Min:([\d.]+)\s+Max:([\d.]+)', line)
        if throughput_match:
            metrics['throughput_median'] = float(throughput_match.group(1))
            metrics['throughput_mean'] = float(throughput_match.group(2))
            metrics['throughput_min'] = float(throughput_match.group(3))
            metrics['throughput_max'] = float(throughput_match.group(4))
        
        # Parse overall duration: "Overall Duration (Secs) Median:0.88 Mean:0.89 ..."
        duration_match = re.search(r'Overall Duration \(Secs\)\s+Median:([\d.]+)\s+Mean:([\d.]+)\s+Min:([\d.]+)\s+Max:([\d.]+)', line)
        if duration_match:
            metrics['duration_median'] = float(duration_match.group(1))
            metrics['duration_mean'] = float(duration_match.group(2))
            metrics['duration_min'] = float(duration_match.group(3))
            metrics['duration_max'] = float(duration_match.group(4))
        
        # Parse peak RSS: "Peak RSS:256.4 MiB"
        rss_match = re.search(r'Peak RSS:([\d.]+)\s+MiB', line)
        if rss_match:
            metrics['peak_rss'] = float(rss_match.group(1))
    
    return metrics


def format_comparison_table(client1_name, client1_branch, metrics1, client2_name, client2_branch, metrics2):
    """Format comparison table for display"""
    
    # Build client labels
    label1 = f"{client1_name}:{client1_branch}"
    label2 = f"{client2_name}:{client2_branch}"
    
    # Determine column widths
    metric_col_width = 25
    value_col_width = max(len(label1), len(label2), 15)
    
    # Build table
    lines = []
    lines.append("")
    lines.append(f"Comparing: {label1} vs {label2}")
    lines.append("")
    
    # Header
    sep = "─" * metric_col_width + "┬" + "─" * value_col_width + "┬" + "─" * value_col_width
    lines.append("┌" + sep[1:-1] + "┐")
    lines.append(f"│ {'Metric':<{metric_col_width-2}} │ {label1:<{value_col_width-2}} │ {label2:<{value_col_width-2}} │")
    lines.append("├" + sep[1:-1] + "┤")
    
    # Throughput section
    lines.append(f"│ {'Throughput (Gb/s)':<{metric_col_width-2}} │ {'':<{value_col_width-2}} │ {'':<{value_col_width-2}} │")
    
    if metrics1['throughput_median'] is not None and metrics2['throughput_median'] is not None:
        lines.append(f"│ {'  Median':<{metric_col_width-2}} │ {metrics1['throughput_median']:<{value_col_width-2}.2f} │ {metrics2['throughput_median']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Mean':<{metric_col_width-2}} │ {metrics1['throughput_mean']:<{value_col_width-2}.2f} │ {metrics2['throughput_mean']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Min':<{metric_col_width-2}} │ {metrics1['throughput_min']:<{value_col_width-2}.2f} │ {metrics2['throughput_min']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Max':<{metric_col_width-2}} │ {metrics1['throughput_max']:<{value_col_width-2}.2f} │ {metrics2['throughput_max']:<{value_col_width-2}.2f} │")
    else:
        lines.append(f"│ {'  (metrics not available)':<{metric_col_width-2}} │ {'':<{value_col_width-2}} │ {'':<{value_col_width-2}} │")
    
    # Duration section
    lines.append(f"│ {'Duration (Secs)':<{metric_col_width-2}} │ {'':<{value_col_width-2}} │ {'':<{value_col_width-2}} │")
    
    if metrics1['duration_median'] is not None and metrics2['duration_median'] is not None:
        lines.append(f"│ {'  Median':<{metric_col_width-2}} │ {metrics1['duration_median']:<{value_col_width-2}.2f} │ {metrics2['duration_median']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Mean':<{metric_col_width-2}} │ {metrics1['duration_mean']:<{value_col_width-2}.2f} │ {metrics2['duration_mean']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Min':<{metric_col_width-2}} │ {metrics1['duration_min']:<{value_col_width-2}.2f} │ {metrics2['duration_min']:<{value_col_width-2}.2f} │")
        lines.append(f"│ {'  Max':<{metric_col_width-2}} │ {metrics1['duration_max']:<{value_col_width-2}.2f} │ {metrics2['duration_max']:<{value_col_width-2}.2f} │")
    else:
        lines.append(f"│ {'  (metrics not available)':<{metric_col_width-2}} │ {'':<{value_col_width-2}} │ {'':<{value_col_width-2}} │")
    
    # Peak RSS
    if metrics1['peak_rss'] is not None and metrics2['peak_rss'] is not None:
        lines.append(f"│ {'Peak RSS (MiB)':<{metric_col_width-2}} │ {metrics1['peak_rss']:<{value_col_width-2}.2f} │ {metrics2['peak_rss']:<{value_col_width-2}.2f} │")
    else:
        val1 = f"{metrics1['peak_rss']:.2f}" if metrics1['peak_rss'] is not None else "N/A"
        val2 = f"{metrics2['peak_rss']:.2f}" if metrics2['peak_rss'] is not None else "N/A"
        lines.append(f"│ {'Peak RSS (MiB)':<{metric_col_width-2}} │ {val1:<{value_col_width-2}} │ {val2:<{value_col_width-2}} │")
    
    # Footer
    lines.append("└" + sep[1:-1] + "┘")
    lines.append("")
    
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Compare two S3 clients')
    parser.add_argument('--client1', required=True, help='First client name')
    parser.add_argument('--client1-branch', required=True, help='First client branch')
    parser.add_argument('--client1-repo', required=True, help='First client repo path')
    parser.add_argument('--client2', required=True, help='Second client name')
    parser.add_argument('--client2-branch', required=True, help='Second client branch')
    parser.add_argument('--client2-repo', required=True, help='Second client repo path')
    parser.add_argument('--bucket', required=True, help='S3 bucket')
    parser.add_argument('--region', required=True, help='AWS region')
    parser.add_argument('--throughput', required=True, help='Target throughput')
    parser.add_argument('--verbose', required=True, help='Verbose mode (true/false)')
    parser.add_argument('--payload', nargs='+', required=True, help='Payload arguments')
    
    args = parser.parse_args()
    
    verbose = args.verbose.lower() == 'true'
    
    try:
        # Parse payload into workload
        workload, files_on_disk = parse_payload(args.payload, verbose)
        
        # Write workload to temp file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            workload_path = f.name
            json.dump(workload, f, indent=4)
        
        log(f"\nWorkload written to: {workload_path}", verbose)
        
        # Prep files once
        prep_files(workload_path, args.bucket, args.region, verbose)
        
        # Run client1
        log(f"\n{'='*60}", verbose)
        log(f"CLIENT 1: {args.client1}:{args.client1_branch}", verbose)
        log(f"{'='*60}", verbose)
        
        checkout_branch(args.client1_repo, args.client1_branch, verbose)
        rebuild_client(args.client1, verbose)
        output1 = run_benchmark(args.client1, workload_path, args.bucket, args.region, args.throughput, verbose)
        metrics1 = parse_metrics(output1)
        
        # Run client2
        log(f"\n{'='*60}", verbose)
        log(f"CLIENT 2: {args.client2}:{args.client2_branch}", verbose)
        log(f"{'='*60}", verbose)
        
        checkout_branch(args.client2_repo, args.client2_branch, verbose)
        rebuild_client(args.client2, verbose)
        output2 = run_benchmark(args.client2, workload_path, args.bucket, args.region, args.throughput, verbose)
        metrics2 = parse_metrics(output2)
        
        # Display comparison table (always shown, regardless of verbose mode)
        table = format_comparison_table(
            args.client1, args.client1_branch, metrics1,
            args.client2, args.client2_branch, metrics2
        )
        print(table)
        
        # Clean up temp file
        os.unlink(workload_path)
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
