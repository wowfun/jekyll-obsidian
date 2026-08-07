---
publish: true
title: 快速开始
description: 通过 GitHub Actions 发布 Markdown 文件夹，需要时再使用本地预览。
---

# 快速开始

Jekyll Obsidian 可以发布任意 Markdown 文件夹，包括 Obsidian 知识库。继续在 Obsidian 或其他文本编辑器中写作，然后推送即可。GitHub Actions 会安装构建工具、检查内容并把站点部署到 Pages。本地无需安装 Ruby 或 Node.js，也不用运行构建命令。

项目自带的内容位于 `website/docs/`，发布实现位于 `website/`。Obsidian 可以直接打开内容目录，无需转换或额外导出。

## 通过 GitHub Actions 发布

将 Jekyll Obsidian 加入其他仓库时，请复制完整的 `website/` 目录，并按照 [[Integration|宿主集成]]操作。其中的无依赖命令可以直接生成宿主配置和 Pages 工作流，无需安装 Ruby 或 Node.js：

```sh
website/bin/integrate --source docs
```

提交内容目录、`website/` 和生成的 `.github/` 文件。在 GitHub 中将 **Settings → Pages → Build and deployment → Source** 设置为 **GitHub Actions**，然后推送。部署完成后，**Verify and deploy Pages** 工作流会显示最终地址。

## 发布一篇笔记

在配置的内容目录中创建 Markdown 文件，并添加包含 YAML 布尔值的 frontmatter：

```yaml
---
publish: true
title: 我的第一篇笔记
tags:
  - fieldwork
---
```

这里必须使用布尔值 `true`，不能使用字符串 `"true"` 或 `"yes"`。未设置默认发布范围时，省略 `publish` 的 Markdown 文件不会进入 HTML、Search、Graph 数据、订阅源、站点地图或复制的附件。

如需递归发布一个目录，请把它相对于内容根目录的路径加入 `website.content.publish_by_default`。特殊路径 `.` 表示完整内容树。在这个范围中，可以用 `publish: false` 排除单篇笔记；范围之外的笔记仍可以通过显式的 `publish: true` 发布。执行发布检查前，编译器会排除内容目录中的 `.obsidian/` 和 `.trash/`。

发布策略只控制生成结果，不能限制仓库访问。不要把密钥、个人记录或其他私密内容放进他人可以读取的仓库。

## 添加链接与附件

继续使用 Obsidian 中的写法：

```md
阅读 [[docs/development/architecture#Compiler boundary]]。
![[docs/development/architecture#^compiler-contract]]
![[assets/research-folio.svg|640]]
```

只有公开笔记、其 `image` 属性或嵌入闭包能够访问的附件才会被复制。`image` 属性还会提供页面的公开 `og:image` 地址。只出现在私密笔记中的文件会被忽略。完整写作契约请参阅 [[Syntax|语法]]。

## 让工作流检查推送

每个拉取请求和默认分支推送都会运行生产编译器与项目检查。生产构建遇到歧义或私密嵌入、循环、路径逃逸、符号链接和 URL 冲突时会停止。普通的未解析链接仍会显示，同时产生警告。

合并或分享站点前，请检查工作流结果。部署作业和 **Settings → Pages** 都会显示公开地址。项目路径、自定义域名和受信任部署作业详见 [[Deployment|部署]]。

## 可选的本地预览

只有需要本地预览或准备修改实现时，才需要安装 Ruby 4.0.x、Node.js 26.x 和 Git。请使用 macOS、Linux 或 WSL。原生 Windows 可以通过 `website\bin\integrate.cmd` 完成集成和部署，再使用 WSL 运行 Jekyll 开发命令。

在仓库根目录运行：

```sh
website/bin/setup
website/bin/dev
```

`website/bin/setup` 会在 `website/` 中安装锁定版本的 Ruby 与 Node 依赖。`website/bin/dev` 会监视配置的内容和站点源码，在需要时重新构建前端资源，并默认用 Minimal 提供 `website/_site` 的本地预览。传入 `--theme docs` 可以预览文档手册。

如需在本地复现生产构建，请运行：

```sh
JEKYLL_ENV=production website/bin/build \
  --url https://example.test \
  --baseurl /jekyll-obsidian \
  --destination _site
```

目标目录始终解析到站点目录下，因此 `_site` 实际写入 `website/_site`。修改实现的贡献者还应阅读 [[docs/development/index|开发者指南]]。

接下来可以阅读 [[Syntax|语法]]、[[Customization|自定义]]或 [[Portfolio|作品集]]。
