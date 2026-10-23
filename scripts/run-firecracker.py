#!/usr/bin/env python3
"""Boot actual x86_64 Elixos in Firecracker; RAM-only, serial, no host networking changes."""
import argparse
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parent.parent
    build = Path(os.environ.get('ELIXOS_BUILD', root / 'build')).resolve()
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        'Development launcher, not a production jailer. Requires Linux KVM. '
        'No disks, TAP, external API socket or GPU are attached. '
        'The guest has serial IEx and loopback PostgreSQL; all state resets on a new boot.'
    ))
    parser.add_argument('--memory-mib', type=int, default=4096)
    parser.add_argument('--cpus', type=int, default=2)
    parser.add_argument('--kernel', type=Path, default=build / 'bzImage')
    parser.add_argument('--initrd', type=Path, default=build / 'initramfs-live.cpio.gz')
    parser.add_argument('--firecracker', type=Path, default=Path(os.environ.get(
        'FIRECRACKER', str(build / 'tools/firecracker-v1.17.0-x86_64/firecracker'))))
    args = parser.parse_args()
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        parser.error('this boot profile requires an x86_64 Linux host')
    if args.memory_mib <= 0 or args.cpus <= 0:
        parser.error('memory and CPU counts must be positive')
    for path in (args.kernel, args.initrd):
        if not path.is_file() or not os.access(path, os.R_OK):
            parser.error(f'missing readable boot artifact: {path}')
    if not args.firecracker.is_file() or not os.access(args.firecracker, os.X_OK):
        parser.error('Firecracker missing; run scripts/install-firecracker.sh or set FIRECRACKER')
    if not os.access('/dev/kvm', os.R_OK | os.W_OK):
        parser.error('read/write /dev/kvm is required; there is no emulation fallback')
    config = {
        'boot-source': {
            'kernel_image_path': str(args.kernel.resolve()),
            'initrd_path': str(args.initrd.resolve()),
            'boot_args': 'console=ttyS0 reboot=k panic=-1 quiet elixos.live=1',
        },
        'machine-config': {'vcpu_count': args.cpus, 'mem_size_mib': args.memory_mib, 'smt': False},
        'drives': [],
    }
    with tempfile.TemporaryDirectory(prefix='elixos-firecracker-') as directory:
        configuration = Path(directory) / 'config.json'
        configuration.write_text(json.dumps(config))
        command = [str(args.firecracker.resolve()), '--no-api', '--config-file', str(configuration)]
        print(f'elixos-firecracker: KVM required, {args.memory_mib} MiB, {args.cpus} CPUs, no disks or TAP', file=sys.stderr, flush=True)
        process = subprocess.Popen(command)
        previous = {}
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, lambda received, _frame: process.send_signal(received) if process.poll() is None else None)
        try:
            return process.wait()
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    sys.exit(main())
