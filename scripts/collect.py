#!/usr/bin/env python3
"""Package firmware and ABI-matched IPKs only after manifest verification."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
TREE = Path.cwd()
target = TREE / 'bin/targets/mediatek/filogic'
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
images = list(target.glob('*cmcc_rax3000m-emmc-mtk*sysupgrade.bin'))
assert len(images) == 1, 'Expected exactly one eMMC MTK sysupgrade image'
manifests = list(target.glob('*cmcc_rax3000m-emmc-mtk*.manifest'))
assert len(manifests) == 1, 'Missing device package manifest'
subprocess.run([sys.executable, str(ROOT / 'scripts/verify.py'), 'manifest', str(manifests[0])], check=True)
metadata_file = out / 'firmware-metadata.json'
subprocess.run([str(TREE / 'staging_dir/host/bin/fwtool'), '-i', str(metadata_file), str(images[0])], check=True)
metadata = json.loads(metadata_file.read_text())
assert 'cmcc,rax3000m-emmc' in metadata['supported_devices'], 'Wrong image board compatibility'
assert metadata['version']['version'] == '24.10-MTK', 'Custom release version missing from image'
assert metadata['version']['revision'] == 'AkiSenn', 'Custom signature missing from image'
for path in target.iterdir():
    device_image = 'cmcc_rax3000m-emmc-mtk' in path.name and path.suffix in ('.bin', '.manifest')
    build_record = path.suffix in ('.json', '.buildinfo') or path.name == 'sha256sums'
    if path.is_file() and (device_image or build_record):
        shutil.copy2(path, out / path.name)
shutil.copy2(TREE / '.config', out / 'build.config')
shutil.copy2(ROOT / 'sources.lock.json', out / 'sources.lock.json')
shutil.copy2(ROOT / 'FLASHING.md', out / 'FLASHING.md')
core = TREE / 'files/etc/openclash/core/clash_meta'
assert core.exists() and core.stat().st_size > 1000000, 'Missing embedded Mihomo core'
shutil.copy2(core, out / 'clash_meta.arm64')
# All selected and module-only packages keep the exact kernel dependency.
ipks = sorted((TREE / 'bin').rglob('*.ipk'))
assert ipks, 'Missing package archive'
with tarfile.open(out / 'packages-matching-this-firmware.tar.gz', 'w:gz') as archive:
    for package in ipks:
        archive.add(package, arcname=str(package.relative_to(TREE / 'bin')))
checksums = []
for path in sorted(out.iterdir()):
    if path.is_file() and path.name != 'SHA256SUMS.txt':
        checksums.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name)
(out / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n')
print('Verified firmware:', images[0].name)
print('ABI-matched package count:', len(ipks))
