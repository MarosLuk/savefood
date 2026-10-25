import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('nvp_backup', Path(__file__).with_name('backup.py'))
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTest(unittest.TestCase):
    def test_online_wal_backup_and_fresh_restore_preserve_committed_data(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target, restored = [Path(directory) / n for n in ['live.sqlite', 'backup.sqlite', 'restored.sqlite']]
            with sqlite3.connect(source) as db:
                db.execute('PRAGMA journal_mode=WAL')
                db.execute('CREATE TABLE records(id INTEGER PRIMARY KEY,content TEXT)')
                db.execute("INSERT INTO records VALUES(1,'Účet a objednávka')")
                db.commit()
                result = backup.checked_copy(source, target)
                self.assertEqual(result['integrity'], 'ok')
                self.assertEqual(result['sha256'], backup.checksum(target))
                with self.assertRaises(ValueError):
                    backup.checked_copy(source, target)
                backup.checked_copy(target, restored)
            with sqlite3.connect(restored) as db:
                self.assertEqual(db.execute('SELECT content FROM records').fetchone()[0], 'Účet a objednávka')


if __name__ == '__main__':
    unittest.main()
