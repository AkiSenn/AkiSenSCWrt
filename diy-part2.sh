#!/bin/bash
#
# diy-part2.sh — AkiSenSCWrt (CMCC RAX3000M eMMC / ImmortalWrt 24.10.6)
# 在 feeds install 之后、make defconfig 之前执行。
# 负责注入：主机名、时区、LAN 网段、IPv6、WiFi 默认值、SMB 默认共享、透明代理共存所需的 sysctl。
#
set -e

echo "======================================================"
echo " AkiSenSCWrt DIY  part2"
echo "======================================================"

OPENWRT_DIR="$(pwd)"
echo ">>> 工作目录: ${OPENWRT_DIR}"

OVERLAY="${OPENWRT_DIR}/package/base-files/files"
mkdir -p "${OVERLAY}/etc/uci-defaults"
mkdir -p "${OVERLAY}/etc/sysctl.d"

# ---------------------------------------------------------------
# 1. 克隆第三方包源码进 package/ 目录，随固件一起编译
#    （ImmortalWrt 24.10 官方 feed 里没有这三个，必须自己拉源码）
# ---------------------------------------------------------------
clone_pkg() {
    # $1 = 显示名  $2 = 目标目录名  $3 = 分支  $4.. = 候选 git 地址
    _name="$1"; _dest="$2"; _branch="$3"; shift 3
    _target="${OPENWRT_DIR}/package/${_dest}"
    rm -rf "${_target}"
    for _repo in "$@"; do
        echo "    ${_name}: 尝试 ${_repo} (${_branch})"
        if git clone --depth=1 -b "${_branch}" "${_repo}" "${_target}" 2>/dev/null; then
            echo "    [OK] ${_name}"
            rm -rf "${_target}/.github"
            return 0
        fi
        rm -rf "${_target}"
        if git clone --depth=1 "${_repo}" "${_target}" 2>/dev/null; then
            echo "    [OK] ${_name}（默认分支）"
            rm -rf "${_target}/.github"
            return 0
        fi
        rm -rf "${_target}"
    done
    echo "    [失败] ${_name} —— 固件中将不含此功能"
    return 1
}

echo ">>> 克隆第三方包源码..."

# OpenClash（透明代理）
clone_pkg "OpenClash" "luci-app-openclash" "${OPENCLASH_BRANCH:-master}" \
    "https://github.com/vernesong/OpenClash.git" \
    "https://gitee.com/vernesong/OpenClash.git" || true

# EasyTier（异地组网）—— 仓库含 easytier / easytier-noweb / luci-app-easytier
clone_pkg "EasyTier" "luci-app-easytier" "main" \
    "https://github.com/EasyTier/luci-app-easytier.git" || true

# rkp-ipid（IPID 改写，防校园网 NAT 指纹检测）
clone_pkg "rkp-ipid" "rkp-ipid" "master" \
    "https://github.com/OpenWrtLi/UA2F-rkp-ipid.git" || true
# 该仓库的 Makefile 直接构建 rkp-ipid 内核模块，改名以便识别
if [ -d "${OPENWRT_DIR}/package/rkp-ipid" ]; then
    rm -f "${OPENWRT_DIR}/package/rkp-ipid/README.md" 2>/dev/null || true
fi

# ---------------------------------------------------------------
# 2. 首次启动默认配置（uci-defaults，只跑一次，之后可自由修改）
# ---------------------------------------------------------------
cat > "${OVERLAY}/etc/uci-defaults/99-akisen-settings" <<'UCIEOF'
#!/bin/sh
# AkiSenSCWrt first-boot defaults

# ---- 主机名 ----
uci -q set system.@system[0].hostname='AkiSenSCWrt'
uci -q set system.@system[0].description='AkiSenSCWrt 24.10.6'
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.ntp.enabled='1'
uci -q set system.ntp.enable_server='1'
uci -q set system.ntp.server='ntp.aliyun.com' 'time1.cloud.tencent.com' 'cn.pool.ntp.org' 'time.apple.com'

# ---- LAN: 192.168.2.1/24 + IPv6 ----
uci -q set network.lan='interface'
uci -q set network.lan.device='br-lan'
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.2.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.lan.ip6assign='60'
uci -q set network.lan.delegate='1'
uci -q set network.lan.ra='server'
uci -q set network.lan.dhcpv6='server'
uci -q set network.lan.ra_slaac='1'
uci -q set network.lan.ra_flags='managed-config' 'other-config'
uci -q set network.lan.dns='192.168.2.1'

