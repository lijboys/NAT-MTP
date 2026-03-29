# ☁️ NooMili - Cloudflare Worker 自建极简短链教程

[⬅️ 返回 NooMili 工具箱主页](../README.md)

## 🌟 为什么需要用 CF Worker 反代？

很多国内的机器或者部分 NAT 小鸡，直接拉取 `raw.githubusercontent.com` 会因为网络问题报错。
利用 Cloudflare (CF) 免费的 Worker 功能，我们可以把脚本缓存到 CF 的全球边缘节点上，并绑定你自己的短域名（例如 `n.你的域名.com`）。
这样不仅命令变得极其简短，而且**永不失联，完美防墙**！

## 🛠️ CF 网页版搭建步骤

全程只需要在 CF 网页版点点鼠标，一分钟搞定：

### 第一步：创建 Worker
1. 登录 Cloudflare 网页版控制台。
2. 在左侧菜单找到 **[Workers 和 Pages]** -> 点击 **[创建应用程序]** -> 点击 **[创建 Worker]**。
3. 给你的 Worker 起个名字（例如 `noomili-proxy`），点击 **[部署]**。

### 第二步：修改反代代码
1. 部署完成后，点击 **[编辑代码]** (Quick edit)。
2. 把左侧代码框里的内容**全部删除**，替换成下面的代码：

```javascript
export default {
  async fetch(request, env, ctx) {
    // 这里填入 NooMili 主控脚本的官方直链
    const githubRawUrl = "[https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh](https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh)";
    
    // 发起请求并返回脚本内容
    const response = await fetch(githubRawUrl);
    return new Response(response.body, {
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
        "Cache-Control": "public, max-age=3600"
      }
    });
  }
};
````

3.  点击右上角的 **[保存并部署]**。

### 第三步：绑定你自己的自定义域名 (核心)

1.  返回刚才那个 Worker 的详情页面。
2.  找到 **[设置] (Settings)** -\> 选择 **[触发器] (Triggers)** 选项卡。
3.  往下滚找到 **[自定义域] (Custom Domains)**，点击 **[添加自定义域]**。
4.  输入你想用来一键安装的短域名（例如 `n.你的域名.com`，前提是这个主域名已经托管在 CF 上），点击添加。
5.  等待几十秒 CF 自动为你签发 SSL 证书。

## 🚀 享受极简安装

大功告成！以后你在任何一台全新小鸡上，只需要输入这行优雅的命令，就能瞬间呼出你的面板：
```
bash <(curl -fsSL n.你的域名.com)
```
