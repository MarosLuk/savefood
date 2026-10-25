#!/usr/bin/env python3
"""Online SQLite backup and restore into a NEW path; never copy live WAL files."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import tempfile


def checksum(path):
    value = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def checked_copy(source, target):
    source, target = Path(source).resolve(), Path(target).resolve()
    if not source.is_file():
        raise ValueError('Source database must exist.')
    if source == target or target.exists():
        raise ValueError('Target must be a NEW path. Existing databases are never overwritten.')
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temp_name = tempfile.mkstemp(prefix='.nvp-backup-', dir=target.parent)
    os.close(descriptor)
    temporary = Path(temp_name)
    try:
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True, timeout=30) as src:
            with sqlite3.connect(temporary) as dst:
                src.backup(dst, pages=256, sleep=0.025)
                if dst.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                    raise ValueError('Backup failed integrity check.')
                if dst.execute('PRAGMA foreign_key_check').fetchone() is not None:
                    raise ValueError('Backup has a broken foreign key.')
        with open(temporary, 'rb') as stream:
            os.fsync(stream.fileno())
        # Atomic no-overwrite promotion, including a racing backup process.
        os.link(temporary, target)
        temporary.unlink()
        return {'sha256': checksum(target), 'bytes': target.stat().st_size,
                'createdAt': dt.datetime.now(dt.timezone.utc).isoformat(),
                'integrity': 'ok'}
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['backup', 'restore', 'verify'])
    parser.add_argument('source')
    parser.add_argument('--target')
    parser.add_argument('--manifest')
    args = parser.parse_args()
    source = Path(args.source).resolve()
    if args.manifest:
        manifest = json.loads(Path(args.manifest).read_text())
        if checksum(source) != manifest['sha256']:
            raise ValueError('SHA-256 does not match the manifest.')
    if args.operation == 'verify':
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as db:
            if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Integrity verification failed.')
        print(json.dumps({'verified': True, 'sha256': checksum(source)}))
        return
    if not args.target:
        parser.error('--target is required (must not exist).')
    result = checked_copy(source, args.target)
    Path(str(Path(args.target).resolve()) + '.json').write_text(json.dumps(result, indent=2))
    if args.operation == 'backup':
        marker = Path(str(source) + '.backup.json')
        temporary = marker.with_suffix(marker.suffix + '.tmp')
        temporary.write_text(json.dumps(result))
        os.chmod(temporary, 0o600)
        os.replace(temporary, marker)
    print(json.dumps({**result, 'operation': args.operation}))


if __name__ == '__main__':
    main()
