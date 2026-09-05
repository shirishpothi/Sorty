#!/usr/bin/env python3
"""Serialize cooperating checkout commands and record validation provenance."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def snapshot(root):
    paths = git(root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard')
    digest = hashlib.sha256()
    for name in sorted(set(paths.split(b'\0')) - {b''}):
        path = root / os.fsdecode(name)
        digest.update(name + b'\0')
        try:
            digest.update(os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes())
        except FileNotFoundError:
            digest.update(b'<deleted>')
    return {'head': git(root, 'rev-parse', 'HEAD').decode().strip(),
            'files': digest.hexdigest(),
            'index': hashlib.sha256(git(root, 'diff', '--cached', '--binary')).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='fail if checkout changes during command')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('provide a command after --')
    root = Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').decode().strip())
    state = root / '.agent-local'
    state.mkdir(exist_ok=True)
    # Keep this inode in place. Unlinking a lock lets another process bypass it.
    with (state / 'checkout.lock').open('a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.seek(0)
            print('Checkout busy: ' + lock.read().strip(), file=sys.stderr)
            return 75
        lock.seek(0)
        lock.truncate()
        lock.write(json.dumps({'pid': os.getpid(), 'command': command, 'started': time.time()}))
        lock.flush()
        before = snapshot(root)
        started = time.monotonic()
        env = dict(os.environ)
        if args.check:
            env['SKIP_GIT_INJECT'] = 'true'
        # Inherit the lock so interruption of this wrapper cannot unlock a live child.
        child = subprocess.Popen(command, cwd=root, env=env, pass_fds=(lock.fileno(),))
        while True:
            try:
                result = child.wait(timeout=30)
                break
            except subprocess.TimeoutExpired:
                print(f'Running {child.pid}, {int(time.monotonic() - started)}s elapsed', flush=True)
            except KeyboardInterrupt:
                child.terminate()
                child.wait()
                result = 130
                break
        after = snapshot(root)
        changed = before != after
        report = {'command': command, 'before': before, 'after': after,
                  'changed': changed, 'exit': result, 'elapsed': time.monotonic() - started}
        report_path = state / f'run-{time.time_ns()}.json'
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Report: {report_path}', flush=True)
        if args.check and changed:
            print('Checkout changed during validation; rerun against stable inputs.', file=sys.stderr)
            return 76
        return result if result >= 0 else 128 - result


if __name__ == '__main__':
    sys.exit(main())
