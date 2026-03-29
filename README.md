# 🛠️ NooMili 综合管理工具箱

<div align="center">
  
[🦇 MTP 代理搭建教程](./MTP.md) | [📊 Komari 探针部署教程](./komari.md)

</div>

## 🌟 简介

本脚本专为海外廉价 NAT 小鸡（尤其是精简版 Alpine/LXC 容器）量身定制。
**NooMili工具箱** 是一个全能的主控面板，支持一键执行系统环境清理与更新，并可无缝直达自带的 MTP 代理面板与 Komari 探针面板。同时，内部集成了多位大佬的精选外部脚本，是管理小鸡的绝佳瑞士军刀。

## 🚀 一键极速部署指令（四选一）

安装主控面板后，即可在内部自由调用各项功能。

### 方案 A：Cloudflare 自定义域名 (推荐)
如果你在 cf 网页版配置了 Worker 代理拉取，直接在小鸡执行：
```bash
bash <(curl -fsSL noomili.你的域名.com)
````

### 方案 B：免费短链白嫖（免域名、极简极短）

利用免费短链服务，无需自己购买域名也能拥有极简指令（制作教程见下方说明）：

```bash
bash <(curl -Ls is.gd/你的自定义后缀)
```

### 方案 C：直写系统命令（简单粗暴，推荐纯净系统）

直接将脚本下载为系统全局命令并赋予权限，随后瞬间唤醒面板（适合未安装 curl 的极简系统）：

```bash
wget -O /usr/local/bin/n [https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh) && chmod +x /usr/local/bin/n && n
```

### 方案 D：经典拉取执行

传统的 GitHub Raw 裸脚本部署方法：

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh))
```

-----

## 🛠️ 后续日常管理 (常驻快捷键)

首次安装完成后，无论何时登录你的小鸡，只需要在 SSH 敲入以下一个字母并回车，即可瞬间唤醒管理面板：

```bash
n
```

**主控面板核心功能：**

  - `1-3` **系统基础运维**：一键查询系统信息、apt/yum 更新、清理垃圾释放空间。
  - `4-5` **核心业务直达**：无缝进入 MTP 代理管理面板 或 Komari 探针管理面板。
  - `6-7` **外部精选合集**：内置老王一键工具箱与科技lion一键脚本。
  - `8` **热更新面板**：直接从 GitHub 同步你对 NooMili 的最新改动。

> **⚠️ 常见问题说明：**
> 若运行指令时提示找不到 `curl` 或 `wget`，请先根据你的系统执行安装：
>
>   * Ubuntu/Debian：`apt-get install -y curl wget`
>   * Alpine：`apk add curl wget`
>   * Fedora：`dnf install -y curl wget`
>   * CentOS/Rocky/Oracle等：`yum install -y curl wget`

-----

## 📖 进阶教程：如何制作属于你的极简指令？

### 玩法 1：利用 `is.gd` 制作免域名的极简短链

如果你没有自己的独立域名，但又想用极其简短的命令来拉取脚本，可以利用免注册的开源短链服务 `is.gd`。

1.  浏览器打开免费短链网站：**[is.gd](https://www.google.com/search?q=https://is.gd/)**
2.  将本仓库真实的主控脚本直链粘贴进输入框：
    `https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh`
3.  点击下方的 **"Further options/custom URL"**（展开高级选项）。
4.  在 **"Custom URL"** 框内，填入一个你好记的专属英文名字，例如 `lijboys_n` 或 `noomili`。
5.  点击 **Shorten\!** 按钮。
6.  大功告成！以后你在任何机器上，只需要敲入下面这行极简命令即可唤醒主控面板：
    ```bash
    bash <(curl -Ls is.gd/lijboys_n)
    ```

*(注：指令中的 `-Ls` 参数代表静默执行并自动跟随跳转，完美契合短链重定向机制)*

### 玩法 2：利用 Cloudflare (cf) 网页版 Workers 代理拉取

如果你有自己的域名，可以直接在 cf 网页版创建一个 Worker 来反代脚本链接：

1.  在 CF 网页版左侧菜单找到 **Workers & Pages** -\> 创建应用程序 -\> 创建 Worker。
2.  将 Worker 的代码替换为反代 GitHub Raw 的代码（目标指向 `https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh`）。
3.  在该 Worker 的“设置” -\> “触发器”中绑定你的自定义域名。
4.  随后即可使用 `bash <(curl -fsSL 你的自定义域名)` 优雅拉取！

<!-- end list -->

```

---

直接把上面的内容复制进去作为主目录的 `README.md` 就完美了。顶部预留了 `MTP.md` 和 `komari.md` 的跳转链接，接下来你要不要我顺手把这两个子教程的 Markdown 内容也帮你写出来？
```