# ---- WAN：校园网，走 DHCP，不拨号 ----
uci -q set network.wan='interface'
uci -q set network.wan.device='eth1'
uci -q set network.wan.proto='dhcp'
uci -q set network.wan.peerdns='1'
uci -q set network.wan6='interface'
uci -q set network.wan6.device='eth1'
uci -q set network.wan6.proto='dhcpv6'
uci -q set network.wan6.reqaddress='try'
uci -q set network.wan6.reqprefix='auto'

# ---- DHCP 服务：强制下发本机为 DNS 与网关 ----
uci -q set dhcp.lan='dhcp'
uci -q set dhcp.lan.interface='lan'
uci -q set dhcp.lan.start='100'
uci -q set dhcp.lan.limit='200'
uci -q set dhcp.lan.leasetime='12h'
uci -q set dhcp.lan.dhcpv6='server'
uci -q set dhcp.lan.ra='server'
uci -q set dhcp.lan.force='1'
uci -q set dhcp.lan.dns='192.168.2.1'
# 让内网解析走 OpenClash 的 DNS 劫持
uci -q set dhcp.@dnsmasq[0].domainneeded='1'
uci -q set dhcp.@dnsmasq[0].localise_queries='1'
uci -q set dhcp.@dnsmasq[0].rebind_protection='0'
uci -q set dhcp.@dnsmasq[0].local='/lan/'
uci -q set dhcp.@dnsmasq[0].domain='lan'

# ---- WiFi：Aris (2.4G) / Aris_5G (5G) ----
# 关键：MT7981 + MT7976 是「单 phy 双频」，不能用 iw 的频段扫描来区分 2.4G/5G。
# 正确做法是直接用 board.json 里的 radio 定义，它已经带好了 band 字段。
WIFI_24_SSID='Aris'
WIFI_5G_SSID='Aris_5G'
WIFI_KEY='wdnmd123456789'

if command -v wifi >/dev/null 2>&1; then

    add_wifi() {
        __band="$1"; __ssid="$2"; __htmode="$3"; __txpower="$4"; __i="$5"
        uci -q batch <<-EOB
			set wireless.radio${__i}=wifi-device
			set wireless.radio${__i}.type='mac80211'
			set wireless.radio${__i}.path='${__path}'
			set wireless.radio${__i}.channel='auto'
			set wireless.radio${__i}.band='${__band}'
			set wireless.radio${__i}.htmode='${__htmode}'
			set wireless.radio${__i}.country='CN'
			set wireless.radio${__i}.txpower='${__txpower}'
			set wireless.radio${__i}.cell_density='0'
			set wireless.radio${__i}.disabled='0'
			set wireless.default_radio${__i}=wifi-iface
			set wireless.default_radio${__i}.device='radio${__i}'
			set wireless.default_radio${__i}.network='lan'
			set wireless.default_radio${__i}.mode='ap'
			set wireless.default_radio${__i}.ssid='${__ssid}'
			set wireless.default_radio${__i}.encryption='psk2+ccmp'
			set wireless.default_radio${__i}.key='${WIFI_KEY}'
			set wireless.default_radio${__i}.disabled='0'
		EOB
    }

    rm -f /etc/config/wireless
    touch /etc/config/wireless
    wifi config >/dev/null 2>&1 || true

    IDX=0
    for dev in $(jsonfilter -e '@.radios[*].path' < /etc/board.json 2>/dev/null); do
        __path="${dev}"
        band=$(jsonfilter -e "@.radios[*].band" < /etc/board.json 2>/dev/null | sed -n "$((IDX + 1))p")
        case "${band}" in
            2g) add_wifi   '2g' "${WIFI_24_SSID}" 'HE40' '20' "${IDX}" ;;
            5g) add_wifi   '5g' "${WIFI_5G_SSID}" 'HE80' '20' "${IDX}" ;;
            6g) add_wifi   '6g' "${WIFI_5G_SSID}" 'HE160' '20' "${IDX}" ;;
            *)  : ;;
        esac
        IDX=$((IDX + 1))
    done

    # 兜底：board.json 没给出 band 时，按 radio 顺序赋值
    if [ "${IDX}" -eq 0 ]; then
        radio0_path=$(uci -q get wireless.radio0.path)
        radio1_path=$(uci -q get wireless.radio1.path)
        [ -n "${radio0_path}" ] && {
            __path="${radio0_path}"; add_wifi '2g' "${WIFI_24_SSID}" 'HE40' '20' 0; }
        [ -n "${radio1_path}" ] && {
            __path="${radio1_path}"; add_wifi '5g' "${WIFI_5G_SSID}" 'HE80' '20' 1; }
    fi
fi

