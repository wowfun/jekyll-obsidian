# jekyll-obsidian

[English](README.md) | 简体中文

`jekyll-obsidian` 可以将一个 Obsidian 文件夹发布为通用 Jekyll 站点或文档手册。将项目自带的 `website/` 目录复制到你的仓库中即可；知识库位于该目录之外，仍可直接通过 Obsidian 使用。

在线预览：[sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

每次构建可选择一个内置主题：

- `minimal` 将自定义 Home 页面、最近文章、完整 Blog、文档和显式配置的自定义栏目组合为个人或组织站点。
- `docs` 提供文档目录树以及上一篇、下一篇导航。

两个主题均默认启用搜索、Wiki 链接阅读预览、页面大纲、笔记关系和交互式局部图谱。每篇笔记的局部图谱位于右侧上下文栏顶部。图谱上的两个控件可分别打开完整公开图谱，或放大当前笔记的邻接关系。站点不会生成独立的 `/graph/` 页面。

切换主题不会改变笔记 URL。默认构建主题为 `docs`。两个主题都支持通过 `_translations/<locale>/` 发布语言覆盖层，也可以为文章接入 GitHub Discussions 评论。存在对应配置但省略 `enabled` 时，本地化仅在 `docs` 中默认启用，评论仅在 `minimal` 中默认启用。

语言清单、默认语言与译文的职责边界、回退页面和 SEO 行为详见[本地化指南](website/docs/docs/Localization.md)。

## 发布前须知

使用 GitHub Pages 部署时，本地计算机无需安装 Ruby、Node.js、Bundler、npm 或浏览器。生成的 GitHub Actions 工作流会安装完整构建工具链。

`publish: true` 决定哪些内容进入生成的站点，但不会让仓库中其他已提交文件变成私密内容。任何能读取仓库的人同样可以读取未发布笔记，因此不要提交密钥、个人记录或其他私密资料。

公开笔记链接到 Canvas 或 Bases 文件时，这些文件会作为下载内容发布。提交前请检查其中是否包含未发布材料的摘录或引用。

## 集成到你的仓库

1. 将完整的 `website/` 目录复制到仓库根目录。
2. 在 `website/` 之外选择一个内容目录，例如 `docs/`，并添加至少一篇公开 Markdown 笔记。
3. 在仓库根目录运行集成命令。

在 macOS、Linux 或 WSL 中运行：

```sh
website/bin/integrate --source docs --theme docs
```

在原生 Windows 的 PowerShell 中运行：

```powershell
.\website\bin\integrate.cmd --source docs --theme docs
```

该命令默认使用 `--source docs --theme docs`。它无需安装依赖或访问 GitHub，即可生成 `.github/jekyll-obsidian.yml` 和 `.github/workflows/pages.yml`。

你的仓库将具有以下结构：

```text
repository/
├── docs/
│   └── Start.md
├── website/
└── .github/
    ├── jekyll-obsidian.yml
    └── workflows/
        └── pages.yml
```

打开 GitHub 中的 **Settings → Pages → Build and deployment**，将 **Source** 设为 **GitHub Actions**。提交并推送内容目录、`website/` 和生成的 `.github/` 文件。你不需要创建 `gh-pages` 分支、配置部署密钥，也不需要手动设置 `url` 和 `baseurl`。

除非传入 `--force-workflow`，否则集成命令不会覆盖不属于本项目的 Pages 工作流。已有配置、Windows 使用方式和冲突处理详见[宿主集成](website/docs/docs/Integration.md)。

## 预览已部署站点

等待默认分支上的 **Verify and deploy Pages** 工作流执行成功。GitHub 会在工作流的 `deploy` 作业和 **Settings → Pages** 中显示部署地址。

未配置自定义域名时，地址通常为：

- 普通项目仓库：`https://<owner>.github.io/<repository>/`
- 仓库名称为 `<owner>.github.io`：`https://<owner>.github.io/`

如果配置了自定义域名，请使用 **Settings → Pages** 中显示的地址。工作流会读取 GitHub Pages 元数据，并自动为该地址构建站内链接。工作流和自定义域名设置详见[部署指南](website/docs/docs/Deployment.md)。

## 配置与发布

生成的 `.github/jekyll-obsidian.yml` 是宿主仓库的配置文件。你可以在其中设置站点标题、描述、语言、仓库链接、内容类型和功能开关。请保留 `website.source` 与 `website.theme` 周围的托管标记，并通过带有相应参数的 `website/bin/integrate` 命令修改这两个值。

所有配置均位于根级 `website:` 映射中。

两个主题都可以通过 Giscus 将文章评论存储在 GitHub Discussions 中。评论默认使用发布仓库，也可以指向另一个公开仓库。存在 `website.comments` 但省略 `enabled` 时，`minimal` 默认启用评论；`docs` 需要显式设置 `website.comments.enabled: true`。在 Discussions 或 Giscus App 尚未就绪时启用评论不会导致构建失败；Giscus 配置不完整时会产生警告，并显示非交互式回退内容。仓库设置、讨论串标识、隐私边界和故障排查详见[评论指南](website/docs/docs/Comments.md)。

直接使用 Obsidian 打开内容目录。只有 frontmatter 中包含 YAML 布尔值 `publish: true` 的笔记才会进入站点：

```yaml
---
publish: true
title: A public note
tags:
  - example
---
```

字符串 `"true"` 和 `"yes"` 不会被接受。生成内容快照前会排除 Obsidian 的 `.obsidian/` 状态目录和 `.trash/` 目录。

内容根目录及其所有子目录都可以不包含 `index.md`。Minimal 会先在 Home 页面显示公开的根 `index.md`，再显示最近六篇文章；没有根页面时，Home 仍可显示文章流。缺少索引的文件夹会链接到排序后的第一个公开页面。内容目录中没有任何公开笔记时，构建仍会失败。

更新 `jekyll-obsidian` 时，请替换仓库中的 `website/` 目录，再次运行集成命令，然后提交刷新的生成文件。`website/bin/integrate --check` 可以验证宿主配置与工作流是否仍然同步。

## 可选的本地预览

本地预览需要在 macOS、Linux 或 WSL 中安装 Ruby 4.0.x、Node.js 26.x 和 Git。原生 Windows 用户可以在 WSL 中运行以下命令：

```sh
website/bin/setup
website/bin/dev
```

本地服务器默认地址为 `http://127.0.0.1:58000/`。`website/bin/dev` 默认使用 Minimal 主题；传入 `--theme docs` 可预览独立文档手册。

## 使用指南

- [宿主集成](website/docs/docs/Integration.md)：介绍如何安装到其他仓库及后续更新。
- [快速开始](website/docs/docs/Getting%20Started.md)：介绍本地写作与预览。
- [语法](website/docs/docs/Syntax.md)：介绍支持的 Obsidian 风格 Markdown。
- [自定义](website/docs/docs/Customization.md)：介绍站点信息、主题、导航和功能。
- [部署](website/docs/docs/Deployment.md)：介绍 GitHub Pages、URL 路径和自定义域名。

贡献者可以继续阅读[开发者指南](website/docs/docs/development/index.md)。

## 许可证

MIT
