#!/usr/bin/env python3
"""Prepare a pinned MTK build tree. Run from the ImmortalWrt source root."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TREE = Path.cwd()
LOCK = json.loads((ROOT / 'sources.lock.json').read_text())

def run(*args):
    subprocess.run(args, check=True)

def fetch_repo(spec, path):
    if path.exists():
        raise RuntimeError(f'Refusing to replace existing package: {path}')
    run('git', 'init', str(path))
    run('git', '-C', str(path), 'remote', 'add', 'origin', spec['url'])
    run('git', '-C', str(path), 'fetch', '--depth=1', 'origin', spec['commit'])
    run('git', '-C', str(path), 'checkout', '--detach', 'FETCH_HEAD')

def write(path, data, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, newline='\n')
    if executable:
        path.chmod(0o755)

def main():
    if not (TREE / 'include/kernel-6.6').is_file():
        raise RuntimeError('Run inside the pinned ImmortalWrt source tree')
    for name, spec in LOCK['packages'].items():
        fetch_repo(spec, TREE / 'package/akisen' / name)

    # This fork renamed the profile but retained the original board compatible.
    # Its preinit selector still uses the profile name, so stock EEPROM extraction
    # would be skipped. Read calibration from this unit on every boot, before kmods.
    preinit = TREE / 'target/linux/mediatek/filogic/base-files/lib/preinit/90_extract_caldata'
    original = preinit.read_text()
    original = original.replace('cmcc,rax3000m-emmc-mtk)', 'cmcc,rax3000m-emmc|\\\n\tcmcc,rax3000m-emmc-mtk)')
    original = original.replace('caldata_validate && exit 0\n\t\tcaldata_extract_mmc "factory" 0x0 0x1000',
        'caldata_extract_mmc "factory" 0x0 0x1000\n\t\tFIRMWARE=e2p\n\t\tcaldata_extract_mmc "factory" 0x0 0x5000', 1)
    if 'FIRMWARE=e2p' not in original:
        raise RuntimeError('EEPROM extraction patch did not apply')
    write(preinit, original, True)

    dts = TREE / 'target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-mtk.dts'
    contents = dts.read_text()
    if contents.count('max-frequency = <52000000>;') != 1:
        raise RuntimeError('Unexpected eMMC device tree')
    write(dts, contents.replace('max-frequency = <52000000>;', 'max-frequency = <26000000>;'))

    # Reserve upper mark bits for the optional campus service; OpenClash uses
    # lower bits. No packets are selected until that service is enabled.
    module = TREE / 'package/akisen/rkp-ipid/src/rkp-ipid.c'
    contents = module.read_text().replace('mark_capture = 0x10;', 'mark_capture = 0x40000000;').replace('mark_random = 0x20;', 'mark_random = 0x20000000;')
    write(module, contents)

    overlay = TREE / 'files'
    shutil.copytree(ROOT / 'files', overlay, dirs_exist_ok=True)
    for path in overlay.rglob('*'):
        if path.is_file() and path.read_bytes().startswith(b'#!/'):
            path.chmod(0o755)
    key = os.environ.get('WIFI_PASSWORD', '')
    if not re.fullmatch(r'[ -~]{8,63}', key):
        raise RuntimeError('WIFI_PASSWORD secret must contain 8-63 printable ASCII characters')
    # Never place the Wi-Fi secret in committed scripts or print it to logs.
    write(overlay / 'etc/akisen-wifi-key', key + '\n')
    (overlay / 'etc/akisen-wifi-key').chmod(0o600)

    core = LOCK['mihomo']
    archive = TREE / 'dl' / ('mihomo-' + core['version'] + '-arm64.gz')
    archive.parent.mkdir(exist_ok=True)
    if not archive.exists():
        with urllib.request.urlopen(core['url'], timeout=120) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != core['sha256']:
        raise RuntimeError('Mihomo checksum mismatch')
    binary = gzip.decompress(archive.read_bytes())
    if binary[:4] != b'\x7fELF' or int.from_bytes(binary[18:20], 'little') != 183:
        raise RuntimeError('Mihomo is not an AArch64 ELF executable')
    dest = overlay / 'etc/openclash/core/clash_meta'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(binary)
    dest.chmod(0o755)

    # Use the vendor's known driver options, but select exactly one current
    # device profile rather than copying its obsolete multi-device defconfig.
    vendor = (TREE / 'defconfig/mt7981-ax3000.config').read_text().splitlines()
    driver = [line for line in vendor if re.match(r'(CONFIG_(MTK_|CONNINFRA_|first_card)|# CONFIG_MTK_)', line)]
    write(TREE / '.config', '\n'.join(driver) + '\n' + (ROOT / 'rax3000m-emmc.config').read_text())
    run('make', 'defconfig')
    run(sys.executable, str(ROOT / 'scripts/verify.py'), 'config', str(TREE / '.config'))

if __name__ == '__main__':
    main()