# ---- SMB 共享默认目录 ----
mkdir -p /mnt/sda1
uci -q set samba4.@samba4[0].workgroup='WORKGROUP'
uci -q set samba4.@samba4[0].description='AkiSenSCWrt'
uci -q set samba4.@samba4[0].disable_netbios='1'
uci -q set samba4.@samba4[0].homes='0'

# ---- 透明代理共存：OpenClash / rkp-ipid 需要的 sysctl ----
# 允许转发 + 关闭严格的 rp_filter（透明代理必需）
cat > /etc/sysctl.d/99-akisen-proxy.conf <<'SYSCTLEOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.route_localnet=1
net.ipv4.tcp_fastopen=3
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
SYSCTLEOF

uci -q commit system
uci -q commit network
uci -q commit dhcp
uci -q commit wireless 2>/dev/null || true
uci -q commit samba4 2>/dev/null || true

exit 0
UCIEOF

chmod 0755 "${OVERLAY}/etc/uci-defaults/99-akisen-settings"

# ---------------------------------------------------------------
# 3. rkp-ipid 开机加载参数
# ---------------------------------------------------------------
# ★★ 重要：这里【不要】自己创建 /etc/modules.d/99-rkp-ipid ！★★
#
# rkp-ipid 包的 Makefile 里已经有：
#     AUTOLOAD:=$(call AutoLoad, 99, rkp-ipid)
# 它会自己在 rootfs 里生成 /etc/modules.d/99-rkp-ipid。
#
# 如果我们在 base-files overlay 里手写同名文件，opkg 会报：
#     check_data_file_clashes: Package kmod-rkp-ipid wants to install file
#       .../etc/modules.d/99-rkp-ipid
#       But that file is already provided by package * base-files
#     opkg_install_cmd: Cannot install package kmod-rkp-ipid.
# 结果整个 package/install 阶段失败，固件生不出来。（上一轮就是这么挂的）
#
# 所以交给包自己管理。如果以后要改加载参数，用 UCI 或改包源码，
# 不要在这里塞同名文件。

# ---------------------------------------------------------------
# 4. rkp-ipid 配套防火墙规则（mangle 表打 MARK），与 OpenClash 透明共存
#    注意：启用 flow offload / 硬件加速 会让 rkp-ipid 失效，所以这里不启用。
# ---------------------------------------------------------------
cat > "${OVERLAY}/etc/uci-defaults/98-akisen-ipid-fw" <<'FWEOF'
#!/bin/sh
# 给发往公网的转发包打 mark 0x10/0x10，供 rkp-ipid 改写 IPID
# 内网/回环/组播/保留地址直接 RETURN
iptables -t mangle -N IPID_MOD 2>/dev/null
iptables -t mangle -C FORWARD -j IPID_MOD 2>/dev/null || \
    iptables -t mangle -A FORWARD -j IPID_MOD
iptables -t mangle -C OUTPUT -j IPID_MOD 2>/dev/null || \
    iptables -t mangle -A OUTPUT -j IPID_MOD

for net in 0.0.0.0/8 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 255.0.0.0/8 224.0.0.0/4; do
    iptables -t mangle -C IPID_MOD -d "${net}" -j RETURN 2>/dev/null || \
        iptables -t mangle -A IPID_MOD -d "${net}" -j RETURN
done
iptables -t mangle -C IPID_MOD -j MARK --set-xmark 0x10/0x10 2>/dev/null || \
    iptables -t mangle -A IPID_MOD -j MARK --set-xmark 0x10/0x10

# 关掉 flow offload（rkp-ipid 与硬件加速冲突）
uci -q set firewall.@defaults[0].flow_offloading='0'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'
uci -q commit firewall

exit 0
FWEOF

chmod 0755 "${OVERLAY}/etc/uci-defaults/98-akisen-ipid-fw"

# ---------------------------------------------------------------
# 5. 便捷访问后缀 / 强制 nginx 不介入
# ---------------------------------------------------------------
# 说明：OpenWrt/LuCI 原生不支持任意 URL 后缀（如 /scwrt/）这种「隐蔽入口」，
# 强行实现需要额外 nginx/uhttpd 改路由，且容易和 OpenClash 的 DNS/HTTP 劫持冲突。
# 这里不做，保持默认 http://192.168.2.1/cgi-bin/luci 访问。

echo "======================================================"
echo " DIY part2 完成"
echo "  第三方包目录:"
for d in luci-app-openclash luci-app-easytier rkp-ipid; do
    if [ -d "${OPENWRT_DIR}/package/${d}" ]; then
        echo "    [有] package/${d}"
    else
        echo "    [无] package/${d}   <-- 缺失，对应功能不会编进固件"
    fi
done
echo "  overlay: ${OVERLAY}"
echo "======================================================"
