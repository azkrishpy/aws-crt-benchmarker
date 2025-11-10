#!/usr/bin/env python3
import argparse
import json
import math
import re
import sys

VERSION = 2
DEFAULT_MAX_REPEAT_COUNT = 10
DEFAULT_MAX_REPEAT_SECS = 600

PARSER = argparse.ArgumentParser(description='Generate temporary workload run JSON from filename.')
PARSER.add_argument('--filename', required=True, help='Workload filename like "upload-15MiB-1x.json"')
PARSER.add_argument('--output', required=True, help='Output file path')


def size_from_str(size_str: str) -> int:
    """Return size in bytes, given string like "5GiB" or "10KiB" or "1byte" """
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


def parse_filename(filename: str):
    """Parse filename like 'upload-15MiB-1x.json' or 'download-5GiB-10_000x-ram.json'"""
    # Remove .json extension
    name = filename.replace('.json', '')
    
    # Check for -ram suffix
    files_on_disk = True
    if name.endswith('-ram'):
        files_on_disk = False
        name = name[:-4]  # Remove '-ram'
    
    # Parse pattern: {action}-{size}-{count}x
    parts = name.split('-')
    if len(parts) < 3:
        raise Exception(f'Invalid filename format: {filename}. Expected: {{action}}-{{size}}-{{count}}x[-ram].json')
    
    action = parts[0]
    if action not in ('upload', 'download'):
        raise Exception(f'Invalid action: {action}. Must be "upload" or "download"')
    
    # Size is the second part
    file_size_str = parts[1]
    
    # Count is everything after, joined back (handles multi-part like "10_000x")
    count_part = '-'.join(parts[2:])
    if not count_part.endswith('x'):
        raise Exception(f'Invalid count format: {count_part}. Must end with "x"')
    
    # Remove 'x' and underscores, convert to int
    num_files = int(count_part[:-1].replace('_', ''))
    
    return action, file_size_str, num_files, files_on_disk


def generate_workload(args):
    action, file_size_str, num_files, files_on_disk = parse_filename(args.filename)
    file_size = size_from_str(file_size_str)
    
    print(f"  action: {action}")
    print(f"  file_size: {file_size_str} ({file_size} bytes)")
    print(f"  num_files: {num_files}")
    print(f"  files_on_disk: {files_on_disk}")
    
    # Build directory name
    dirname = f'{file_size_str}'
    dirname += f'-{num_files:_}x'
    
    # Build workload JSON
    workload = {
        'version': VERSION,
        'comment': f'Temporary workload generated from {args.filename}',
        'filesOnDisk': files_on_disk,
        'checksum': None,
        'maxRepeatCount': DEFAULT_MAX_REPEAT_COUNT,
        'maxRepeatSecs': DEFAULT_MAX_REPEAT_SECS,
        'tasks': [],
    }
    
    # Format filenames
    int_width = int(math.log10(num_files)) + 1 if num_files > 1 else 1
    int_fmt = f"{{:0{int_width}}}"
    
    for i in range(num_files):
        filename = int_fmt.format(i + 1)
        task = {
            'action': action,
            'key': f'{action}/{dirname}/{filename}',
            'size': file_size,
        }
        workload['tasks'].append(task)
    
    # Write to output file
    with open(args.output, 'w') as f:
        json.dump(workload, f, indent=4)
        f.write('\n')


if __name__ == '__main__':
    args = PARSER.parse_args()
    try:
        generate_workload(args)
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)
