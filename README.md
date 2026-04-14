# 🛠️ NooMili SSH工具箱

<div align="center">
  
[🦇 MTP 代理搭建教程](./MD/MTP.md) | [📊 Komari 探针部署教程](./MD/komari.md) | [☁️ CF Worker 短链搭建教程](./MD/cf.md)

</div>

## 🌟 简介

**NooMili工具箱** 是一款全能的服务器主控面板，**全面兼容独立 VPS 与海外廉价 NAT 小鸡（Alpine/LXC 架构）**。
它支持一键执行系统环境清理与更新，内置智能识别网络环境的 MTP 代理部署、Komari 探针，以及专为极小内存机器打造的 Lucky Web SSL 证书面板。同时集成多位大佬的精选外部脚本，是你管理所有小鸡的绝佳瑞士军刀。

## 🚀 一键极速部署指令（四选一）

安装主控面板后，即可在内部自由调用各项功能。

### 方案 A：Cloudflare 自定义短域名 (极简推荐)
如果你拥有自己的域名，利用 CF 网页版搭建专属的极简短链（完美防墙，全球极速秒连！）：
```bash
bash <(curl -fsSL vvvps.qzz.io)
````

👉 **[点击查看：CF Worker 极简短链搭建教程](https://www.google.com/search?q=./MD/cf.md)**

### 方案 B：免费短链白嫖（免域名、极简指令）

利用免费短链服务，无需自己购买域名（如使用 `is.gd` 短链）：

```bash
bash <(curl -Ls is.gd/你的自定义后缀)
```

### 方案 C：直写系统命令（简单粗暴，推荐极简系统）

直接将脚本下载为系统全局命令并瞬间唤醒面板（适合未安装 curl 的纯净系统）：

```bash
wget -O /usr/local/bin/n [https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh) && chmod +x /usr/local/bin/n && n
```

### 方案 D：经典拉取执行

传统的 GitHub Raw 裸脚本部署方法：

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/SSHTools/main/NooMili.sh))
```

-----

## 🛠️ 后续日常管理 (常驻快捷键)

首次安装完成后，无论何时登录你的机器，只需要在 SSH 敲入以下一个字母并回车，即可瞬间唤醒管理面板：

```bash
n
```

**主控面板核心功能：**

  - `1-3` **系统基础运维**：一键查询系统信息、apt/yum 更新、清理垃圾释放空间。
  - `4-6` **核心业务直达**：无缝进入 MTP 代理面板、Komari 探针面板、安装 Lucky (自动化 Web SSL/反代管理)。
  - `7-8` **外部精选合集**：内置老王一键工具箱与科技lion一键脚本。
  - `9` **热更新面板**：直接从 GitHub 同步你对 NooMili 的最新代码改动。

> **⚠️ 常见问题说明：**
> 若运行指令时提示找不到 `curl` 或 `wget`，请先根据你的系统执行安装：
>
>   * Ubuntu/Debian：`apt-get install -y curl wget`
>   * Alpine：`apk add curl wget`
>   * Fedora：`dnf install -y curl wget`
>   * CentOS/Rocky/Oracle等：`yum install -y curl wget`
