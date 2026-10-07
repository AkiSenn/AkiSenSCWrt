# AkiSenSCWrt — CMCC RAX3000M (eMMC 算力版) ImmortalWrt 云编译

> 目标设备：**CMCC RAX3000M eMMC 算力版**（MT7981B + 512M DDR4 + MT7976CN + MT7531，64G eMMC）
> 固件签名：**AkiSenn** ／ 主机名：**AkiSenSCWrt** ／ LAN：**192.168.2.1**

---

## 0. 结论速查（你问的几个问题）

| 你的问题 | 答案 |
|---|---|
| 用哪个 ImmortalWrt 版本 | **ImmortalWrt 24.10.6**（分支 `openwrt-24.10`，内核 **6.6.157 LTS**） |
| 用哪个 U-Boot | 二选一，见 [§3](#3-u-boot-选型与刷写)；版本必须和分区表**同源** |
| OpenClash 内核模块会不会缺 | 不会。所有必需 kmod 已**编译进固件**，见 [§5](#5-openclash-内核依赖已内建) |
| UA3F 和 OpenClash 能共存吗 | 技术上能（串行），但**按你要求已不集成 UA3F** |
| 校园网防检测怎么办 | 用 **rkp-ipid**（只改 IP 头 IPID，不碰流量转发，与 OpenClash 零冲突） |
| 要不要装 Docker | **没有**，已在 `.config` 里显式排除并加了自检 |
| `scwrt/` 便捷访问后缀 | **做不到，已放弃**，原因见 [§9](#9-没做的功能与原因) |
| vantage 主题 | 24.10 官方 feed **没有**这个包，改用 **Argon**（见 §9） |

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `rax3000m-emmc.config` | 固件 `.config`：设备、内核模块、插件全套选择 |
| `diy-part2.sh` | 编译前注入：拉取第三方源码、写默认配置、WiFi/UPnP/SMB 默认值 |
| `.github/workflows/build-immortalwrt-rax3000m-emmc.yml` | GitHub Actions 云编译流程 |

---

## 2. 怎么用（GitHub 云编译）

1. 新建一个 GitHub 仓库（公开即可，私有也行但 Actions 有分钟数限制），把本目录三个文件**保持目录结构**传上去：
   ```
   your-repo/
   ├── .github/workflows/build-immortalwrt-rax3000m-emmc.yml
   ├── rax3000m-emmc.config
   └── diy-part2.sh
   ```
2. 仓库 → **Actions** → 左侧 `Build AkiSenSCWrt (RAX3000M eMMC)` → **Run workflow**。
   - `openclash_branch`：保持 `master`（稳定版）。想要开发版选 `dev`。
   - `use_ccache`：第一次也勾上，第二次编译会快很多。
3. 编译约 **2～4 小时**（首次）。完成后在 run 页面底部下载 artifact：
   `AkiSenSCWrt-RAX3000M-eMMC-<run号>`。
4. 解压后你会拿到（文件名前面带日期前缀）：
   - `*sysupgrade.itb` ← **这是要刷的固件**（eMMC 用 FIT 格式）
   - `*recovery.itb` ← initramfs 救砖/内存启动镜像
   - `*emmc-gpt.bin`、`*emmc-preloader.bin`、`*emmc-bl31-uboot.fip` ← 只有走 OpenWrt U-Boot 方案才需要
   - `*.manifest`、`SHA256SUMS.txt`

> ⚠️ **重要**：编译日志里的"关键项自检"会告诉你哪些包没编进去。**务必看一眼**，
> 如果 `luci-app-openclash` 或任何 `kmod-*` 显示 `[!!]`，说明源码没拉到，先解决再刷。

---

## 3. U-Boot 选型与刷写

RAX3000M eMMC 的 `fip` 分区 = U-Boot（`bl2` 在 `boot0` 硬件分区，一般不用动）。
**U-Boot 和 GPT 分区表必须同源配套**，混用会导致启动失败。

### 先确认你现在用的是哪一套

SSH 到路由器执行：

```bash
# 看 fip 分区大小
fdisk -l /dev/mmcblk0 | grep -E "fip|production|rootfs"
# 看分区标签
blkid | grep -E "production|rootfs|kernel"
# 看 U-Boot 版本
strings $(blkid -t PARTLABEL=fip -o device) | grep -iE "U-Boot 20|dual_boot" | head
```

| 特征 | 方案 A（OpenWrt 官方 U-Boot） | 方案 B（lgs2007m / hanwckf U-Boot） |
|---|---|---|
| `fip` 大小 | **4 MB** | **2 MB** |
| 分区标签 | `production` | `kernel` / `rootfs` / `production` 均见 |
| 有 `dual_boot.current_slot` 环境变量 | 无 | 有 |
| 刷机方式 | U-Boot Web UI **可直接刷 `sysupgrade.itb`** | 老版本 Web UI **刷不了 `.itb`**，见下方警告 |

### 方案 A：OpenWrt / ImmortalWrt 官方 U-Boot（**推荐**）

优点：与 ImmortalWrt 24.10 官方发布完全同一套布局，版本天然一致，`sysupgrade` 升级最省心。

1. 进 U-Boot Web UI（电脑固定 IP `192.168.1.2/24`，按住 reset 上电等灯变色，浏览器开 `http://192.168.1.1`）。
2. 先刷 U-Boot：`http://192.168.1.1/uboot.html` 上传本次编译产出的 **`*emmc-bl31-uboot.fip`**。
3. 再刷分区表：`http://192.168.1.1/gpt.html` 上传 **`*emmc-gpt.bin`**。
4. 最后刷固件：`http://192.168.1.1` 上传 **`*sysupgrade.itb`**。

> 刷完进系统后格式化数据分区（给 SMB/硬盘用）：
> ```bash
> mkfs.ext4 $(blkid -t PARTLABEL=data -o device)   # 若 GPT 里有 data 分区
> ```

### 方案 B：lgs2007m 的 U-Boot（社区最常用，支持双系统切换）

> ## ⚠️ 重要更正（我上一版说错了，这里必须讲清楚）
>
> **文件名里的 `legacy-and-fit` 是指"能引导"两种固件，不等于"Web UI 能刷入" `.itb`。**
>
> 社区实测（[zzhi-github 的 RX30 升级记录](https://github.com/zzhi-github/CMCC-RX30-ImmortalWrt/blob/main/RX30%E7%AE%97%E5%8A%9B%E7%89%8823.05%E5%88%B024.10%E5%8D%87%E7%BA%A7.md)）：
> 用 lgs2007m 老版 U-Boot 的 Web UI 直接刷 `sysupgrade.itb` / `recovery.itb`，
> **会直接报错"不识别文件"，这条路是堵死的。**
>
> 也就是说要分清两件事：
>
> | 能力 | lgs2007m 老版 `_legacy-and-fit_` | 需要 |
> |---|---|---|
> | **引导**已写入的 `.itb` | ✅ 可以 | 有 `bootconf config-1#mt7981b-cmcc-rax3000m-emmc` |
> | **从 Web UI 刷入** `.itb` | ❌ 不行 | 换成 `-fip-fit.bin` 版 U-Boot |
>
> **所以如果你现在是 lgs2007m 的 U-Boot，有两个选择：**
>
> **选择 1（推荐，最省事）：在系统里升级，别走 U-Boot Web UI**
> 旧固件里直接进 LuCI → **系统 → 备份/刷写固件** → 上传 `sysupgrade.itb`。
> 因为老 U-Boot 能**引导** `.itb`，这条路是通的，而且**保留配置**。
> 这也是 24.10 之后正规的升级方式。
>
> **选择 2：换 U-Boot**
> 按[恩山那个帖子](https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8418450)的流程：
> 先刷 `emmc-gpt.bin` → 刷 `emmc-preloader.bin` → 换 `mt7981-cmcc_rax3000m-emmc-fip-fit.bin` 版 U-Boot →
> 刷 `initramfs-recovery.itb` 起来 → 再用 `sysupgrade.itb` 升级。
>
> 如果只是要稳定用，**选择 1 就够了**，没必要折腾 U-Boot。
>
> **最稳的还是方案 A** —— 官方 U-Boot + 官方 GPT，格式天然对齐，直接刷 `.itb` 没有这些坑。

**具体文件**（你这个机型就是这一个）：

```
mt7981_cmcc_rax3000m-emmc-fip_legacy-and-fit_20241026.bin
MD5 = 26ab5703bc760e5ec1e15815bc583dfd
```

来源：[lgs2007m/Actions-OpenWrt → Releases → Router-Flashing-Files](https://github.com/lgs2007m/Actions-OpenWrt/releases/tag/Router-Flashing-Files)
（下载 `RAX3000M-eMMC_XR30-eMMC_Tutorial-Files.7z`，里面同时含 uboot、GPT 分区表、原厂备份、救砖工具）

刷 U-Boot（SSH 里执行，先把文件传到 `/tmp`）：

```bash
md5sum /tmp/mt7981_cmcc_rax3000m-emmc-fip_legacy-and-fit_20241026.bin
# 必须等于 26ab5703bc760e5ec1e15815bc583dfd

dd if=/tmp/mt7981_cmcc_rax3000m-emmc-fip_legacy-and-fit_20241026.bin \
   of=$(blkid -t PARTLABEL=fip -o device) conv=fsync

# 校验
md5sum $(blkid -t PARTLABEL=fip -o device)
```

> ⚠️ **别拿错文件**：RAX3000Z 增强版（XR30-eMMC）的 U-Boot 是
> `mt7981_cmcc_xr30-emmc-fip_legacy-and-fit_*.bin`，MD5 不同，刷错起不来。
>
> ⚠️ **文件名日期有 20241007 / 20241026 两个版本在流传**。lgs2007m 教程正文里
> 两处写法不一致，压缩包里以实际文件名为准。**认准 MD5**，不要只看日期。
>
> ⚠️ **XR30 用户注意**：lgs2007m 的 U-Boot 把 `bootconf` 硬编码成
> `config-1#mt7981b-cmcc-rax3000m-emmc`，RAX3000M eMMC 用没问题。

选好分区表大小（建议 **512M / 512M**，给 overlay 和插件留足空间）后，
按教程第 3 步刷 GPT 并新建 `data` 分区。

### 方案 C：fry2022 的中文 DHCP U-Boot（双格式通吃，已实测分析）

来源：[恩山 tid=8405357](https://www.right.com.cn/forum/thread-8405357-1-1.html)（作者 fry2022，
基于 [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x)，DHCP 代码来自"湍清"）

**文件**：`mt7981_cmcc_rax3000m-emmc-fip.bin`（解压后 598,693 字节 / 585 KB）

我实际下载后做了二进制分析，结论如下：

| 项目 | 实测结果 |
|---|---|
| U-Boot 版本 | 2023.07（2024-09-12 16:03 构建） |
| 引导 `.bin`（Legacy） | ✅ `## Booting kernel from Legacy Image` + 完整 Legacy 校验分支 |
| 引导 `.itb`（FIT） | ✅ `FIT image found` / `## Loading %s from FIT Image` / hash 校验 |
| FIT 配置选择 | ✅ 设备树内含 **`u-boot,bootconf`** 签名 |
| DHCP | ✅ 内置 DHCP server，电脑无需固定 IP |
| 中文界面 | ✅ |
| 上传页 | `/bl2.html` `/uboot.html` `/gpt.html` + `simg` 单镜像 |

> ⚠️ **重要更正**：网上流传的"U-Boot 小 200K+ 对应 `.itb`、大 500K+ 对应 `.bin`"判据
> **不是铁律**。这个 U-Boot 585 KB，却是**两种格式通吃的合并构建**（镜像校验代码里
> Legacy 和 FIT 两个分支都在）。按体积猜会猜错。

**优点（相对方案 B）**：Web UI **能直接刷 `.itb`**，中文界面，DHCP 免固定 IP。

**代价 / 风险**：
1. 个人第三方构建，基于 U-Boot 2023.07，**无维护承诺**。
2. 换 U-Boot 是整条链路**最高危**的一步 —— 同一批帖子里有人"刷 uboot 折腾了 2 夜"，
   有人失手卡在 `169.x` 只能 TTL 救砖。
3. **刷前必须确认 GPT 分区布局**：社区有人因为"原来刷过主线所以 GPT 分区变了"，
   导致刷第三方固件一直 `update failed`，最后靠 TTL 刷 rootfs+gpt 才救回来。

**结论**：如果你只是要上 24.10 稳定用，**没必要换**，走方案 B 的"系统内升级"最稳。
只有当你打算**长期反复进 U-Boot 刷机**时，它的中文 + DHCP + 双格式通吃才值得这个风险。

### 关于 eMMC 频率（重要，别踩坑）

RAX3000M 算力版的 eMMC **体质较差，必须跑 26MHz**。跑 52MHz 会爆 `I/O error` 导致系统崩溃。
原厂和大佬固件默认都是 26MHz。刷完检查：

```bash
dmesg | grep 'I/O error'      # 应该没有输出
cat /sys/kernel/debug/mmc0/ios   # clock 应为 26000000
```

**不要**为了提速去刷 52MHz 固件——只能换 eMMC，不划算，而且 26MHz 约 20MB/s 日常够用。

---

## 4. 固件默认设置（刷完就是这个状态）

| 项目 | 值 |
|---|---|
| 主机名 | `AkiSenSCWrt` |
| 固件签名 / 版本号 | `AkiSenn` |
| LAN | `192.168.2.1/24`，DHCP 池 `192.168.2.100-199` |
| WAN | `eth1`，DHCP（**不拨号**，直接接校园网） |
| IPv6 | LAN `ip6assign 60` + RA/DHCPv6 server；WAN6 `dhcpv6` |
| 2.4G WiFi | SSID **`Aris`**，`psk2+ccmp`，HE40，txpower 20dBm |
| 5G WiFi | SSID **`Aris_5G`**，`psk2+ccmp`，HE80，txpower 20dBm |
| WiFi 密码 | `wdnmd123456789` |
| 时区 | `Asia/Shanghai`，NTP 阿里/腾讯 |
| 主题 | Argon |
| sysctl | `ip_forward=1`、`rp_filter=0`、`route_localnet=1`（透明代理必需） |

### 关于无线功放（按你的要求）

按你说的，**没有照抄你现有固件的高功率设置**：

- 你现在的固件 `txpower='100'`（= 最大 dBm），我这里是 **`20`（dBm）**，属于稳定区间。
- 走的是 **开源 mt76 驱动**，功放不做魔改，穿墙会比闭源略弱，但**不会抽风、不会掉线**。
- 想要信号更强可以自己在 LuCI 里调 `txpower`（建议不超过 `23`）并**观察稳定性**，
  不要一步拉到 100。

---

## 5. OpenClash 内核依赖（已内建）

这是你最担心的点。**kmod 与内核版本严格绑定**，事后从第三方源装必然报版本不符，
所以下面这些全部在 `.config` 里选中、随固件一起编译：

| 类别 | 已内建包 |
|---|---|
| TUN | `kmod-tun` |
| fw4/nftables TPROXY | `kmod-nft-tproxy` `kmod-nft-socket` `kmod-nft-core` `kmod-nft-nat` `kmod-nf-tproxy` |
| conntrack | `kmod-nf-conntrack` `kmod-nf-conntrack-netlink` |
| 进程名规则 | `kmod-inet-diag` `kmod-netlink-diag` |
| fullcone | 未选（见下方说明） |
| iptables 兼容路径 | `kmod-ipt-nat` `kmod-ipt-core` `kmod-nf-ipt` `iptables-mod-tproxy` `iptables-mod-extra` |
| DNS 劫持 | `dnsmasq-full`（含 nftset/ipset，**不是**精简版 dnsmasq） |
| 其他运行时 | `bash` `curl` `ca-bundle` `ip-full` `ruby` `ruby-yaml` `ruby-psych` `unzip` `luci-compat` |

> **关于 fullcone**：我实测 24.10 的内核模块定义文件里**没有** `kmod-nft-fullcone`
> （那是后续分支才加的）。它不是 OpenClash 的必需依赖，只是可选的 NAT 优化，
> 所以**故意没选**——宁可少一个可选优化，也不要冒编译报错的风险。
>
> 另外 `kmod-usb-common` 这个名字是**别名**，实际由 `kmod-usb-core` 提供，
> 所以 `.config` 里写 `CONFIG_PACKAGE_kmod-usb-core=y` 就够了。

刷完后可以自查：

```bash
# 内核版本
uname -r
# 模块是否都在
for m in tun nft_tproxy nft_socket nf_tproxy inet_diag nf_conntrack_netlink; do
  lsmod | grep -q "^$m" && echo "OK   $m" || echo "MISS $m"
done
# dnsmasq 是否 full 版
dnsmasq --version | head -1
```

---

## 6. 校园网防检测 & 与 OpenClash 的共存

### 为什么不集成 UA3F

你原来的需求里 UA3F 要装。但 **UA3F 会自己建立一套 TPROXY 规则去劫持 80/443**，
而 OpenClash 也在同一层做 TPROXY。两个都抢入口时：

- 规则顺序互相覆盖，表现为"代理时通时不通"；
- 排查极其痛苦（两边日志都正常，就是不工作）。

要正确共存必须做**串行**：OpenClash 收流量 → 上游指向 UA3F 的本地口 → UA3F 再出去。
这需要手工调两边的端口和防火墙规则，属于"能跑但不稳"的配置，
和你"**固件稳定为主**"的要求直接冲突。**所以按你的意思已经拿掉了。**

### 现在用什么：rkp-ipid

`rkp-ipid` 是一个**纯内核模块**，只做一件事：把出站包的 **IP 头的 IPID 字段**
改成递增（或随机），从而打乱 NAT 后面多设备共享一个出口 IP 时暴露的指纹。

**它和 OpenClash 零冲突**，因为它不碰流量转发、不建 TPROXY 规则，只在 netfilter 的
mangle 阶段改一个头部字段。

已注入的配套规则（`/etc/uci-defaults/98-akisen-ipid-fw`）：

```bash
iptables -t mangle -N IPID_MOD
iptables -t mangle -A FORWARD -j IPID_MOD
iptables -t mangle -A OUTPUT  -j IPID_MOD
# 内网/回环/组播 RETURN，其余打 mark 0x10/0x10
iptables -t mangle -A IPID_MOD -j MARK --set-xmark 0x10/0x10
```

> ⚠️ **两个必须知道的坑**：
> 1. **不能开 flow offloading / 硬件加速**（LuCI：网络 → 防火墙 → 软件流量分载）。
>    开了 rkp-ipid 就失效。我已经在默认配置里把它**关掉**了。
>    代价是 MT7981 的 NAT 加速没了，千兆以下校园网基本无感。
> 2. 默认用**递增**模式。README 里也写了随机模式很吃 CPU，不建议开。
>    想改参数编辑 `/etc/modules.d/99-rkp-ipid`：
>    `rkp-ipid mark_capture=0x40 mark_ramdom=0x80`

### 关于 `kmod-iptables-ipot`

你提到的 `kmod-iptables-ipot` 我在 OpenWrt 官方源、ImmortalWrt 源、
以及 kenzok8 等主流第三方 feed 里**都没有找到这个包名**。最接近的现有包是：

- `kmod-ipt-ipopt` / `iptables-mod-ipopt` —— **IP options 匹配模块**（已内建）
- `kmod-ipt-iprange`、`kmod-ipt-ipmark` —— 其他 IP 相关匹配

如果你指的是某个特定第三方仓库里的包，把仓库地址发我，我加进 `diy-part2.sh` 一起编译。

> **注意**：用户态防检测工具（UA2F/UA3F 这类）**不需要内核模块**，
> 所以它们不受内核版本限制，想加随时能装。

---

## 7. 硬盘 / SMB / 扩容

### 已内建（"硬盘插件完整"）

| 类别 | 包 |
|---|---|
| USB 存储 | `kmod-usb3` `kmod-usb-xhci-hcd` `kmod-usb-xhci-mtk` `kmod-usb-storage` `kmod-usb-storage-extras` `kmod-usb-storage-uas` |
| 文件系统 | `kmod-fs-ext4` `kmod-fs-f2fs` `kmod-fs-vfat` `kmod-fs-exfat` `kmod-fs-ntfs3` `kmod-fs-btrfs` `kmod-fs-xfs` `kmod-fs-autofs4` |
| 工具 | `e2fsprogs` `resize2fs` `f2fs-tools` `dosfstools` `exfatprogs` `ntfs-3g` `btrfs-progs` `xfs-mkfs` `smartmontools` `hdparm` `parted` `fdisk` `gdisk` `sgdisk` `usbutils` |
| 挂载 | `block-mount` `automount` `ntfs3-mount` `luci-app-diskman` |
| SMB | `samba4-server` `ksmbd-server` + 两个 LuCI 界面 |
| 压缩内存 | `kmod-zram` `zram-swap` |

### 64G eMMC 扩容 / 用上剩余空间

刷完先进 LuCI **系统 → 挂载点**，或 SSH：

```bash
# 看当前分区
fdisk -l /dev/mmcblk0
lsblk

# 若 GPT 方案里已有 data 分区，直接格式化并挂载
mkfs.ext4 -L data $(blkid -t PARTLABEL=data -o device)

# 然后在 LuCI 系统→挂载点 里把该分区挂到 /mnt/data，勾选启用，保存应用
```

SMB 默认共享目录是 `/mnt/sda1`（方便插 U 盘直接用）。
改共享目录：LuCI **网络存储 → 网络共享**。

---

## 8. 刷完后的建议操作顺序

1. **改 root 密码**：系统 → 管理权 → 主机密码（否则谁都能进）。
2. **确认上网**：状态 → 概览，WAN 拿到校园网 IP。
3. **配 OpenClash**：服务 → OpenClash → 配置文件订阅 → 更新 → 启动。
   - 建议模式：**Fake-IP (TUN)** 或 **Redir-Host**，先用默认跑通再调。
   - 首次启动会下载内核，需要能出网。
4. **配 EasyTier**：VPN → EasyTier，填网络名/密码，启动。
5. **开 SMB**：网络存储 → 网络共享，设置共享目录和用户。
6. **开 UPnP**：服务 → UPnP（默认已启用，按需开"启用安全模式"）。
7. **微信推送**：服务 → 微信推送，填 SendKey。
8. **确认 IPv6 可用**：状态 → 概览看 IPv6 前缀；或 `ip -6 addr`。

---

## 9. 没做的功能与原因

| 需求 | 状态 | 原因 |
|---|---|---|
| `scwrt/` 便捷访问后缀 | ❌ 未做 | OpenWrt/LuCI 的 uhttpd **原生不支持**任意 URL 前缀做"隐蔽入口"。硬做需要引入 nginx 改路由，还要改 LuCI 的 dispatch 路径，并且会和 OpenClash 的 DNS/HTTP 劫持互相干扰。收益极低、风险很高，与你"稳定为主"冲突。**保持默认访问 `http://192.168.2.1`**。 |
| vantage 主题 | ❌ 改用 Argon | ImmortalWrt 24.10 官方 feed（我实测拉了 `luci` + `packages` 索引，8397 个包）**没有 `luci-theme-vantage`**，immortalwrt/luci 的 24.10 分支也没有。Argon 是功能最接近、维护最好的替代品。如果你能提供 vantage 的源码仓库，我加进 `diy-part2.sh`。 |
| UA3F | ❌ 按你要求移除 | 与 OpenClash 抢 TPROXY 入口（详见 §6）。 |
| Docker | ✅ 已显式排除 | `.config` 里写了 `=n`，并且编译自检会**报错提示**如果被选中。 |
| 高功率无线 | ✅ 有意不做 | 你的原固件 `txpower=100` 不稳定；这里用 20dBm + 开源驱动，稳定优先。 |
| IPv6 | ✅ 已配 | LAN RA/DHCPv6 server + WAN6 dhcpv6。 |

---

## 10. 稳定版 vs 新版的取舍（为什么选 24.10.6）

| | **24.10.6（已选）** | 25.12.x |
|---|---|---|
| 内核 | 6.6.157（LTS） | 6.12 |
| 包管理 | `opkg`（`.ipk`） | `apk`（`.apk`） |
| 包生态 | 最成熟，第三方插件基本都只适配到 24.10 | 较新，部分插件还没跟上 |
| 你现在固件 | 25.12.0-rc2 / 内核 6.12.63 | — |
| 稳定性 | ✅ 维护分支，只收修 bug | ⚠️ 新特性带来新问题 |

**结论**：你要"稳定为主"，24.10.6 是正确选择。
代价是内核从 6.12 降到 6.6 —— 对 MT7981 路由器来说 6.6 LTS 完全够用，
而且 **kmod 一致性由编译保证**，不会有你担心的"装软件缺内核"问题。

> ⚠️ 正因为换了内核版本，**你现有固件里装的 `.ipk`/闭源 `.ko` 不能拿到新固件里用**。
> 所以本次把你要的功能全部编进固件了。

---

## 11. 故障排查

| 现象 | 排查 |
|---|---|
| OpenClash 启动报 `nft_tproxy module not found` | 编译自检里 `kmod-nft-tproxy` 应为 `[OK]`；刷完后 `lsmod \| grep nft_tproxy` |
| TUN 模式起不来 | 检查 `kmod-tun`；`lsmod \| grep tun` |
| DNS 劫持不生效 | `dnsmasq --version \| head -1` 必须含 `nftset`；否则装的是精简版 |
| 编译缺 `luci-app-openclash` | 看 Actions 日志里 `diy-part2.sh` 的"第三方包目录"输出，克隆失败会标 `[无]` |
| 编译卡住不动 | 正常，OpenWrt 全量编译 2-4 小时；看日志尾部是否在跑 `make[3]` |
| 刷完起不来 | 进 U-Boot Web UI（`192.168.1.1`）重刷；`recovery.itb` 可内存启动救急 |
| 无线起不来 | `factory` 分区（eeprom）可能被刷掉了，见 lgs2007m 教程第 6 节恢复 |
| `I/O error` 刷屏 | eMMC 跑了 52MHz，必须用 26MHz 固件 |

---

## 12. 参考来源

- U-Boot / 刷机教程：[lgs2007m/Actions-OpenWrt · Tutorial/RAX3000M-eMMC_XR30-eMMC.md](https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/RAX3000M-eMMC_XR30-eMMC.md)
- U-Boot 与 GPT 文件：[Router-Flashing-Files Releases](https://github.com/lgs2007m/Actions-OpenWrt/releases/tag/Router-Flashing-Files)
- OpenClash 依赖清单：[vernesong/OpenClash · 02-dependencies.md](https://github.com/vernesong/OpenClash/blob/dev/.github/skills/openclash-user-guide/02-dependencies.md)
- rkp-ipid：[OpenWrtLi/UA2F-rkp-ipid](https://github.com/OpenWrtLi/UA2F-rkp-ipid)
- EasyTier：[EasyTier/luci-app-easytier](https://github.com/EasyTier/luci-app-easytier)
- ImmortalWrt 包索引：[downloads.immortalwrt.org/releases/24.10.6/packages/aarch64_cortex-a53/](https://downloads.immortalwrt.org/releases/24.10.6/packages/aarch64_cortex-a53/)
