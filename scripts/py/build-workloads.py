#!/usr/bin/env python3
import argparse
import math
from pathlib import Path
import json
import re
from typing import Optional

REPO_ROOT = Path(__file__).parent.parent.parent
WORKLOADS_SRC_DIR = REPO_ROOT / 'workloads' / 'src'
WORKLOADS_RUN_DIR = REPO_ROOT / 'workloads' / 'run'

VERSION = 2
DEFAULT_NUM_FILES = 1
DEFAULT_FILES_ON_DISK = True
DEFAULT_CHECKSUM = None
DEFAULT_MAX_REPEAT_COUNT = 10
DEFAULT_MAX_REPEAT_SECS = 600

PARSER = argparse.ArgumentParser(
    description='Build workload src/*.json into run/*.json.')
PARSER.add_argument(
    'SRC_FILE', nargs='*',
    help='Path to specific workload src json file. ' +
    'If none specified, builds all workloads/src/*.json')


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


def build_workload(src_file: Path):
    """Read workload src JSON and write out run JSON."""
    with open(src_file) as f:
        src_json = json.load(f)

    # required fields
    action: str = src_json['action']
    file_size_str: str = src_json['fileSize']
    file_size: int = size_from_str(file_size_str)

    # optional fields
    comment: str = src_json.get('comment', "")
    num_files: int = src_json.get('numFiles', DEFAULT_NUM_FILES)
    files_on_disk: bool = src_json.get('filesOnDisk', DEFAULT_FILES_ON_DISK)
    checksum: Optional[str] = src_json.get('checksum', DEFAULT_CHECKSUM)
    max_repeat_count = src_json.get('maxRepeatCount', DEFAULT_MAX_REPEAT_COUNT)
    max_repeat_secs = src_json.get('maxRepeatSecs', DEFAULT_MAX_REPEAT_SECS)

    # validation
    assert action in ('download', 'upload')
    assert checksum in (None, 'CRC32', 'CRC32C', 'SHA1', 'SHA256')

    # Build directory name
    dirname = f'{file_size_str}'
    dirname += f'-{num_files:_}x'
    if checksum:
        dirname += f'-{checksum.lower()}'

    suffix = ''
    if not files_on_disk:
        suffix += '-ram'

    # Build dst workload run json
    dst_json = {
        'version': VERSION,
        'comment': comment,
        'filesOnDisk': files_on_disk,
        'checksum': checksum,
        'maxRepeatCount': max_repeat_count,
        'maxRepeatSecs': max_repeat_secs,
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
        dst_json['tasks'].append(task)

    # Ensure run directory exists
    WORKLOADS_RUN_DIR.mkdir(parents=True, exist_ok=True)

    # Write file to run directory
    dst_file = WORKLOADS_RUN_DIR / src_file.name
    with open(dst_file, 'w') as f:
        json.dump(dst_json, f, indent=4)
        f.write('\n')
    
    print(f"Built {src_file.name} -> {dst_file.relative_to(REPO_ROOT)}")


if __name__ == '__main__':
    args = PARSER.parse_args()

    if args.SRC_FILE:
        src_files = [Path(x) for x in args.SRC_FILE]
        for src_file in src_files:
            if not src_file.exists():
                exit(f'file not found: {src_file}')
    else:
        src_files = sorted(WORKLOADS_SRC_DIR.glob('*.json'))
        if not src_files:
            exit(f'no workload src files found in {WORKLOADS_SRC_DIR}')

    for src_file in src_files:
        try:
            build_workload(src_file)
        except Exception as e:
            print(f'Failed building: {str(src_file)}')
            raise e
