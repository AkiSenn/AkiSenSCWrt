#!/usr/bin/env python3
"""Fail the build when required selections or final manifest entries are missing."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(r'^(docker(?:d)?|containerd|runc|luci-app-dockerman|luci-app-docker)(?:$|-)')
REQUIRED = '''luci-app-openclash dnsmasq-full kmod-tun kmod-nft-tproxy
kmod-nft-socket kmod-nf-tproxy kmod-nf-socket kmod-inet-diag
kmod-nf-conntrack-netlink kmod-ipt-ipopt iptables-mod-ipopt iptables-nft
kmod-mt_wifi kmod-conninfra kmod-warp kmod-mediatek_hnat mtwifi-cfg luci-app-mtwifi-cfg
kmod-rkp-ipid easytier luci-app-easytier luci-app-samba4 samba4-server
luci-app-diskman luci-app-upnp luci-app-ttyd luci-app-wechatpush
luci-theme-vantage luci-app-vantage luci-theme-bootstrap
kmod-usb-storage kmod-usb-storage-uas kmod-fs-ext4 kmod-fs-f2fs
kmod-usb-net kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm usbutils
kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-vfat kmod-fs-btrfs kmod-fs-xfs
block-mount ntfs3-mount cfdisk parted sgdisk resize2fs mkf2fs f2fsck smartmontools
odhcp6c odhcpd-ipv6only luci-proto-ipv6 bash curl ruby ruby-yaml'''.split()

def verify_declared_conflicts(filename, selected):
    """Check the actual feed metadata, including conflicts with virtual providers."""
    packages = {}
    current = None
    for line in Path(filename).read_text().splitlines():
        if line.startswith('Source-Makefile:'):
            current = None
        elif line.startswith('Package: '):
            current = line.split(':', 1)[1].strip()
            packages[current] = {'conflicts': [], 'provides': []}
        elif current and line.startswith(('Conflicts:', 'Provides:')):
            field, value = line.split(':', 1)
            packages[current][field.lower()] = value.split()
    providers = {}
    for name in selected:
        for alias in [name] + packages.get(name, {}).get('provides', []):
            providers.setdefault(alias, set()).add(name)
    conflicts = set()
    for name in selected:
        for other in packages.get(name, {}).get('conflicts', []):
            for provider in providers.get(other, set()) - {name}:
                conflicts.add(tuple(sorted((name, provider))))
    assert not conflicts, 'Conflicting firmware packages: ' + '; '.join(' / '.join(pair) for pair in sorted(conflicts))
    print('Feed metadata: no declared conflicts among installed packages')

def main():
    mode, filename = sys.argv[1:3]
    data = Path(filename).read_text()
    if mode == 'config':
        selected = set(re.findall(r'^CONFIG_PACKAGE_([^=]+)=y$', data, re.M))
        target = 'CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m-emmc-mtk=y'
        assert target in data.splitlines(), 'Wrong RAX3000M eMMC MTK target'
        for setting in ('CONFIG_WARP_VERSION=2', 'CONFIG_WARP_CHIPSET="mt7981"'):
            assert setting in data.splitlines(), 'Wrong MT7981 WARP hardware setting: ' + setting
        for setting in ('CONFIG_DEVEL=y', 'CONFIG_CCACHE=y'):
            assert setting in data.splitlines(), 'Compiler cache prerequisite missing: ' + setting
        for setting in ('CONFIG_IMAGEOPT=y', 'CONFIG_VERSIONOPT=y', 'CONFIG_VERSION_NUMBER="24.10-MTK"', 'CONFIG_VERSION_CODE="AkiSenn"'):
            assert setting in data.splitlines(), 'Custom firmware version setting missing: ' + setting
        for option in ('RUBY_ENABLE_YJIT', 'USE_MKLIBS', 'STRIP_KERNEL_EXPORTS'):
            assert f'CONFIG_{option}=y' not in data.splitlines(), f'Unsafe build option: {option}'
        if len(sys.argv) > 3:
            assert re.search(r'^CONFIG_CCACHE_DIR="[^"\n]+"$', data, re.M), 'Compiler cache directory was discarded by Kconfig'
            verify_declared_conflicts(sys.argv[3], selected)
    elif mode == 'manifest':
        selected = {line.split(' - ')[0] for line in data.splitlines()}
        assert 'kernel' in selected, 'Missing kernel package'
        assert not any(p.startswith(('kmod-mt76', 'kmod-mt7915e')) for p in selected), 'Wrong Wi-Fi driver'
    else:
        raise ValueError(mode)
    missing = sorted(set(REQUIRED) - selected)
    assert not {'ntfs-3g', 'ntfs3-mount'} <= selected, 'Conflicting NTFS mount providers: ntfs-3g / ntfs3-mount'
    forbidden = sorted(p for p in selected if FORBIDDEN.match(p))
    assert not missing, 'Required packages missing: ' + ', '.join(missing)
    assert not forbidden, 'Docker/container packages selected: ' + ', '.join(forbidden)
    print(f'{mode}: all {len(REQUIRED)} required packages present; Docker excluded')

if __name__ == '__main__':
    main()
