# AkiSenSCWrt

自用 CMCC RAX3000M **eMMC 算力版**固件。主机名 AkiSenSCWrt，签名 AkiSenn。

基于 [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) 的 `openwrt-24.10-6.6` 社区分支，Linux **6.6.133**，MediaTek `mt_wifi 7.6.6.1` 厂商驱动。它不是官方 24.10 点版本；源码和 feeds 均锁定在 [sources.lock.json](sources.lock.json)。

克隆对比了 [lgs2007m/Actions-OpenWrt](https://github.com/lgs2007m/Actions-OpenWrt) 与 [KawaiiHachimi/Actions-rax3000m-emmc](https://github.com/KawaiiHachimi/Actions-rax3000m-emmc)，参考前者的 24.10 MTK 构建思路，使用当前源码的 eMMC MTK 目标。未沿用 21.02 或高功率 EEPROM。

## 功能

- OpenClash，预置经 SHA256 校验的 ARM64 Mihomo 核心；TUN、nftables TPROXY/socket、iptables/ipset、连接跟踪与诊断模块。
- EasyTier 核心、CLI 与 LuCI；Samba4 SMB 共享；UPnP；网页终端；微信推送。
- DiskMan、USB 3/UAS、分区和扩容工具、SMART、ext4/F2FS/NTFS3/exFAT/FAT/Btrfs/XFS。
- DHCP 上网与 IPv6；5GHz HE160、2.4GHz HE40，2.4GHz 保留共存机制。
- 原机 factory 校准、26MHz eMMC；不自动格式化、扩容或修改 GPT。
- Vantage 主题和面板，保留 Bootstrap 恢复入口。
- `kmod-rkp-ipid`、`kmod-ipt-ipopt` 与 `iptables-mod-ipopt`，附可关闭的校园网 TTL/IPID 功能。
- 不集成 Docker、dockerd、containerd、runc 或 Dockerman。
- 保留 MTK HNAT 模块和“网络 → MTK HNAT”开关，默认关闭。开启 OpenClash 或校园网功能时自动暂停硬件加速，避免绕过报文处理。

Vantage 上游只验证了 OpenWrt 25.12，24.10 和厂商无线接口仍需实机验证。160MHz 涉及 DFS，遇到雷达退避可改 HE80；不修改校准数据增加功率。

## 云编译与隐私

Actions → **Build AkiSenSCWrt (RAX3000M eMMC)** → Run workflow。需要两个 Actions Secrets：

| Secret | 用途 |
|---|---|
| `WIFI_PASSWORD` | 在构建工作目录注入无线密码 |
| `ARTIFACT_PASSWORD` | GnuPG AES256 加密编译产物 |

文档和源码不保存无线密码、订阅、推送密钥或设备配置备份。公开仓库只上传加密固件包及密文校验和；解密口令在本机另行保存。

缺少关键包、驱动不正确或意外选入 Docker 时，构建直接失败。产物包含源码锁定记录、manifest、SHA256 及同次编译的 IPK；后装内核模块需使用同次构建的包，不能保证官方源 kmod 的 ABI 兼容，不强制忽略依赖。

## 使用

见 [FLASHING.md](FLASHING.md)。OpenClash、EasyTier 和微信推送需配置个人订阅、网络或推送服务后启用。磁盘挂载和 SMB 目录通过 LuCI 设置，不默认匿名共享整块硬盘。

校园网功能默认关闭，避免在未知门户环境下改变报文。需要时在终端启用：

```sh
uci set campus.main.enabled='1'
uci commit campus
/etc/init.d/firewall restart
```

关闭时把 `enabled` 改为 `0` 后重启防火墙。规则只处理 WAN IPv4 TTL/IPID，防火墙重载或 WAN 重连后重新应用；IPv6 保持原生转发。IPID 不能覆盖 UA、时间戳等检测方式，也不替代门户认证。未集成额外 HTTP 流量代理。

本地编译见 [LOCAL-BUILD.md](LOCAL-BUILD.md)。
