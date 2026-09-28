# jekyll-obsidian

[English](README.md) | 简体中文

`jekyll-obsidian` 可以将 Markdown 文件夹（包括 Obsidian 知识库）发布为博客或文档站。继续在编辑器中写作并推送，GitHub Actions 就会构建和发布。仓库只需添加配置文件和工作流，发布实现通过 `jekyll-obsidian-site` Ruby gem 安装。

在线预览：[sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

每次构建可选择一个内置主题：

- `minimal` 将自定义 Home 页面、最近文章、完整 Blog、文档和显式配置的自定义栏目组合为个人或组织站点。
- `docs` 提供文档目录树以及上一篇、下一篇导航。

两个主题均默认启用搜索、Wiki 链接阅读预览、页面大纲、笔记关系和交互式局部图谱。当笔记与另一篇公开笔记存在链接或嵌入关系时，局部图谱位于右侧上下文栏顶部；孤立笔记和仅自链笔记不显示它。图谱上的两个控件可分别打开完整公开图谱，或放大当前笔记的邻接关系。完整图谱仍包含所有公开笔记；站点不会生成独立的 `/graph/` 页面。

切换主题不会改变笔记 URL。默认构建和部署主题为 `minimal`。两个主题都支持通过 `_translations/<locale>/` 发布语言覆盖层，也可以为文章接入 GitHub Discussions 评论。存在对应配置但省略 `enabled` 时，本地化仅在 `docs` 中默认启用，评论仅在 `minimal` 中默认启用。

语言清单、默认语言与译文的职责边界、回退页面和 SEO 行为详见[本地化指南](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Localization.md)。

Minimal 还提供 Blog、标签、Atom 订阅源、联系方式、源码操作，以及自动检测并生成项目卡片的作品集。项目页可以直接使用一篇公开 GitHub Markdown 作为正文。两个主题都会生成 Search 与 Graph 数据、canonical 元数据、站点地图、404 页面和不含 frontmatter 的 Markdown 资源。可选流量统计支持 Cloudflare Web Analytics 或 Google Analytics，配置前始终关闭。

## 发布前须知

使用 GitHub Pages 部署时，本地计算机无需安装 Ruby、Node.js、Bundler、npm 或浏览器。生成的 GitHub Actions 工作流会安装完整构建工具链。

[GitHub Free 的公开仓库可以使用 GitHub Pages](https://docs.github.com/zh/pages/quickstart#谁可以使用此功能)，因此公开的 `jekyll-obsidian` 站点无需付费托管。

发布策略决定哪些内容进入生成的站点，但不会让仓库中其他已提交文件变成私密内容。任何能读取仓库的人同样可以读取未发布笔记，因此不要提交密钥、个人记录或其他私密资料。

公开笔记链接到 Canvas 或 Bases 文件时，这些文件会作为下载内容发布。提交前请检查其中是否包含未发布材料的摘录或引用。

## 集成到你的仓库

1. 根据[配置示例](examples/jekyll-obsidian.yml)创建 `.github/jekyll-obsidian.yml`：

```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

2. 将 [Pages 工作流](examples/pages.yml)复制到 `.github/workflows/pages.yml`。
3. 在 `docs/` 中添加一篇带 `publish: true` 的 Markdown 笔记，在 **Settings > Pages > Build and deployment > Source** 中选择 **GitHub Actions**，然后推送。

内容也可以放在 `website/docs/` 或仓库内的其他目录，直接修改 `website.source` 即可。通过 Actions 发布时，本地无需安装 Ruby、Node.js，也不用运行构建命令。

如果希望在本地初始化，请先安装 Ruby 4.0.x，再运行：

```sh
gem install jekyll-obsidian-site
jekyll-obsidian init --source docs
```

`init` 会创建同样的配置和工作流，只在内容目录不存在或为空时添加公开的欢迎页。已有冲突文件不会被覆盖。Bundler、版本更新和已有仓库的接入方式见[宿主集成](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Integration.md)。

## 预览已部署站点

等待默认分支上的 **Build and deploy Pages** 工作流执行成功。GitHub 会在工作流的 `deploy` 作业和 **Settings → Pages** 中显示部署地址。

未配置自定义域名时，地址通常为：

- 普通项目仓库：`https://<owner>.github.io/<repository>/`
- 仓库名称为 `<owner>.github.io`：`https://<owner>.github.io/`

如果配置了自定义域名，请使用 **Settings → Pages** 中显示的地址。工作流会读取 GitHub Pages 元数据，并自动为该地址构建站内链接。工作流和自定义域名设置详见[部署指南](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Deployment.md)。

## 配置与发布

直接编辑 `.github/jekyll-obsidian.yml`，设置标题、语言、内容目录、主题和功能。修改 `website.source` 或 `website.theme` 会在下一次构建时生效，无需重新生成工作流。

所有配置均位于根级 `website:` 映射中。

两个主题都可以通过 Giscus 将文章评论存储在 GitHub Discussions 中。评论默认使用发布仓库，也可以指向另一个公开仓库。存在 `website.comments` 但省略 `enabled` 时，`minimal` 默认启用评论；`docs` 需要显式设置 `website.comments.enabled: true`。在 Discussions 或 Giscus App 尚未就绪时启用评论不会导致构建失败；Giscus 配置不完整时会产生警告，并显示非交互式回退内容。仓库设置、讨论串标识、隐私边界和故障排查详见[评论指南](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Comments.md)。

使用 Obsidian 或任意 Markdown 编辑器打开内容目录。默认情况下，只有 frontmatter 中包含 YAML 布尔值 `publish: true` 的笔记才会进入站点：

```yaml
---
publish: true
title: A public note
tags:
  - example
---
```

字符串 `"true"` 和 `"yes"` 不会被接受。如需递归发布整个文件夹，请把相对于内容根目录的路径加入 `website.content.publish_by_default`；使用 `.` 可选择完整内容树。默认发布范围内的单篇笔记仍可通过 YAML 布尔值 `publish: false` 排除。生成内容快照前会排除 Obsidian 的 `.obsidian/` 状态目录和 `.trash/` 目录。

内容根目录及其所有子目录都可以不包含 `index.md`。如果文件夹中没有物理 `index.md`，同级且文件名精确为 `README.md` 的公开笔记会成为索引。即使 `index.md` 未发布，它仍然拥有更高优先级，此时 `README.md` 仍是普通笔记。README 被选为索引后仍保留原始路径和源码操作，但会发布到文件夹路由。Minimal 会先在 Home 页面显示选中的公开根索引，再显示最近六篇文章；没有根页面时，Home 仍可显示文章流。没有公开索引的文件夹会链接到排序后的第一个公开页面。内容目录中没有任何公开笔记时，构建仍会失败。

可信的独立 HTML Slide 也可以通过显式路由发布，不经过主题或 Liquid。可以映射单个 `.html` 文件，也可以映射包含 `index.html` 的目录 bundle；除 Markdown 和 `_locale.yml` 等编译器语言清单外，目录中的普通文件会按原相对结构公开：

```yaml
website:
  html:
    slides/product-tour: /slides/product-tour/
```

HTML 映射是独立于 Markdown 默认值的显式发布边界。Raw 页面不会进入导航、Search、Graph、Feed 或 sitemap，并会作为可信同源代码执行。发布前请审查整个 bundle。详见[自定义指南](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Customization.md#独立-html-slides)和[真实 Slide 源码](website/jekyll-obsidian-docs/slides/jekyll-obsidian/index.html)。

使用新版本时，修改工作流中的 Action 版本。本地 gem 安装通过 `gem update jekyll-obsidian-site` 更新；使用 Bundler 时运行 `bundle update jekyll-obsidian-site` 并提交锁文件。内容和配置始终保留在自己的仓库中。

## 可选的本地预览

在 macOS、Linux 或 WSL 中安装 Ruby 4.0.x 后运行：

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

打开 `http://127.0.0.1:58000/`。修改内容或配置会触发完整重建，构建失败时仍可浏览上一次成功生成的站点。运行 `jekyll-obsidian dev --help` 查看主机、端口、基础路径和主题选项。

部署到其他主机时，可运行 `jekyll-obsidian build --url https://example.com --baseurl /project`。输出位于 `.jekyll-obsidian-cache/site/`；`jekyll-obsidian clean` 清理本项目的缓存和输出。gem 已包含前端资源，本地使用无需安装 Node.js。

## 使用指南

- [宿主集成](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Integration.md)：介绍如何安装到其他仓库及后续更新。
- [快速开始](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Getting%20Started.md)：介绍 GitHub Actions 发布、写作和可选本地预览。
- [语法](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Syntax.md)：介绍支持的 Obsidian 风格 Markdown。
- [自定义](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Customization.md)：介绍站点信息、主题、导航和功能。
- [作品集](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Portfolio.md)：介绍项目集合和公开 GitHub Markdown 正文。
- [流量统计](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Analytics.md)：介绍可选的 Cloudflare 与 Google 访问统计。
- [评论](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Comments.md)：介绍 GitHub Discussions 配置和隐私边界。
- [本地化](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Localization.md)：介绍译文、回退页面和本地化 SEO。
- [部署](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Deployment.md)：介绍 GitHub Pages、URL 路径和自定义域名。

贡献者可以继续阅读[开发者指南](website/jekyll-obsidian-docs/docs/development/index.md)。

## 许可证

MIT
