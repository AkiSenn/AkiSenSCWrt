# 本地编译指南（WSL2）— AkiSenSCWrt / CMCC RAX3000M eMMC

> 目标固件：ImmortalWrt **24.10.6**（分支 `openwrt-24.10`，内核 6.6 LTS）
> 目标设备：**CMCC RAX3000M eMMC 算力版**（`mediatek/filogic`，`cmcc,rax3000m`）
> 产出的刷机文件：**`*sysupgrade.itb`**

---

## 0. 为什么本地编译比 GitHub Actions 好

| | GitHub Actions | 本地 WSL2 |
|---|---|---|
| 耗时 | **151 分钟**（4 核 runner） | 通常 **30–90 分钟**（取决于 CPU 核数） |
| 单次会话上限 | **6 小时硬限制**，超时就废 | 无限制 |
| 磁盘 | 14 GB 可用，需先清盘 | 自己控制 |
| 调试 | 改一行要重跑几小时 | 可增量重编，只重编改动部分 |
| ccache | 每次跑从零恢复 | **本地常驻，二次编译极快** |
| 额度 | 每次消耗 Actions 分钟 | 免费 |

**结论：本地编译明显更划算。** 难点只在环境配置，配好一次就一劳永逸。

---

## 1. WSL2 环境准备（关键，别跳）

### 1.1 必须把源码放在 Linux 原生文件系统

```
✅ 正确： ~/immortalwrt-build            (即 \\wsl$\Ubuntu\home\<你>\...)
❌ 错误： /mnt/c/...  /mnt/d/...
```

**这是 WSL2 上最容易踩的坑。** 放在 `/mnt/c` 或 `/mnt/d` 会：

- 跨文件系统 I/O 慢几十倍（编译时间可能翻 5–10 倍）
- 文件权限、大小写敏感、符号链接行为不一致
- 大概率直接编译失败

### 1.2 确认 WSL2 资源够用

在 **Windows 侧**创建/编辑 `C:\Users\<你>\.wslconfig`：

```ini
[wsl2]
memory=16GB          # 建议 ≥ 8GB，16GB 更稳
processors=8         # 按你 CPU 实际核数填
swap=8GB
localhostForwarding=true
```

改完在 PowerShell 执行 `wsl --shutdown` 重启 WSL 生效。

> **磁盘空间**：源码 + 工具链 + 编译中间产物大约需要 **30–50 GB**。
> WSL2 的虚拟磁盘默认会随使用增长，但**不会自动收缩**，注意 C 盘余量。

### 1.3 检查 WSL2 确为 v2

在 PowerShell：

```powershell
wsl -l -v          # STATE 里应显示 VERSION = 2
```

如果是 1，执行：`wsl --set-version <发行版名> 2`

### 1.4 换国内 apt 源（可选，但强烈建议）

WSL2 里 Ubuntu 默认源在国内很慢。换成阿里/清华源，`apt install` 会快很多。

---

## 2. 用法

把这三个文件放进同一个目录（比如 `~/akisen/`）：

```
rax3000m-emmc.config      # 固件配置
diy-part2.sh              # 编译前注入脚本
build-local.sh            # 一键编译脚本
```

然后：

```bash
cd ~/akisen
chmod +x build-local.sh diy-part2.sh
./build-local.sh
```

脚本会自动完成：装依赖 → 克隆源码 → 修 feeds → 拉第三方包 → 应用配置 → 自检 → 下载 → 编译 → 打包产物。

### 可选环境变量

```bash
JOBS=8 ./build-local.sh                      # 指定并发数（默认 nproc）
WORKDIR=~/build/iw ./build-local.sh          # 指定工作目录
USE_CCACHE=0 ./build-local.sh                # 关掉 ccache
CCACHE_SIZE=50G ./build-local.sh             # 加大 ccache 容量
PACK_OUTPUT=0 ./build-local.sh               # 不自动打包产物
```

### 增量重编（改配置后）

不用重跑整个脚本。在源码目录里：

```bash
cd ~/immortalwrt-build/immortalwrt
make defconfig                 # 改过 .config 后必须跑
make -j$(nproc)                # 只重编改动的部分，很快
```

---

## 3. 六个坑（都是我实际踩过的）

### 坑 1：`git.openwrt.org` 不可达 → feeds 更新失败

