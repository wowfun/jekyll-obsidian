---
publish: true
title: 部署
description: 使用随附的 GitHub Pages 工作流检查并部署任意内置主题。
---

# 部署

[Pages 工作流示例](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.0/examples/pages.yml)使用版本化的 Jekyll Obsidian Action。Action 安装 Ruby 和对应版本的 `jekyll-obsidian-site` gem，然后构建宿主内容。下游仓库无需安装 npm 依赖或运行本项目的回归测试。

## 拉取请求与推送

拉取请求只构建和校验站点，不部署。默认分支上的推送会构建并部署，其他分支的推送会被忽略。手动运行时，也只有选择默认分支才会部署。

工作流不设置内容路径过滤器。修改 `.github/jekyll-obsidian.yml` 中的 `website.source` 后，无需重新生成工作流。本项目在自己的仓库中单独运行编译器、安装包、前端和浏览器测试。

## 受信任的 Pages 构建

在 **Settings > Pages > Build and deployment > Source** 中选择 **GitHub Actions**。构建作业读取 Pages 元数据，构建一次，审计输出后上传已验证的产物。部署作业只获取部署所需的 Pages 和身份令牌权限。

上传前会检查输出路径、文件类型、站点大小、URL 和资源引用。构建失败不会替换上一次本地输出，也不会部署产物。

Action 接受 `url` 和 `baseurl`，通过 `site-path` 返回输出目录的绝对路径。示例工作流将 Pages 元数据传给这些输入，并上传返回的目录。

## 查找已部署站点

部署作业和 **Settings > Pages** 会显示站点地址。普通项目仓库通常使用 `https://<owner>.github.io/<repository>/`，名为 `<owner>.github.io` 的仓库使用根路径。

## 根站点与项目路径

部署到其他静态主机时运行：

```sh
jekyll-obsidian build --url https://example.com --baseurl /project
```

上传 `.jekyll-obsidian-cache/site/`。根路径站点使用 `--baseurl ""`。生产构建需要域名来源，也可以在站点配置中设置 `url` 和 `baseurl`；显式命令行参数优先。

## 自定义域名

在 GitHub Pages 中配置自定义域名和 DNS。工作流会从 Pages 元数据读取最终的域名和基础路径，无需在该工作流的站点配置中写死这些值。

## 更新构建工具

将 Action 引用改为已发布的发行 tag。每个 Action 版本安装其对应的 gem，内容和配置保留在宿主仓库中，无需复制实现目录或运行快照更新器。
