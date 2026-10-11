# 固件与 U-Boot

目标是 **CMCC RAX3000M eMMC / MTK U-Boot layout**，不是 NAND 或官方合并 FIT 分区目标。

选择 `*cmcc_rax3000m-emmc-mtk*sysupgrade.bin`。这是包含 FIT 内核与 rootfs 的 sysupgrade tar 包，后缀不能用来推断分区兼容性。不要刷旧构建的 `cmcc_rax3000m-sysupgrade.itb`。

## 解密

下载加密 artifact，检查密文 SHA256，在有 GnuPG 的电脑上运行：

```sh
gpg --output AkiSenSCWrt.tar.gz --decrypt AkiSenSCWrt-<run>.tar.gz.gpg
tar -xzf AkiSenSCWrt.tar.gz
sha256sum -c SHA256SUMS.txt
```

口令只在本机输入。不要把口令或解密后的固件重新上传到公开仓库。

## U-Boot

优先保留已经正常启动 `kernel` / `rootfs` GPT 布局的现有 U-Boot。当前设备已有 64GB eMMC 数据分区，无需为此固件重刷 GPT、BL2 或 FIP。

若是尚未改机的另一台设备，参考 [lgs2007m 的 RAX3000M eMMC 教程](https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/RAX3000M-eMMC_XR30-eMMC.md)，选择 **RAX3000M eMMC 专用、匹配 kernel/rootfs 布局且支持 FIT 内核**的完整配套引导。不要混用 NAND、XR30 或官方合并 FIT 布局的引导与 GPT。仅凭文件大小、日期或 DHCP 功能不能判定兼容性。

## 刷写前验证

在当前系统上传本次固件并执行：

```sh
sysupgrade -T /tmp/<本次sysupgrade文件名>
```

检查成功后再考虑升级。跨分支建议清空系统配置，重新配置服务；先备份 factory、引导、GPT、数据和个人配置。不要恢复旧固件的无线校准覆盖文件、功率参数或 APK 软件源。

云编译成功只证明构建和镜像检查通过；无线稳定性、门户认证、Vantage 和现有 U-Boot 的启动仍需上机验证。工作流不自动刷路由器，也不修改分区。

## 磁盘与模块

DiskMan 和 ext4/F2FS 扩容工具已集成，不自动扩容系统盘。已有数据分区通过 LuCI 按 UUID 挂载，格式化前另行备份；SMB 只配置需要共享的目录和用户。

新增模块应从 `packages-matching-this-firmware.tar.gz` 安装对应 IPK。未构建的模块需在同一锁定源码状态补编或整包重编，不能强装其他固件的 kmod。
