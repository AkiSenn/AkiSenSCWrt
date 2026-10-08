#!/bin/bash
#
# ImmortalWrt 24.10.6 本地编译脚本 — CMCC RAX3000M (eMMC 算力版)
# AkiSenSCWrt / AkiSenn
#
# 适用：WSL2 / Ubuntu / Debian 上的本地编译（也可用于 GitHub Actions）
#
# 用法：
#   chmod +x build-local.sh
#   ./build-local.sh
#
# 全部选项可用环境变量覆盖，例如：
#   JOBS=8 ./build-local.sh
#   WORKDIR=~/build/iw ./build-local.sh
#
set -euo pipefail

# ============================================================
# 0. 可配置项
# ============================================================
# 工作根目录。★ WSL2 上必须放在 Linux 原生文件系统（~/ 下），
#   千万不要放 /mnt/c 或 /mnt/d —— 跨文件系统 I/O 极慢，
#   而且大小写敏感/权限/符号链接都会出问题，编译大概率失败。
WORKDIR="${WORKDIR:-$HOME/immortalwrt-build}"

REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-24.10}"     # 24.10 稳定分支，内核 6.6 LTS

# 并发数。WSL2 里建议 = 分到的 vCPU 数，或略少（留 1 核给系统）
JOBS="${JOBS:-$(nproc)}"

# 是否启用 ccache（二次编译提速明显，强烈建议开）
USE_CCACHE="${USE_CCACHE:-1}"
CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
CCACHE_SIZE="${CCACHE_SIZE:-20G}"

# 编译完成后是否自动打包产物到 $HOME
PACK_OUTPUT="${PACK_OUTPUT:-1}"

TARGET_DIR="bin/targets/mediatek/filogic"

# ============================================================
# 1. 依赖检查与安装
# ============================================================
echo "=============================================================="
echo " ImmortalWrt 24.10.6 本地编译 — RAX3000M eMMC"
echo " 工作目录: $WORKDIR"
echo " 并发数  : $JOBS"
echo " ccache  : $USE_CCACHE"
echo "=============================================================="

need_pkgs=(
  ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential
  bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex
  gawk gcc-multilib g++-multilib gettext genisoimage git gperf haveged
  help2man intltool lib32gcc-s1 lib32stdc++6 libc6-dev-i386 libelf-dev
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev
  libncursesw5-dev libpython3-dev libreadline-dev libssl-dev libtool lld
  libncurses-dev msmtp nano ninja-build p7zip p7zip-full patch pkgconf
  python3 python3-pip python3-ply python3-docutils python3-pkg-resources
  qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo
  uglifyjs unzip vim wget xmlto xxd zlib1g-dev zstd file
)

echo ">>> [1/8] 检查编译依赖..."
missing=0
for p in "${need_pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || { missing=1; break; }
done

if [ "$missing" -eq 1 ]; then
    echo "    缺少依赖，开始安装（需要 sudo 密码）..."
    sudo apt-get update -qq
    sudo -E apt-get install -y "${need_pkgs[@]}"
else
    echo "    [OK] 依赖齐全，跳过安装"
fi

# ============================================================
# 2. 克隆源码
# ============================================================
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ -d immortalwrt/.git ]; then
    echo ">>> [2/8] 源码已存在，跳过克隆（如需重来请手动删除 $WORKDIR/immortalwrt）"
else
    echo ">>> [2/8] 克隆 ImmortalWrt 源码（$REPO_BRANCH）..."
    git clone --depth=1 -b "$REPO_BRANCH" "$REPO_URL" immortalwrt
fi

cd immortalwrt

# ============================================================
# 3. 修 feeds（★ 关键坑）
# ============================================================
# ImmortalWrt 默认的 feeds.conf.default 里，routing/telephony/video 指向
# git.openwrt.org。这个域名在国内经常不可达，feeds update 会直接失败。
# 全部换成 GitHub 镜像。
echo ">>> [3/8] 替换 feeds 为 GitHub 镜像（避开不可达的 git.openwrt.org）..."
cat > feeds.conf.default <<'EOF'
src-git packages https://github.com/immortalwrt/packages.git;openwrt-24.10
src-git luci https://github.com/immortalwrt/luci.git;openwrt-24.10
src-git routing https://github.com/openwrt/routing.git;openwrt-24.10
src-git telephony https://github.com/openwrt/telephony.git;openwrt-24.10
EOF
cat feeds.conf.default

