# 📊 NatTools - Komari 探针部署教程

[⬅️ 返回 NooMili 工具箱主页](./README.md)

## 🌟 简介

**Komari** 是一款轻量级的自托管服务器监控探针。相比于 ServerStatus 或是哪吒探针，它非常适合部署在资源有限的 NAT 小鸡上用来查看各项性能指标。
官方 GitHub: [komari-monitor/komari](https://github.com/komari-monitor/komari)

为了让 Komari 在 NAT 环境下更安全、更好用，本面板对其进行了深度的运维定制，加入了 Nginx 反代配置和 IP 访问限制功能。

## 🚀 启动方式

如果你已经安装了 `NooMili` 主控面板，你可以通过以下两种方式随时唤醒探针面板：
1. 在终端输入 `n` 打开主菜单，选择 **[5] 进入 Komari 探针管理面板**。
2. 或在终端直接输入快捷指令：
   ```bash
   komari
   ```

*(单脚本独立安装指令：)*
```bash
wget -O /usr/local/bin/komari [https://raw.githubusercontent.com/lijboys/NatTools/main/komari.sh](https://raw.githubusercontent.com/lijboys/NatTools/main/komari.sh) && chmod +x /usr/local/bin/komari && komari
```

## 🛠️ 核心功能与玩法

### 1. 一键提取初始凭据
Komari 官方脚本安装完成后，账号密码通常隐藏在系统日志中。本面板在安装完成后会自动抓取并提取你的 `Username` 和 `Password`，你也可以随时在面板中按 **[4] 查看初始凭据**。

### 2. Cloudflare 回源配置 (推荐玩法)
由于 NAT 小鸡直接暴露 IP 和端口容易被扫，面板为你提供了 **CF 回源模式** 的专属优化：
* 在面板选择 **[5] 添加域名访问**。
* 选择 `Cloudflare 回源模式`。
* 面板会自动配置 Nginx 监听 `80` 端口并反代你的 Komari 本地端口。
* **你要做的**：去 CF 网页版将域名解析到小鸡 IP 并开启**小黄云**（代理模式），然后在 CF 的 Origin Rule 中，将回源端口指向小鸡的 NAT 公网映射端口（如果你映射了 80 端口则无需设置）。全程由 CF 提供免费的 SSL 证书保护！

### 3. IP 防火墙开关
配合上面的域名绑定功能，你可以通过面板的 **[8] 阻止 IP+端口 访问** 功能，利用 `iptables` 直接掐断公网通过 `IP:端口` 直连探针的途径。
这样你的探针就只能通过你绑定的 CF 域名来访问了，安全性直接拉满，彻底杜绝被恶意扫描器爆破的风险！
