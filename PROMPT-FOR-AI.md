# 给另一个 AI 的提示词：ImmortalWrt 云编译（CMCC RAX3000M eMMC）

> 用法：把下面 `====` 之间的全部内容复制给另一个 AI（DeepSeek / ChatGPT 等）即可。
> 配套文件：`rax3000m-emmc.config`、`diy-part2.sh`、`build-local.sh`、`LOCAL-BUILD.md`
> （已存放在 https://github.com/AkiSenn/AkiSenSCWrt ，可直接取用）

---

=====================================================================

# 任务

帮我为 **CMCC RAX3000M eMMC（算力版）** 编译一个 **ImmortalWrt 固件**。
可以用 GitHub Actions 云编译，也可以指导我在本机 WSL2 上编译。请先给方案再动手，遇错要查根因不要盲目重试。

## 一、硬件与固件基本信息

- 路由器：**CMCC RAX3000M eMMC 算力版**（不是 NAND 版）
  - SoC：MT7981B；内存：512M DDR4；无线：MT7976CN；交换：MT7531；闪存：64G eMMC
  - 目标平台：`mediatek/filogic`，设备 ID：`cmcc,rax3000m`，架构：`aarch64_cortex-a53`
  - 重要：eMMC 版和 NAND 版**设备 ID 相同**，固件是 all-in-FIT（一个文件含两个设备树），靠 U-Boot 的 `bootconf` 选配置
- 要求版本：**ImmortalWrt 24.10.x 稳定分支**（`openwrt-24.10`，内核 6.6 LTS）
  - **不要 21.xx 及更早的版本**
  - 稳定优先。不要为了新特性上 25.12
- 现状：路由器上跑的是 OpenWrt 25.12.0-rc2（内核 6.12.63），可以 SSH 进去参考它已装的软件包

## 二、固件功能需求

### 必须实现

| 项目 | 要求 |
|---|---|
| 主机名 | `AkiSenSCWrt` |
| 自定义签名 / 版本号 | `AkiSenn` |
| LAN 地址 | `192.168.2.1/24` |
| WAN | 走 DHCP，**不拨号**（校园网环境） |
| IPv6 | **必须支持**（LAN RA/DHCPv6 server，WAN6 dhcpv6） |
| WiFi 名称 | `Aris`（2.4GHz）、`Aris_5G`（5GHz） |
| WiFi 密码 | `wdnmd123456789` |
| 5GHz 频宽 | **HE160（160MHz）** —— MT7981 支持，别缩成 80MHz |
| 2.4GHz 频宽 | HE40 |
| 无线驱动 | **开源 mt76**（稳定优先） |
| 主题 | Argon（vantage 主题官方 feed 里没有，如果找不到就用 Argon） |
| 磁盘管理 | diskman，**硬盘相关插件一定要完整** |
| SMB 共享 | samba4 |
| UPnP | 必须 |
| 终端 | ttyd |
| 微信推送 | luci-app-wechatpush |
| OpenClash | 必须，内核依赖必须齐全 |
| EasyTier | 必须（异地组网） |

### 明确不要

- **一定不要安装 Docker**（以及 dockerd / containerd / runc / dockerman）
- **UA3F 不要装**（它会和 OpenClash 抢 TPROXY 入口，冲突难排查）
- 不要照抄我现有固件的**无线功放设置**（那是 `txpower=100` 拉满，不稳定）。用保守值（20dBm），稳定优先

### 校园网防检测

需要防校园网代理/多设备检测的插件。考虑到已有 OpenClash，请用**只改 IP 头字段、不参与流量转发**的方案，例如 `rkp-ipid`（IPID 改写），它能和 OpenClash 透明共存。

如果你知道 `kmod-iptables-ipot` 这个包在哪个源里，可以一并加上（我在 OpenWrt 官方源、ImmortalWrt 源、kenzok8 等主流第三方 feed 里都没找到这个包名）。

## 三、技术要点（请务必遵守，这些是踩坑总结）

### 3.1 OpenClash 的内核模块必须编进固件

kmod 与内核版本严格绑定，**事后从第三方源安装必然报版本不符**。所以下面这些全部要在编译时内建：