echo ">>> [4/8] 更新并安装 feeds（第一次比较慢，约 5-15 分钟）..."
./scripts/feeds update -a
./scripts/feeds install -a

# ============================================================
# 4. 拉第三方包（官方 feed 没有的）
# ============================================================
echo ">>> [5/8] 拉取第三方包源码..."

clone_pkg() {
    _name="$1"; _dest="$2"; _branch="$3"; shift 3
    _target="$WORKDIR/immortalwrt/package/${_dest}"
    [ -d "$_target" ] && { echo "    [跳过] ${_name} 已存在"; return 0; }
    for _repo in "$@"; do
        if git clone --depth=1 -b "$_branch" "$_repo" "$_target" 2>/dev/null; then
            echo "    [OK] ${_name}"; rm -rf "${_target}/.github"; return 0
        fi
        rm -rf "$_target"
    done
    echo "    [失败] ${_name}"
    return 1
}

# ★★ OpenClash 不要自己克隆！★★
# 官方 immortalwrt/luci 的 openwrt-24.10 分支里已经有 luci-app-openclash，
# 版本就是 0.47.156（与 vernesong/OpenClash 的 master 一致）。
# 如果这里再克隆一份同名包，会出现 package/luci-app-openclash 与
# package/feeds/luci/luci-app-openclash 同名冲突，
# make defconfig 会直接把 CONFIG_PACKAGE_luci-app-openclash 丢掉，
# 结果固件里没有 OpenClash。（这个坑踩过一次，务必注意）
if [ -d "feeds/luci/applications/luci-app-openclash" ]; then
    echo "    [OK] OpenClash 由官方 luci feed 提供（不自行克隆，避免同名冲突）"
else
    echo "    [!!] 官方 feed 无 luci-app-openclash，退回克隆"
    clone_pkg "OpenClash" "luci-app-openclash" "master" \
        "https://github.com/vernesong/OpenClash.git" || true
fi

# EasyTier（官方 feed 没有）
clone_pkg "EasyTier" "luci-app-easytier" "main" \
    "https://github.com/EasyTier/luci-app-easytier.git" || true

# rkp-ipid（官方 feed 没有）—— IPID 改写，防校园网 NAT 指纹检测
clone_pkg "rkp-ipid" "rkp-ipid" "master" \
    "https://github.com/OpenWrtLi/UA2F-rkp-ipid.git" || true

# 本地包拉完必须重新登记一次 feeds，否则 defconfig 找不到它们
./scripts/feeds install -a

# ============================================================
# 5. 拷贝 .config 与 DIY 脚本
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> [6/8] 应用 .config 与 DIY 脚本..."
if [ -f "${SCRIPT_DIR}/rax3000m-emmc.config" ]; then
    cp "${SCRIPT_DIR}/rax3000m-emmc.config" .config
elif [ -f "${SCRIPT_DIR}/.config" ]; then
    cp "${SCRIPT_DIR}/.config" .config
else
    echo "    !!! 找不到 rax3000m-emmc.config，请把它放在脚本同目录 !!!"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/diy-part2.sh" ]; then
    cp "${SCRIPT_DIR}/diy-part2.sh" diy-part2.sh
    chmod +x diy-part2.sh
    bash diy-part2.sh
fi

# ccache 路径写进 .config
if [ "$USE_CCACHE" = "1" ]; then
    ccache -M "$CCACHE_SIZE" >/dev/null 2>&1 || true
    sed -i '/^CONFIG_CCACHE_DIR=/d;/^CONFIG_CCACHE=/d' .config
    {
        echo "CONFIG_CCACHE=y"
        echo "CONFIG_CCACHE_DIR=\"${CCACHE_DIR}\""
    } >> .config
fi

# ============================================================
# 6. defconfig + 自检
# ============================================================
echo ">>> [7/8] make defconfig + 关键项自检..."
make defconfig

fail=0
check() { if grep -q "^$1=y" .config; then echo "  [OK ] $1"; else echo "  [!! ] $1  <-- 缺失"; fail=1; fi }

grep -q 'CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m=y' .config \
  && echo "  [OK ] 目标设备 cmcc_rax3000m" || { echo "  [!! ] 目标设备错误"; fail=1; }