ImmortalWrt 默认的 `feeds.conf.default` 里 `routing` / `telephony` / `video` 指向 `git.openwrt.org`，国内经常连不上，`feeds update` 直接失败。

**修法**：全部换成 GitHub 镜像（脚本已自动处理）：

```bash
cat > feeds.conf.default <<'EOF'
src-git packages https://github.com/immortalwrt/packages.git;openwrt-24.10
src-git luci https://github.com/immortalwrt/luci.git;openwrt-24.10
src-git routing https://github.com/openwrt/routing.git;openwrt-24.10
src-git telephony https://github.com/openwrt/telephony.git;openwrt-24.10
EOF
```

---

### 坑 2：Ruby YJIT 拖进整个 Rust 工具链 → 编译时间爆炸 ★最坑

**现象**：编译卡在 `package/feeds/packages/lang/rust`，日志里 `rustc` 有 3795 个编译目标，几小时都编不完。

**根因**（`feeds/packages/lang/ruby/Makefile` 原文）：

```makefile
PKG_BUILD_DEPENDS:=ruby/host RUBY_ENABLE_YJIT:rust/host

config RUBY_ENABLE_YJIT
    bool "Enable YJIT"
    depends on x86_64||aarch64
    default y if x86_64||aarch64      # ← aarch64 默认就打开！
```

**链路**：OpenClash 依赖 `ruby` → Ruby 的 YJIT 在 aarch64 上默认开启 → YJIT 需要 Rust → 从源码编译整个 Rust + LLVM。

**修法**：在 `.config` 里关掉。OpenClash 用 ruby 只是解析 YAML，**根本不需要 YJIT**：

```
CONFIG_RUBY_ENABLE_YJIT=n
```

> 实测效果：GitHub runner 上从"5 小时 51 分还没编完"降到"能正常跑完"。

---

### 坑 3：自己克隆 OpenClash → 同名包冲突 → 包被静默丢弃 ★最隐蔽

**现象**：编译**成功**，但固件里没有 OpenClash。`make defconfig` 后 `.config` 里就是没有 `CONFIG_PACKAGE_luci-app-openclash`。

**根因**：官方 `immortalwrt/luci` 的 `openwrt-24.10` 分支里**已经有 `luci-app-openclash`**，版本 `0.47.156`（和 `vernesong/OpenClash` 的 master 完全一致）。如果又在 `package/` 下克隆一份，就变成：

```
package/luci-app-openclash              ← 你克隆的
package/feeds/luci/luci-app-openclash   ← feeds install 建立的
```

同名冲突，defconfig 反而把这个包整个丢掉。

**修法**：**不要克隆 OpenClash**，直接用官方 feed 的。脚本已处理（并在 feed 缺失时才退回克隆）。

> 这个坑最危险的地方是：**编译报 success，不报错**。所以一定要看自检输出。

---

### 坑 4：手写 `/etc/modules.d/99-rkp-ipid` → opkg 文件冲突 → 打包崩溃

**现象**：

```
check_data_file_clashes: Package kmod-rkp-ipid wants to install file
  .../etc/modules.d/99-rkp-ipid
  But that file is already provided by package * base-files
opkg_install_cmd: Cannot install package kmod-rkp-ipid.
make[2]: *** [package/Makefile:99: package/install] Error 255
```

**根因**：`rkp-ipid` 包的 Makefile 里有 `AUTOLOAD:=$(call AutoLoad, 99, rkp-ipid)`，**它自己就会生成** `/etc/modules.d/99-rkp-ipid`。你再通过 base-files overlay 塞一个同名文件就冲突了。

**修法**：**不要自己创建这个文件**，交给包管理。`diy-part2.sh` 已修正。

---

### 坑 5：`USE_MKLIBS` / `STRIP_KERNEL_EXPORTS` → 打包失败 + 破坏兼容性

**现象**：

```
I: library reduction pass 1
Library not found: .../root-mediatek/lib/libc.so in path: /usr/lib:...
make[2]: *** [package/Makefile:102: package/install] Error 1
```

**根因**：`config/Config-build.in` 里的原文：

```kconfig
config STRIP_KERNEL_EXPORTS
    depends on BROKEN              # ← 源码里明确标记"损坏"
    help
      ...might make the kernel incompatible with any kernel modules
      that were not selected at the time the kernel image was created

config USE_MKLIBS
    help
      ...will make the system libraries incompatible with most of the
      packages that are not selected during the build process
```

