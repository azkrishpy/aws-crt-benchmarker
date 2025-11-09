#!/usr/bin/env python3
"""
The per-instance job is running on a specific EC2 instance type.
It pulls down the aws-crt-s3-benchmarks repo and runs the benchmarks.
"""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import s3_benchmarks


# Use comma separated lists for Batch jobs (instead of normal argparse lists)
# so that it's easy to pass via Batch's job definition parameters:
# https://docs.aws.amazon.com/batch/latest/userguide/job_definition_parameters.html?icmpid=docs_console_unmapped#parameters
def comma_separated_list(arg):
    items = arg.split(',')  # comma separated
    items = [x.strip() for x in items]  # strip whitespace
    items = [x for x in items if x]  # remove empty strings
    if len(items) == 0:
        raise argparse.ArgumentTypeError('List is empty')
    return items


PARSER = argparse.ArgumentParser(
    description="Run S3 benchmarks on each EC2 instance type")
PARSER.add_argument(
    '--buckets', required=True, type=comma_separated_list,
    help="S3 bucket names, comma separated (e.g. my-bucket,my-bucket--usw2-az3--x-s3)")
PARSER.add_argument(
    '--region', required=True,
    help="AWS region (e.g. us-west-2)")
PARSER.add_argument(
    '--instance-type', required=True,
    choices=s3_benchmarks.INSTANCE_TYPES.keys(),
    help="EC2 instance type this is running on")
PARSER.add_argument(
    '--s3-clients', required=True, type=comma_separated_list,
    help="S3 clients to benchmark, comma separated (e.g. crt-c,crt-python)")
PARSER.add_argument(
    '--workloads', required=True, type=comma_separated_list,
    help="Workloads, comma separated (e.g. upload-Caltech256Sharded,download-Caltech256Sharded)")
PARSER.add_argument(
    '--branch',
    # default to "main" (instead of None or "") to work better with Batch parameters.
    # (Batch seems to omit parameters with empty string values)
    default="main",
    help="If specified, try to use this branch/commit/tag of various Git repos.")
PARSER.add_argument(
    '--skip-installs', action='store_true',
    help="Skip installing tools. Useful if running the script locally.")


def run(cmd_args: list[str], check=True):
    print(f'{Path.cwd()}> {subprocess.list2cmdline(cmd_args)}', flush=True)
    subprocess.run(cmd_args, check=check)


if __name__ == '__main__':
    # show in logs exactly how this Batch job was invoked
    print(f"> {sys.executable} {subprocess.list2cmdline(sys.argv)}")

    # show file system disk space usage
    run(['df', '-Th'])

    args = PARSER.parse_args()

    instance_type = s3_benchmarks.INSTANCE_TYPES[args.instance_type]

    # cd into tmp working dir
    try:
        tmp_dir = Path(tempfile.mkdtemp(prefix='s3-benchmarks-',
                                        dir=s3_benchmarks.PER_INSTANCE_WORK_DIR)).absolute()
    except FileNotFoundError:
        # if running locally, PER_INSTANCE_WORK_DIR may not exist,
        # so fall back to normal /tmp dir
        tmp_dir = Path(tempfile.mkdtemp(prefix='s3-benchmarks-')).absolute()

    os.chdir(tmp_dir)
    print(f"Using tmp dir: {tmp_dir}")

    # git clone aws-crt-s3-benchmarks
    run(['git', 'clone', 'https://github.com/awslabs/aws-crt-s3-benchmarks.git'])
    benchmarks_dir = Path('aws-crt-s3-benchmarks')

    # if branch specified, try to check it out
    preferred_branch = args.branch if args.branch != 'main' else None
    if preferred_branch:
        os.chdir(benchmarks_dir)
        run(['git', 'checkout', preferred_branch], check=False)
        os.chdir(tmp_dir)

    # install tools
    if not args.skip_installs:
        run([sys.executable,
            str(benchmarks_dir/'scripts/install-tools-AL2023.py')])

        # install python packages
        run([sys.executable, '-m', 'pip', 'install', '-r',
            str(benchmarks_dir/'scripts/requirements.txt')])

    # get full paths to workload files
    workloads = []
    for workload_name in args.workloads:
        workload_path = benchmarks_dir/f'workloads/{workload_name}.run.json'
        workloads.append(str(workload_path))

    # Initialize submodules
    os.chdir(benchmarks_dir)
    run(['git', 'submodule', 'update', '--init', '--recursive'])
    
    # Run init to install dependencies
    run([str(benchmarks_dir/'crt-benchmarker.sh'), 'init'])
    
    # Build workloads
    run([str(benchmarks_dir/'crt-benchmarker.sh'), 'workload', 'build'])
    
    # Build all runners
    run([str(benchmarks_dir/'crt-benchmarker.sh'), 'build', 'all'])
    
    # Prep files for each bucket
    for bucket in args.buckets:
        run([str(benchmarks_dir/'crt-benchmarker.sh'), 'prep', 'all',
             '--bucket', bucket, '--region', args.region])
    
    # Run benchmarks for each client and workload
    for s3_client in args.s3_clients:
        for workload_name in args.workloads:
            workload_file = f'{workload_name}.json'
            for bucket in args.buckets:
                run([str(benchmarks_dir/'crt-benchmarker.sh'), 'test',
                     '--client', s3_client,
                     '--workload', workload_file,
                     '--bucket', bucket,
                     '--region', args.region,
                     '--throughput', str(instance_type.bandwidth_Gbps)])

    print("PER-INSTANCE JOB DONE!")
