# 🦇 NatTools - MTP 代理部署教程

[⬅️ 返回 NooMili 工具箱主页](../README.md)

## 🌟 简介

本模块是专为 Telegram 打造的专属 MTProxy 代理一键部署工具，底层采用官方原生 `mtg v2` 核心。
由于许多廉价 NAT 小鸡（如 Alpine/LXC 架构）精简了 `systemd` 守护进程，传统的一键脚本经常会报错或无法后台运行。本脚本通过底层进程守护与 `crontab` 完美兼容了这类极其精简的系统。

## 🚀 启动方式

如果你已经安装了 `NooMili` 主控面板，你可以通过以下两种方式随时唤醒 MTP 面板：
1. 在终端输入 `n` 打开主菜单，选择 **[4] 进入 MTP 代理管理面板**。
2. 或在终端直接输入快捷指令：
   ```bash
   mtp
   ```

*(如果你只想单独安装 MTP 面板，不想要主控，可以直接运行：)*
```bash
wget -O /usr/local/bin/mtp [https://raw.githubusercontent.com/lijboys/NatTools/main/mtp.sh](https://raw.githubusercontent.com/lijboys/NatTools/main/mtp.sh) && chmod +x /usr/local/bin/mtp && mtp
```

## 🛠️ 核心功能亮点

### 1. FakeTLS 动态伪装
告别容易被墙的普通 MTP！本脚本内置了动态 Secret 生成逻辑，你可以一键选择高隐蔽性的白名单域名（如必应、苹果商店、Cloudflare 等），也可以自定义你自己的直连域名。流量会被伪装成正常的 TLS 网站流量，极其稳健。

### 2. 完美适配 NAT 映射逻辑
在 NAT 小鸡上，你的“内网监听端口”和“公网连接端口”通常是不一样的。
脚本安装时会引导你分别输入**内网端口**和**商家分配的公网端口/IP**，自动为你计算并生成最终可以一键直连的 `tg://proxy?server=...` 链接。

### 3. 热修改（救命神器）
NAT 商家的公网 IP 和端口经常会突然变动。遇到这种情况无需重装，直接打开面板选择 **[3] 修改端口、IP与伪装域名**，输入新的公网信息，脚本会自动重载配置并刷新你的 TG 链接，10 秒内恢复失联的小鸡。

### 4. 纯净卸载
选择卸载时，脚本会自动清理所有的定时任务、后台进程、二进制文件以及配置残留，保证还你一个干干净净的系统。