```
kmod-tun
kmod-nft-tproxy  kmod-nft-socket  kmod-nft-core  kmod-nft-nat  kmod-nf-tproxy
kmod-nf-conntrack  kmod-nf-conntrack-netlink
kmod-inet-diag   kmod-netlink-diag
iptables-mod-tproxy  iptables-mod-extra  iptables-mod-ipopt
ipset  kmod-ipt-ipset
dnsmasq-full          ← 必须是 full 版（含 nftset/ipset），不能用精简版 dnsmasq
bash  curl  ca-bundle  ip-full  ruby  ruby-yaml  ruby-psych  unzip  luci-compat
```

### 3.2 必须关闭的三个选项（都是实际踩过的坑）

**① `CONFIG_RUBY_ENABLE_YJIT=n`（最关键，否则编译跑不完）**

`feeds/packages/lang/ruby/Makefile` 里写着：

```makefile
PKG_BUILD_DEPENDS:=ruby/host RUBY_ENABLE_YJIT:rust/host
config RUBY_ENABLE_YJIT
    default y if x86_64||aarch64     # aarch64 默认就打开
```

OpenClash 依赖 ruby → YJIT 在 aarch64 上默认开启 → **构建系统会从源码编译整个 Rust 编译器 + LLVM**（rustc 有 3795 个编译目标），实测 50 分钟都编不完，直接把 6 小时跑满超时。
OpenClash 用 ruby 只是解析 YAML，**不需要 YJIT**。

**② `CONFIG_USE_MKLIBS` 和 `CONFIG_STRIP_KERNEL_EXPORTS` 都不要开**

`config/Config-build.in` 原文：

```kconfig
config STRIP_KERNEL_EXPORTS
    depends on BROKEN          # 源码里明确标记"损坏/实验性"
    help
      ...might make the kernel incompatible with any kernel modules
      that were not selected at the time the kernel image was created

config USE_MKLIBS
    help
      ...will make the system libraries incompatible with most of the
      packages that are not selected during the build process
```

这两个和"以后还能正常装软件、不缺内核模块"的需求**直接冲突**。而且 `USE_MKLIBS` 在 aarch64 上会触发 library reduction 失败：

```
Library not found: .../root-mediatek/lib/libc.so in path: /usr/lib:...
make[2]: *** [package/Makefile:102: package/install] Error 1
```

**③ 不要开 `CONFIG_DEVEL=y`** —— 会阻止裁剪、保留调试符号、编译更慢、固件更大。

### 3.3 OpenClash 不要自己克隆源码

官方 `immortalwrt/luci` 的 `openwrt-24.10` 分支里**已经有 `luci-app-openclash`**，版本 `0.47.156`（和 `vernesong/OpenClash` 的 master 一致）。

如果又在 `package/` 下克隆一份，会出现同名包冲突：

```
package/luci-app-openclash              ← 你克隆的
package/feeds/luci/luci-app-openclash   ← feeds install 建立的
```

`make defconfig` 会**把 `CONFIG_PACKAGE_luci-app-openclash` 整个丢掉**，结果**编译成功但固件里没有 OpenClash**（静默失败，最危险）。
**修法：直接用官方 feed 的，不要克隆。**（只在 feed 确实没有时才退回克隆）

### 3.4 不要手写 `/etc/modules.d/99-rkp-ipid`

`rkp-ipid` 包的 Makefile 有 `AUTOLOAD:=$(call AutoLoad, 99, rkp-ipid)`，**它自己会生成这个文件**。如果你在 base-files overlay 里也塞一个同名文件，opkg 会报文件冲突导致 `package/install` 崩溃：

```
check_data_file_clashes: Package kmod-rkp-ipid wants to install file
  .../etc/modules.d/99-rkp-ipid
  But that file is already provided by package * base-files
make[2]: *** [package/Makefile:99: package/install] Error 255
```

### 3.5 feeds 要换 GitHub 镜像

ImmortalWrt 默认的 `feeds.conf.default` 里 `routing` / `telephony` / `video` 指向 `git.openwrt.org`，**国内经常不可达**，feeds update 会失败。全部换成 GitHub 镜像：

```
src-git packages https://github.com/immortalwrt/packages.git;openwrt-24.10
src-git luci https://github.com/immortalwrt/luci.git;openwrt-24.10
src-git routing https://github.com/openwrt/routing.git;openwrt-24.10
src-git telephony https://github.com/openwrt/telephony.git;openwrt-24.10
```

