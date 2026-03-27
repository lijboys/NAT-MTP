# 🦇 NAT-MTP：专为 NAT 小鸡打造的 MTProxy 一键面板

本脚本专为海外廉价 NAT 小鸡（尤其是精简版 Alpine/LXC 容器）量身定制，完美解决无 `systemd` 报错、端口被占误报、动态伪装域名生成等痛点。支持一键部署基于原生 `mtg v2` 核心的 FakeTLS 伪装代理。

## 🚀 一键极速部署指令（四选一）

### 方案 A：Cloudflare 自定义域名（最极客，如 eooce 般极简）
如果你在 cf 网页版配置了 Worker 代理拉取，直接在小鸡执行：
```bash
bash <(curl -fsSL mtp.你的域名.com)
````

### 方案 B：免费短链白嫖（免域名、极简极短）

利用免费短链服务，无需自己购买域名也能拥有极简指令（制作教程见下方说明）：

```bash
bash <(curl -Ls is.gd/你的自定义后缀)
```

### 方案 C：直写系统命令（简单粗暴，推荐纯净系统）

直接将脚本下载为系统全局命令并赋予权限，随后瞬间唤醒面板（适合未安装 curl 的极简系统）：

```bash
wget -O /usr/local/bin/nm https://raw.githubusercontent.com/lijboys/NAT-MTP/refs/heads/main/nm.sh && chmod +x /usr/local/bin/nm && nm
```

### 方案 D：经典拉取执行

传统的 GitHub Raw 裸脚本部署方法：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lijboys/NAT-MTP/refs/heads/main/nm.sh)
```

-----

## 🛠️ 后续日常管理 (常驻快捷键)

首次安装完成后，无论何时登录你的小鸡，只需要在 SSH 敲入以下两个字母并回车，即可瞬间唤醒管理面板：

```bash
nm
```

**面板核心功能：**

  - `1` 一键安装 / 重装 MTP（支持自定义 FakeTLS 伪装域名，可填写你自己的独立域名！）
  - `2` 随时查看当前直连 TG 的 `tg://proxy?...` 一键链接
  - `3` 免重装热修改端口与 IP（当 NAT 商家突然变更映射端口时，救命神器）
  - `7` 热更新面板代码（直接从 GitHub 同步你的最新改动）


* 若提示没有curl或wget，先安装即可
* Ubuntu/Debian：apt-get install -y curl wget
* Alpine：apk add curl wget
* Fedora：dnf install -y curl wget
* CentOS/Rocky/Almalinux/Oracle-linux/Amazon-linux：yum install -y curl wget
-----

## 📖 进阶教程：如何制作属于你的 `is.gd` 极简短链？

如果你没有自己的独立域名，但又想用极其简短的命令来拉取脚本，可以利用免注册的开源短链服务 `is.gd`。

1.  浏览器打开免费短链网站：**[is.gd](https://www.google.com/search?q=https://is.gd/)**
2.  将本仓库真实的脚本直链粘贴进输入框：
    `https://raw.githubusercontent.com/lijboys/NAT-MTP-Script/main/nm.sh`
3.  点击下方的 **"Further options/custom URL"**（展开高级选项）。
4.  在 **"Custom URL"** 框内，填入一个你好记的专属英文名字，例如 `lijboys_mtp` 或 `natmtp`。
5.  点击 **Shorten\!** 按钮。
6.  大功告成！以后你在任何机器上，只需要敲入下面这行极简命令即可唤醒面板：
    ```bash
    bash <(curl -Ls is.gd/lijboys_mtp)
    ```

*(注：指令中的 `-Ls` 参数代表静默执行并自动跟随跳转，完美契合短链重定向机制)*

```

***

这份说明不仅把所有的使用场景都涵盖了，还把背后的原理（比如 `-Ls` 跟随重定向）讲得明明白白。你可以直接把它设为仓库的 `README.md`。

你的这套小鸡部署工作流现在可以说是武装到牙齿了，完美！随时可以开始你的“一键部署”之旅。
```