for s in \
  CONFIG_PACKAGE_luci-app-openclash \
  CONFIG_PACKAGE_kmod-tun \
  CONFIG_PACKAGE_kmod-nft-tproxy \
  CONFIG_PACKAGE_kmod-nft-socket \
  CONFIG_PACKAGE_kmod-nf-tproxy \
  CONFIG_PACKAGE_kmod-inet-diag \
  CONFIG_PACKAGE_kmod-nf-conntrack-netlink \
  CONFIG_PACKAGE_dnsmasq-full \
  CONFIG_PACKAGE_luci-app-easytier \
  CONFIG_PACKAGE_easytier \
  CONFIG_PACKAGE_kmod-rkp-ipid \
  CONFIG_PACKAGE_luci-app-diskman \
  CONFIG_PACKAGE_luci-app-samba4 \
  CONFIG_PACKAGE_luci-app-upnp \
  CONFIG_PACKAGE_luci-app-ttyd \
  CONFIG_PACKAGE_luci-app-wechatpush \
  CONFIG_PACKAGE_luci-theme-argon \
  CONFIG_PACKAGE_kmod-fs-ntfs3 \
  CONFIG_PACKAGE_kmod-usb-storage-uas
do
  check "$s"
done

echo "  --- 必须关闭的项（否则会编译失败或破坏兼容性） ---"
for s in CONFIG_RUBY_ENABLE_YJIT CONFIG_USE_MKLIBS CONFIG_STRIP_KERNEL_EXPORTS; do
    if grep -qE "^${s}=y" .config; then
        echo "  [!! ] ${s}=y  —— 必须关闭！"; fail=1
    else
        echo "  [OK ] ${s} 已关闭"
    fi
done

echo "  --- 确认无 Docker ---"
if grep -qE '^CONFIG_PACKAGE_(docker|dockerd|containerd|runc|luci-app-dockerman)=y' .config; then
    echo "  [!! ] 检测到 Docker 被选中！"; fail=1
else
    echo "  [OK ] 无 Docker"
fi

if [ "$fail" -ne 0 ]; then
    echo ""
    echo "!!! 自检未通过。继续编译也可以，但成品可能缺功能。"
    echo "!!! 常见原因：feeds install 没登记到第三方包，或 .config 被裁剪。"
    read -r -p "仍要继续编译? [y/N] " ans
    [ "${ans:-N}" = "y" ] || exit 1
fi

# ============================================================
# 7. 下载 + 编译
# ============================================================
echo ">>> [8/8] 下载源码包 + 开始编译..."
echo "    （首次全量编译，性能还行的机器约 30-90 分钟）"

make download -j"$JOBS" || make download -j1 V=s
# 清掉下载不完整的小文件
find dl -size -1024c -exec ls -l {} \; 2>/dev/null || true
find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

# 并行编译；失败则用单线程 + 详细日志重跑，方便定位
if make -j"$JOBS"; then
    echo "=== 编译成功 ==="
else
    echo "=== 并行编译失败，改用 -j1 V=s 重跑以获取完整错误 ==="
    make -j1 V=s 2>&1 | tee /tmp/build_verbose.log
    echo "=== 真正的报错行 ==="
    grep -nE 'Error [0-9]|make(\[[0-9]\])?: \*\*\*|ERROR:|Library not found|Cannot install|Collected errors|check_data_file_clashes' \
        /tmp/build_verbose.log | tail -40 || true
    exit 1
fi

# ============================================================
# 8. 收集产物
# ============================================================
echo ""
echo "=============================================================="
echo " 编译完成！产物目录： $WORKDIR/immortalwrt/$TARGET_DIR"
echo "=============================================================="
ls -lh "$TARGET_DIR" 2>/dev/null || true

if [ "$PACK_OUTPUT" = "1" ]; then
    OUT="$HOME/akisen-firmware-$(date +%Y%m%d-%H%M)"
    mkdir -p "$OUT"
    for pat in '*sysupgrade*' '*recovery*' '*.manifest' '*.config' 'sha256sums' 'profiles.json' \
               '*preloader*' '*bl31-uboot*' '*emmc-gpt*'; do
        find "$TARGET_DIR" -maxdepth 1 -name "$pat" -exec cp -v {} "$OUT/" \; 2>/dev/null || true
    done
    ( cd "$OUT" && sha256sum ./* > SHA256SUMS.txt 2>/dev/null || true )
    echo ""
    echo "已打包到： $OUT"
    ls -lh "$OUT"
    echo ""
    echo "★ 刷机要用的文件是 *sysupgrade.itb"
fi

echo ""
echo "完成。"
