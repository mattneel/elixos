#!/usr/bin/env python3
"""Melange build step only. Native pip verifies every upstream wheel hash."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(destination, architecture):
    pins_path = Path('/home/build/scripts/coding-eval/python-wheels.json')
    pins = json.loads(pins_path.read_text())
    if sys.version_info[:3] != tuple(map(int, pins['python'].split('.'))):
        raise RuntimeError('Eval Python builder must match the pinned CPython version')
    sources = pins['sources'][architecture]
    if len(sources) != 4 or len({item['package'] for item in sources}) != 4:
        raise RuntimeError('incomplete pinned Eval Python runtime closure')
    root = Path(destination) / 'opt/oh-my-jido-eval'
    root.mkdir(parents=True, exist_ok=False)
    venv = root / 'venv'
    subprocess.run([sys.executable, '-m', 'venv', '--without-pip', '--symlinks', str(venv)], check=True)
    with tempfile.TemporaryDirectory(prefix='coding-eval-wheels-') as work:
        work = Path(work)
        downloads = work / 'wheels'
        downloads.mkdir()
        requirements = work / 'download.txt'
        requirements.write_text(''.join(f"{item['url']} --hash=sha256:{item['sha256']}\n" for item in sources))
        subprocess.run([sys.executable, '-m', 'pip', 'download', '--disable-pip-version-check',
                        '--no-deps', '--only-binary=:all:', '--require-hashes', '-r', str(requirements),
                        '--dest', str(downloads)], check=True)
        installed = []
        install_requirements = work / 'install.txt'
        for item in sources:
            wheel = downloads / item['filename']
            if not wheel.is_file() or wheel.stat().st_size == 0 or digest(wheel) != item['sha256']:
                raise RuntimeError(f"missing/changed Python wheel: {item['filename']}")
            installed.append(dict(item, bytes=wheel.stat().st_size))
        install_requirements.write_text(''.join(f"{downloads / item['filename']} --hash=sha256:{item['sha256']}\n" for item in sources))
        subprocess.run([sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check',
                        '--no-index', '--no-deps', '--no-compile', '--require-hashes',
                        '--target', str(venv / 'lib/python3.14/site-packages'),
                        '-r', str(install_requirements)], check=True)
    # The interpreter link is intentionally system-layout, not a host/staging path.
    for name in ('python', 'python3', 'python3.14'):
        link = venv / 'bin' / name
        if link.is_symlink():
            link.unlink()
            link.symlink_to('/usr/bin/python3.14')
    (root / 'python-wheels.json').write_bytes(pins_path.read_bytes())
    (root / 'python-package.py').write_bytes(Path(__file__).read_bytes())
    (root / 'source.json').write_text(json.dumps({
        'format_version': 1, 'architecture': architecture, 'libc': 'musl',
        'python': sys.version, 'system_python_sha256': digest(Path(sys.executable).resolve()),
        'pins_sha256': digest(pins_path), 'wheels': installed,
        'layout': '/opt/oh-my-jido-eval/venv', 'provisioning_at_runtime': False,
    }, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    main(*sys.argv[1:])