**这两个选项和"以后还能装软件、不缺内核模块"的需求直接冲突**（`STRIP_KERNEL_EXPORTS` 会让内核和未编入的 kmod 不兼容，`USE_MKLIBS` 会让库和未选中的包不兼容）。

**修法**：两个都**不要开**：

```
# CONFIG_STRIP_KERNEL_EXPORTS is not set
# CONFIG_USE_MKLIBS is not set
```

---

### 坑 6：`CONFIG_DEVEL=y` → 编译变慢、固件变大

`CONFIG_DEVEL` 会阻止裁剪、保留调试符号、显著增大编译量与固件体积。**对"要按时跑完"的场景是负收益，别开。**

---

## 4. 编译后必看：自检输出

编译脚本会打印一份自检，**一定要确认全绿**：

```
  [OK ] 目标设备 cmcc_rax3000m
  [OK ] CONFIG_PACKAGE_luci-app-openclash      ← 重点！曾在这里抓到缺失
  [OK ] CONFIG_PACKAGE_kmod-tun
  [OK ] CONFIG_PACKAGE_kmod-nft-tproxy
  [OK ] CONFIG_PACKAGE_kmod-nft-socket
  [OK ] CONFIG_PACKAGE_kmod-nf-tproxy
  [OK ] CONFIG_PACKAGE_kmod-inet-diag
  [OK ] CONFIG_PACKAGE_kmod-nf-conntrack-netlink
  [OK ] CONFIG_PACKAGE_dnsmasq-full
  [OK ] CONFIG_PACKAGE_luci-app-easytier
  [OK ] CONFIG_PACKAGE_easytier
  [OK ] CONFIG_PACKAGE_kmod-rkp-ipid
  ... (磁盘/存储/SMB/UPnP 等)
  [OK ] CONFIG_RUBY_ENABLE_YJIT 已关闭
  [OK ] CONFIG_USE_MKLIBS 已关闭
  [OK ] 无 Docker
```

**只要有 `[!!]`，先别刷机** —— 那说明成品会缺功能（而且很可能编译仍显示"成功"）。

---

## 5. 产物说明

产物在 `immortalwrt/bin/targets/mediatek/filogic/`，脚本会额外打包到 `~/akisen-firmware-<时间戳>/`：

| 文件 | 用途 |
|---|---|
| **`*squashfs-sysupgrade.itb`** | ★ **这就是要刷的固件** |
| `*initramfs-recovery.itb` | 内存启动的救砖/临时系统镜像 |
| `*emmc-gpt.bin` | eMMC GPT 分区表 |
| `*emmc-preloader.bin` | eMMC BL2 / Preloader |
| `*emmc-bl31-uboot.fip` | U-Boot |
| `*.manifest` | **固件内所有软件包清单**（核对功能用这个） |
| `*.config` | 本次实际生效的编译配置 |
| `SHA256SUMS.txt` | 校验和 |

**核对功能是否真的编进去了**，看 manifest 最准：

```bash
grep -E 'openclash|easytier|rkp-ipid|samba4|diskman|upnp|ttyd|wechatpush|argon' *.manifest
```

---

## 6. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `feeds update` 失败、连不上 git.openwrt.org | 坑 1，换 GitHub 镜像 |
| 卡在 `lang/rust` 几个小时 | 坑 2，关 `CONFIG_RUBY_ENABLE_YJIT` |
| 编译成功但固件缺 OpenClash | 坑 3，别克隆 OpenClash |
| `check_data_file_clashes` / `package/install Error 255` | 坑 4，别手写 `/etc/modules.d/99-rkp-ipid` |
| `Library not found: .../libc.so` | 坑 5，关 `USE_MKLIBS` |
| 编译奇慢（比预期慢 5-10 倍） | 源码放在了 `/mnt/c`，移到 `~/` 下 |
| WSL2 内存不足 / 被 OOM 杀掉 | 调大 `.wslconfig` 的 `memory`，或降低 `JOBS` |
| 磁盘写满 | 清理：`make clean`（保留 .config）或 `make dirclean`（全清） |

### 清理命令

```bash
make clean        # 删编译产物，保留 .config 和工具链（改配置后用）
make dirclean     # 删工具链和所有产物，保留 .config
make distclean    # 全部清掉，连 .config 都没了
```

