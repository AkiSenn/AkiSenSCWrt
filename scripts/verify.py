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
kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-vfat kmod-fs-btrfs kmod-fs-xfs
block-mount cfdisk parted sgdisk resize2fs mkf2fs f2fsck smartmontools
odhcp6c odhcpd-ipv6only luci-proto-ipv6 bash curl ruby ruby-yaml'''.split()

def main():
    mode, filename = sys.argv[1:3]
    data = Path(filename).read_text()
    if mode == 'config':
        selected = set(re.findall(r'^CONFIG_PACKAGE_([^=]+)=y$', data, re.M))
        target = 'CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m-emmc-mtk=y'
        assert target in data.splitlines(), 'Wrong RAX3000M eMMC MTK target'
        for option in ('RUBY_ENABLE_YJIT', 'USE_MKLIBS', 'STRIP_KERNEL_EXPORTS'):
            assert f'CONFIG_{option}=y' not in data.splitlines(), f'Unsafe build option: {option}'
    elif mode == 'manifest':
        selected = {line.split(' - ')[0] for line in data.splitlines()}
        assert 'kernel' in selected, 'Missing kernel package'
        assert not any(p.startswith(('kmod-mt76', 'kmod-mt7915e')) for p in selected), 'Wrong Wi-Fi driver'
    else:
        raise ValueError(mode)
    missing = sorted(set(REQUIRED) - selected)
    forbidden = sorted(p for p in selected if FORBIDDEN.match(p))
    assert not missing, 'Required packages missing: ' + ', '.join(missing)
    assert not forbidden, 'Docker/container packages selected: ' + ', '.join(forbidden)
    print(f'{mode}: all {len(REQUIRED)} required packages present; Docker excluded')

if __name__ == '__main__':
    main()