### 3.6 第三方包拉完后要重新登记 feeds

官方 feed 没有 `luci-app-easytier` / `easytier` / `rkp-ipid`，必须自己克隆到 `package/` 下。**克隆完要再跑一次 `./scripts/feeds install -a`**，否则 `make defconfig` 找不到它们，会把对应的 `CONFIG_PACKAGE_*` 丢掉。

克隆源：
- EasyTier：`https://github.com/EasyTier/luci-app-easytier.git`（分支 main；仓库含 `easytier` / `easytier-noweb` / `luci-app-easytier` 三个子包，easytier 是下载预编译二进制，不编 Rust）
- rkp-ipid：`https://github.com/OpenWrtLi/UA2F-rkp-ipid.git`（分支 master）

### 3.7 编译后必须做自检

**`make defconfig` 之后一定要检查 `.config`**，确认关键包都被保留了（因为 defconfig 会静默丢弃找不到的包）。逐项确认这些是 `=y`：

```
CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m
CONFIG_PACKAGE_luci-app-openclash      ← 曾经在这里发现被丢弃
CONFIG_PACKAGE_kmod-tun
CONFIG_PACKAGE_kmod-nft-tproxy
CONFIG_PACKAGE_dnsmasq-full
CONFIG_PACKAGE_luci-app-easytier
CONFIG_PACKAGE_easytier
CONFIG_PACKAGE_kmod-rkp-ipid
CONFIG_PACKAGE_luci-app-diskman
CONFIG_PACKAGE_luci-app-samba4
CONFIG_PACKAGE_luci-app-upnp
CONFIG_PACKAGE_luci-app-ttyd
CONFIG_PACKAGE_luci-app-wechatpush
CONFIG_PACKAGE_luci-theme-argon
```

并确认没有 Docker：
```bash
grep -E '^CONFIG_PACKAGE_(docker|dockerd|containerd|runc|luci-app-dockerman)=y' .config   # 应该无输出
```

**只要有一项缺失，先别刷机** —— 固件会缺功能，但编译仍然显示"成功"。

## 四、环境相关

### 如果用 GitHub Actions

- runner 用 `ubuntu-22.04`
- `timeout-minutes` 设 **360**（GitHub 硬上限 6 小时，别设更小自己提前砍死）
- 先 `jlumbroso/free-disk-space` 清盘（编译需要约 14GB）
- 装依赖、克隆源码、修 feeds、feeds install、注入配置、拉第三方包、**再 feeds install**、make defconfig + 自检、make download、make -j$(nproc)
- 编译失败时用 `make -j1 V=s` 重跑并把报错行 grep 出来（我遇到过的报错都藏在一大堆 samba rpath 警告里，不好找）

### 如果在本机 WSL2 编译

- **源码必须放 Linux 原生文件系统（`~/` 下），绝对不能放 `/mnt/c` 或 `/mnt/d`** —— 跨文件系统 I/O 慢 5–10 倍，且权限/大小写/符号链接问题会导致编译失败
- `.wslconfig` 建议配 16GB 内存、按实际核数配 processors
- 磁盘需要 30–50 GB
- 相比 GitHub Actions（151 分钟）本地通常 30–90 分钟，而且 ccache 常驻、可增量重编

## 五、其他要求

- **不要照抄我现有固件的高功率无线设置**。我用的是 `txpower` 拉满（100），不稳定。请用保守值（20dBm 左右）
- 便捷访问后缀 `scwrt/`：如果实现不了就直说，不要硬做（LuCI/uhttpd 原生不支持任意 URL 前缀做隐蔽入口，硬做要引 nginx 改路由，还会和 OpenClash 的 DNS/HTTP 劫持冲突）
- 刷机方式请一并说明。注意 **U-Boot 和 GPT 分区表必须来自同一套方案，不能混搭**（`fip` 分区 2MB vs 4MB 不通用）：
  - 官方 ITB 路线三件套（`https://drive.wrt.moe/uboot/mediatek/`）：
    - `immortalwrt-24.10.x-...-cmcc_rax3000m-emmc-gpt.bin`（17,408 B）
    - `immortalwrt-24.10.x-...-cmcc_rax3000m-emmc-preloader.bin`（221,501 B）
    - `mt7981-cmcc_rax3000m-emmc-fip-fit.bin`（218,048 B）
    - 刷写顺序：**GPT → BL2 → FIP → 固件**
  - 如果已在 lgs2007m 的 U-Boot + 他的 GPT 上，**别碰 U-Boot/GPT**，走 LuCI「系统 → 刷写固件」传 `sysupgrade.itb` 最稳
