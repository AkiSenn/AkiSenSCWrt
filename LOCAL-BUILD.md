# 本地编译

需要 Ubuntu 22.04 或相近 Linux 环境、足够磁盘和编译依赖，见 Actions 工作流。Windows 建议在 WSL 的 Linux 原生文件系统中构建。

Windows 的 Git Bash 可以用于 Git 操作和触发云编译。它本身不能提供固件完整编译所需的 Linux 环境。云端工作流和本地入口均由 Bash 编排；构建工具及源码锁定、校验脚本仍需要 Python 3。

在仓库目录私下设置 `WIFI_PASSWORD` 环境变量，执行 `./build-local.sh`。不要把值写入脚本、文档或 shell 历史。输出包含个人无线配置，属于私有数据，只保留在本机。

脚本使用 `sources.lock.json` 锁定的源码和 feeds，验证配置和最终 manifest，保存对应 IPK。构建目录必须是新目录，不覆盖已有源码树。
