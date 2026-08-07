---
publish: true
title: 部署
description: 使用随附的 GitHub Pages 工作流检查并部署任意内置主题。
---

# 部署

生成的工作流面向 GitHub.com，并将不受信任的验证与受信任的 Pages 构建分开。宿主可以通过 `website/bin/integrate` 或 `website\bin\integrate.cmd` 创建或刷新工作流，无需在本地安装 Ruby 或 Node.js。

## 拉取请求与推送

每个拉取请求和默认分支推送都会检出完整 Git 历史，运行无依赖的集成偏差检查，安装锁定的 Ruby 与 Node 依赖，运行模板测试套件，并校验配置的宿主内容。项目自带的示例会分别在域名根路径构建两个主题，并在项目路径下再次构建 Minimal，从而覆盖两种部署形式：

1. 域名根路径，例如 `https://owner.github.io/`。
2. 项目路径，例如 `https://owner.github.io/jekyll-obsidian/`。

拉取请求作业只有 `contents: read` 权限。它们不会调用 `configure-pages`、上传 Pages 构建产物或执行部署。

工作流会监视配置的内容目录、`website/**`、`.github/jekyll-obsidian.yml` 和自身文件。不要手工编辑这些触发路径；内容目录更改后，请重新运行集成命令。模板浏览器测试与视觉基线始终使用 `website/docs`，另有独立生产构建校验宿主内容，因此自定义文档不会被误判为视觉回归。

## 受信任的 Pages 构建

默认分支收到受信任推送，或从默认分支手动运行工作流时，`build_pages` 会等待验证完成。`actions/configure-pages` 提供权威的 `origin` 和 `base_path`。工作流将两者传给 `website/bin/build`，后者在站点目录内写入临时 Jekyll 配置覆盖层。

作品集项目引用 GitHub Markdown 时，验证作业会把每个移动引用解析为 commit，并导出一份经过摘要校验的内容。受信任的 Pages 构建会使用同一份内容，不会再次读取分支，因此一次工作流中的验证与部署不会发布两个不同版本。

上传前，审计会检查 `website/_site/index.html` 是否存在、每个输出路径是否在允许范围内、链接是否为普通文件而不是符号链接或多硬链接文件，并确认站点没有超过 GitHub Pages 的 1 GB 发布限制。

只有部署作业获得 `pages: write` 和 `id-token: write` 权限。它使用 `github-pages` 环境，并报告部署操作返回的 URL。

## 查找已部署站点

默认分支上的 **Verify and deploy Pages** 成功后，GitHub 会在工作流的 `deploy` 作业和 **Settings → Pages** 中显示公开 URL。部署作业的 `github-pages` 环境也会链接到同一地址。

未配置自定义域名时，名称为 `<owner>.github.io` 的仓库使用 `https://<owner>.github.io/`，其他仓库使用 `https://<owner>.github.io/<repository>/`。

## 根站点与项目路径

编译器不会把 `baseurl` 写入 permalink。统一的 URL builder 会把路由与配置的 base path 组合，用于 HTML、资源、canonical 链接、订阅源、站点地图和 JSON 请求。

拉取请求无法取得 Pages metadata 时，`website/bin/build` 会检查 `GITHUB_REPOSITORY`。名称为 `<owner>.github.io` 的仓库使用域名根路径，其他仓库使用 `/<repository>`。

## 自定义域名

请在 Pages 设置或通过 GitHub Pages API 配置域名，并在 DNS 服务商处添加所需的 CNAME、A、ALIAS 或 ANAME 记录。使用 Actions 发布时，仓库中的 `CNAME` 文件会被忽略。部署后，应以 **Settings → Pages** 报告的自定义 URL 为准。

添加或删除域名后，请手动运行一次工作流。重新构建会更新 canonical URL、Open Graph 元数据、Atom 链接和站点地图。

本地命令请返回 [[docs/Getting Started|快速开始]]，构建内部实现请参阅 [[docs/development/architecture|架构]]。