- **eMMC 不自动创建数据分区**，首次进系统要手动建一次（约 56GB，给 SMB/硬盘用）：
  `cfdisk /dev/mmcblk0` + `mkfs.ext4`
- **eMMC 频率必须 26MHz**。RAX3000M 算力版 eMMC 体质差，跑 52MHz 会 `I/O error` 崩溃

## 六、关于 AES 硬件加速（性能相关）

`mediatek/filogic` 的内核配置**默认已开启** ARMv8 加密扩展，不用额外加：

```
CONFIG_CRYPTO_AES_ARM64=y
CONFIG_CRYPTO_AES_ARM64_CE=y
CONFIG_CRYPTO_GHASH_ARM64_CE=y      ← GCM 的 GHASH 加速，最影响 AES-GCM 吞吐
CONFIG_CRYPTO_SHA2_ARM64_CE=y
```

另外可以加上 `kmod-crypto-hw-safexcel`（MTK EIP-197 加密引擎，优先级 300，高于 ARM CE 的 250）。
但注意：**它只有 mini 固件，功能有限**；完整固件需与 Marvell 签 NDA。
而且 **Clash.Meta / sing-box / Xray 是用户态程序，不走内核 crypto API** —— 它们的 AES 来自 Go 自带的 ARM64 汇编（用 CPU 的 AES 指令）。所以内核加密加速对出海速度帮助有限。
真正影响出海速度的是：TUN vs TPROXY 开销、代理内核选择（用 Meta 内核）、加密套件选择（**ChaCha20-Poly1305 常优于 AES-256-GCM**）。

## 七、参考资源

- 刷机/U-Boot 权威指南：https://github.com/cachenow/BuildAuto-Rax3000m/blob/main/刷机必备/RAX3000M_U-Boot_WebUI_升级降级指南.md
- lgs2007m 刷机教程：https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/RAX3000M-eMMC_XR30-eMMC.md
- OpenClash 依赖清单：https://github.com/vernesong/OpenClash/blob/dev/.github/skills/openclash-user-guide/02-dependencies.md
- ImmortalWrt 包索引：https://downloads.immortalwrt.org/releases/24.10.6/packages/aarch64_cortex-a53/

## 八、最终要交付给我

1. 完整的 `.config`（或等价的可复现配置）
2. `diy-part2.sh`（编译前注入脚本：主机名、WiFi、LAN、IPv6、SMB 默认值等）
3. 编译工作流（GitHub Actions 的 yml）或本地编译脚本
4. 一份说明文档：怎么编译、怎么刷机、有哪些坑

**如果我的要求里有互相冲突或做不到的地方，请直接告诉我，不要硬做。**

=====================================================================

---

## 附：这份提示词对应的已解决问题清单

如果对方 AI 遇到以下报错，直接对照（这些都已经解决，方案见上）：

| 报错 / 现象 | 根因 | 解决 |
|---|---|---|
| 编译卡在 `lang/rust` 几小时、6 小时超时 | Ruby YJIT 默认开启，拖进 Rust+LLVM | `CONFIG_RUBY_ENABLE_YJIT=n` |
| `make` 成功但固件里没有 OpenClash | 同名包冲突（自己克隆 vs feed） | 不要克隆，用官方 feed |
| `check_data_file_clashes` + `package/install Error 255` | 手写了 `/etc/modules.d/99-rkp-ipid` | 删掉，交给包 AUTOLOAD |
| `Library not found: .../libc.so` + `package/install Error 1` | `USE_MKLIBS` 在 aarch64 上崩 | 关 `USE_MKLIBS` / `STRIP_KERNEL_EXPORTS` |
| `feeds update` 失败、连不上 git.openwrt.org | 上游域名国内不可达 | 换 GitHub 镜像 |
| `make defconfig` 后 `CONFIG_PACKAGE_xxx` 消失 | 第三方包没登记进 feeds | 克隆后重跑 `feeds install -a` |
| 编译奇慢（比预期慢 5–10 倍） | 源码放在 `/mnt/c` | 移到 `~/` 下 |
