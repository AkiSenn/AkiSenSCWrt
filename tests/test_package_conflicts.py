"""Regression checks for the package/install failure caused by NTFS providers."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify', Path(__file__).resolve().parents[1] / 'scripts/verify.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class PackageConflictTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.metadata = Path(self.directory.name) / '.packageinfo'
        self.metadata.write_text(
            'Package: ntfs3-mount\nConflicts: ntfs-3g\nProvides:\n'
            'Package: ntfs-3g\nConflicts:\nProvides:\n'
            'Package: alternate-ntfs\nConflicts:\nProvides: ntfs-3g\n')

    def test_current_ntfs3_selection_is_valid(self):
        verify.verify_declared_conflicts(self.metadata, {'ntfs3-mount', 'kmod-fs-ntfs3'})

    def test_original_ntfs_conflict_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'ntfs-3g / ntfs3-mount'):
            verify.verify_declared_conflicts(self.metadata, {'ntfs3-mount', 'ntfs-3g'})

    def test_conflicting_virtual_provider_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'alternate-ntfs / ntfs3-mount'):
            verify.verify_declared_conflicts(self.metadata, {'ntfs3-mount', 'alternate-ntfs'})


if __name__ == '__main__':
    unittest.main()