---

## 7. 关键配置速查（这套方案的要点）

| 项目 | 值 |
|---|---|
| 分支 | `openwrt-24.10`（ImmortalWrt 24.10.6，内核 6.6.157） |
| 目标 | `mediatek/filogic`，设备 `cmcc_rax3000m` |
| 主机名 | `AkiSenSCWrt` |
| 签名 | `AkiSenn` |
| LAN | `192.168.2.1/24` |
| WAN | `eth1` DHCP（不拨号），IPv6 `dhcpv6` |
| WiFi | `Aris`（2.4G，HE40）/ `Aris_5G`（5G，**HE160**），密码 `wdnmd123456789` |
| 无线驱动 | **开源 mt76**，功放 20dBm（不拉满） |
| 主题 | Argon |
| Docker | **明确排除** |

**OpenClash 必需的内核模块（全部编进固件）**：

```
kmod-tun  kmod-nft-tproxy  kmod-nft-socket  kmod-nf-tproxy
kmod-inet-diag  kmod-nf-conntrack-netlink  kmod-nft-nat  kmod-nft-core
iptables-mod-tproxy  iptables-mod-extra  iptables-mod-ipopt  ipset
dnsmasq-full（必须是 full 版，含 nftset）
```

> 这些**必须编译进固件**。kmod 与内核版本严格绑定，事后从第三方源安装必然报版本不符。

**AES 硬件加速**：`mediatek/filogic` 的内核配置**默认已开启** ARMv8 加密扩展，无需额外操作：

```
CONFIG_CRYPTO_AES_ARM64=y
CONFIG_CRYPTO_AES_ARM64_CE=y
CONFIG_CRYPTO_GHASH_ARM64_CE=y      ← GCM 的 GHASH 加速
CONFIG_CRYPTO_SHA2_ARM64_CE=y
```

另外配置里已包含 `kmod-crypto-hw-safexcel`（MTK EIP-197 加密引擎，优先级 300 高于 ARM CE 的 250）。
注意它只有 **mini 固件**（功能有限），完整固件需与 Marvell 签 NDA。

> ⚠️ **重要认知**：Clash.Meta / sing-box / Xray 这类**用户态代理核心的 AES 来自 Go 自带的 ARM64 汇编实现**（用 CPU 的 AES 指令），**不经过内核 crypto API**。所以内核加密加速对它们帮助有限。
> 真正影响出海速度的是：TUN vs TPROXY 开销、代理核心效率、加密套件选择（ChaCha20 常优于 AES-GCM）。

---

## 8. 刷机（简要）

⚠️ **U-Boot 和 GPT 必须来自同一套方案，不能混搭**（`fip` 分区 2MB vs 4MB 不通用）。

| 你现在的情况 | 做法 |
|---|---|
| 已在 lgs2007m U-Boot + 他的 GPT 上 | **别碰 U-Boot/GPT**，LuCI「系统 → 刷写固件」传 `sysupgrade.itb`（保留配置） |
| 已在官方 U-Boot + 官方 GPT 上 | 同上，或 U-Boot Web UI 直接刷 |
| 要换成官方 ITB 路线 | 整套换：GPT → BL2 → FIP → 固件（顺序不能跳） |

官方 ITB 路线三件套（`https://drive.wrt.moe/uboot/mediatek/`）：

```
GPT:    immortalwrt-24.10.x-mediatek-filogic-cmcc_rax3000m-emmc-gpt.bin          (17,408 B)
BL2:    immortalwrt-24.10.x-mediatek-filogic-cmcc_rax3000m-emmc-preloader.bin   (221,501 B)
U-Boot: mt7981-cmcc_rax3000m-emmc-fip-fit.bin                                    (218,048 B)
```

**eMMC 不自动建数据分区** —— 首次进系统后手动建一次（约 56GB，给 SMB/硬盘用）：

```bash
cfdisk /dev/mmcblk0        # 用剩余空间新建分区，保持对齐
mkfs.ext4 /dev/mmcblk0pX   # X 换成新分区号
```

**eMMC 频率必须 26MHz**（RAX3000M 算力版体质差，52MHz 会 `I/O error` 崩溃）：

```bash
dmesg | grep 'I/O error'          # 应无输出
cat /sys/kernel/debug/mmc0/ios    # clock 应为 26000000
```
