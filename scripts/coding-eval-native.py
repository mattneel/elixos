#!/usr/bin/env python3
"""Build-only ELF/source inventory. Never loads a NIF or launches a guest."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def describe(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f'missing/empty native artifact: {path}')
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def elf(path, machine):
    with path.open('rb') as stream:
        header = stream.read(64)
    if not header.startswith(b'\x7fELF'):
        return None
    if len(header) < 64 or header[4:6] != b'\x02\x01' or int.from_bytes(header[18:20], 'little') != machine:
        raise RuntimeError(f'foreign or malformed ELF artifact: {path}')
    text = subprocess.check_output(['readelf', '--wide', '--dynamic', '--dyn-syms', '--program-headers', str(path)], text=True)
    needed = re.findall(r'\(NEEDED\).*\[([^\]]+)\]', text)
    if any('libc.so.6' == name or 'ld-linux' in name for name in needed) or 'Requesting program interpreter: /lib/ld-linux' in text:
        raise RuntimeError(f'glibc artifact selected for musl: {path}')
    search = []
    for value in re.findall(r'\((?:RPATH|RUNPATH)\).*\[([^\]]+)\]', text):
        search.extend(value.split(':'))
    required_nif = sorted(set(re.findall(r'\bUND\s+(enif_[A-Za-z0-9_]+)', text)))
    exports = set()
    for line in text.splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[0].endswith(':') and fields[6] != 'UND':
            exports.add(fields[7].split('@')[0])
    return {'needed': needed, 'search': search, 'required_nif_exports': required_nif, 'exports': exports}


def main(destination, architecture, receipt_path):
    machine = {'x86_64': 62, 'aarch64': 183}[architecture]
    root = Path(destination).resolve()
    paths = sorted(root.rglob('*'))
    files, symlinks, queue = [], [], []
    for path in paths:
        relative = '/' + str(path.relative_to(root))
        if path.is_symlink():
            target = os.readlink(path)
            resolved = (root / target.lstrip('/')) if target.startswith('/') else path.parent / target
            if not resolved.exists():
                resolved = Path(target) if target.startswith('/') else path.resolve()
            # Emerge's separate /system package is sealed by its own native
            # receipt; this optional package does not claim that service asset.
            if target.startswith('/system/gui/'):
                symlinks.append({'path': relative, 'target': target, 'owner': 'elixos-gui-renderer'})
                continue
            if not resolved.exists():
                raise RuntimeError(f'unresolved package symlink: {relative} -> {target}')
            item = {'path': relative, 'target': target}
            if resolved.is_file():
                resolved = resolved.resolve()
                item['resolved'] = describe(resolved)
                if resolved.is_relative_to(root):
                    item['resolved']['path'] = '/' + str(resolved.relative_to(root))
                queue.append(resolved)
            symlinks.append(item)
        elif path.is_file():
            item = {'path': relative, 'bytes': path.stat().st_size, 'sha256': sha(path)}
            files.append(item)
            queue.append(path)
    if not files:
        raise RuntimeError('empty optional Eval package')
    factory = root / 'factory'
    beam = None
    beam_exports = set()
    if factory.exists():
        candidates = list(Path('/usr/local/lib/erlang').glob('erts-*/bin/beam.smp'))
        if len(candidates) != 1:
            raise RuntimeError('expected exactly one target ERTS')
        beam = describe(candidates[0])
        beam_info = elf(candidates[0], machine)
        beam_exports = beam_info['exports']
        if not any(name.startswith('enif_') for name in beam_exports):
            raise RuntimeError('target ERTS does not export the native NIF API')
        beam['nif_exports'] = sorted(name for name in beam_exports if name.startswith('enif_'))
        queue.append(candidates[0])
        nif_paths = [str(path) for path in paths if path.is_file() and path.suffix == '.so']
        for name in ('QuickBEAM.Native', 'oxc_ex_nif', 'oxc_fmt_nif', 'oxc_lint_nif'):
            if not any(name in path and '/factory/lib/' in path for path in nif_paths):
                raise RuntimeError(f'missing required Eval NIF: {name}')
    seen, native = set(), []
    while queue:
        path = queue.pop().resolve()
        if path in seen:
            continue
        seen.add(path)
        info = elf(path, machine)
        if info is None:
            continue
        if info['required_nif_exports'] and not beam_exports.issuperset(info['required_nif_exports']):
            raise RuntimeError(f'ERTS is missing required NIF exports for {path}')
        record = describe(path)
        if path.is_relative_to(root):
            record['path'] = '/' + str(path.relative_to(root))
        record['machine'] = machine
        record['required_nif_exports'] = info['required_nif_exports']
        record['needed'] = []
        origin = path.parent
        directories = [Path(value.replace('${ORIGIN}', str(origin)).replace('$ORIGIN', str(origin))) for value in info['search']]
        directories.extend([root / 'lib', root / 'usr/lib', Path('/lib'), Path('/usr/lib'), Path('/usr/local/lib')])
        for name in info['needed']:
            resolved = next((directory / name for directory in directories if (directory / name).is_file()), None)
            if resolved is None:
                raise RuntimeError(f'unresolved native dependency {name} required by {path}')
            resolved = resolved.resolve()
            link = describe(resolved)
            link['soname'] = name
            if resolved.is_relative_to(root):
                link['path'] = '/' + str(resolved.relative_to(root))
            record['needed'].append(link)
            queue.append(resolved)
        native.append(record)
    if not native:
        raise RuntimeError('optional Eval package emitted no target ELF artifacts')
    result = {'format_version': 1, 'architecture': architecture, 'elf_machine': machine,
              'libc': 'musl', 'files': files, 'symlinks': symlinks,
              'elf': sorted(native, key=lambda item: item['path']), 'erts': beam,
              'builder_apk_database_sha256': sha(Path('/lib/apk/db/installed')),
              'target_execution_verified': False}
    output = root / receipt_path.lstrip('/')
    output.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(result, sort_keys=True, indent=2) + '\n').encode()
    with output.open('xb') as stream:
        stream.write(data)
    with Path(str(output) + '.sha256').open('x') as stream:
        stream.write(hashlib.sha256(data).hexdigest() + '  ' + output.name + '\n')


if __name__ == '__main__':
    main(*sys.argv[1:])
