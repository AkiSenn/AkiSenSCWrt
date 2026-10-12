"""Regression checks for source revision versus custom firmware branding."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verify', Path(__file__).resolve().parents[1] / 'scripts/verify.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class ImageIdentityTests(unittest.TestCase):
    def setUp(self):
        self.metadata = {
            'supported_devices': ['cmcc,rax3000m-emmc-mtk', 'cmcc,rax3000m-emmc'],
            'version': {'version': '24.10-MTK', 'revision': 'r0-ec9ef10', 'target': 'mediatek/filogic'},
        }
        self.release = (
            "DISTRIB_RELEASE='24.10-MTK'\nDISTRIB_REVISION='r0-ec9ef10'\n"
            "DISTRIB_TARGET='mediatek/filogic'\n"
            "DISTRIB_DESCRIPTION='ImmortalWrt 24.10-MTK AkiSenn'\n"
        )

    def test_custom_signature_does_not_replace_source_revision(self):
        verify.verify_image_identity(self.metadata, self.release)

    def test_missing_custom_signature_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'signature missing'):
            verify.verify_image_identity(self.metadata, self.release.replace('AkiSenn', 'r0-ec9ef10'))

    def test_wrong_device_is_rejected(self):
        self.metadata['supported_devices'] = ['cmcc,rax3000m']
        with self.assertRaisesRegex(AssertionError, 'board compatibility'):
            verify.verify_image_identity(self.metadata, self.release)

    def test_mismatched_source_revision_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'source revision mismatch'):
            verify.verify_image_identity(self.metadata, self.release.replace('r0-ec9ef10', 'other-source'))


if __name__ == '__main__':
    unittest.main()
