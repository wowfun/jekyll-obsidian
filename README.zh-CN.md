# jekyll-obsidian

[English](README.md) | 简体中文

将 Markdown 文件夹或 Obsidian 仓库发布为博客或文档站点。在熟悉的编辑器中写作并推送到 GitHub，Actions 会使用 [jekyll-obsidian-site](https://rubygems.org/gems/jekyll-obsidian-site) Ruby gem 构建和发布站点。

在线预览：[sinputer.top/jekyll-obsidian](https://sinputer.top/jekyll-obsidian/)

选择一个内置主题：

- `minimal`（默认）：自定义首页、近期文章、博客、文档，以及项目集或自定义栏目。
- `docs`：文档目录树，以及上一篇和下一篇链接。

两个主题都提供搜索、Wiki 链接预览、页面大纲、笔记关系和交互式图谱，支持媒体嵌入、多语言翻译和 GitHub Discussions 评论，并生成规范链接元数据、站点地图和可下载的 Markdown。

## 发布到 GitHub Pages

工作流会安装构建工具，本地无需安装 Ruby 或 Node.js。[公开仓库可以通过 GitHub Free 使用 GitHub Pages](https://docs.github.com/en/pages/quickstart#who-can-use-this-feature)。

发布设置控制的是生成的站点，不会限制对已提交文件的访问。能够读取仓库的人也能读取未发布的笔记。请勿将私密内容放入公开仓库；将链接的 Canvas 和 Bases 文件作为下载内容发布前，也应先检查其中的内容。

**已有 Gemfile？** 请先按照[宿主集成](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Integration.md#使用-bundler)配置：Action 要求同时存在 `Gemfile` 和 `Gemfile.lock`，且构建器版本与 Action 发布版本一致。

1. 参照[示例配置](examples/jekyll-obsidian.yml)创建 `.github/jekyll-obsidian.yml`：

<!-- example:site-config -->
```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

2. 将 [Pages 工作流](examples/pages.yml)复制到 `.github/workflows/pages.yml`。
3. 创建 `docs/index.md`：

<!-- example:public-note -->
```markdown
---
publish: true
title: Welcome
---

# Welcome

My first public note.
```

4. 在 **Settings > Pages > Build and deployment > Source** 中选择 **GitHub Actions**，然后提交并推送到默认分支。

**Build and deploy Pages** 成功后，可以在 `deploy` 作业或 **Settings > Pages** 中找到站点地址。项目站点通常使用 `https://<owner>.github.io/<repository>/`；名为 `<owner>.github.io` 的仓库使用域名根路径。工作流还会自动读取自定义域名设置。详见[部署](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Deployment.md)。

## 配置与更新

编辑 `.github/jekyll-obsidian.yml`。站点基本信息（`title`、`description`、`lang`、`url`、`baseurl`）放在 YAML 根层级；内容、主题和功能设置放在 `website` 下。将 `website.source` 设置为相对于仓库根目录的内容路径，将 `website.theme` 设置为 `minimal` 或 `docs`。修改会在下次构建时生效。

默认只发布 frontmatter 中包含 YAML 布尔值 `publish: true` 的笔记。若要递归发布文件夹，可在 `website.content.publish_by_default` 中列出相对于内容目录的路径；`.` 表示整个内容目录树。使用 `publish: false` 排除某篇笔记。`"true"` 等带引号的字符串不是布尔值。Obsidian 的 `.obsidian/` 和 `.trash/` 目录不会被发布。

首页不是必需的：未提供首页时，站点可以打开某个栏目或另一篇公开笔记。站点至少需要一篇公开笔记。索引页选择与导航规则见[自定义](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Customization.md#内容与导航)。

切换主题不会改变仍然公开的笔记 URL。多语言站点应显式设置 `website.i18n.enabled: true`，以便切换主题后继续启用翻译。详见[本地化](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Localization.md)。

功能、多语言和评论设置的默认值见[站点主题](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Customization.md#站点主题)。

升级时，修改工作流中的 Action 发布版本。如果使用 Bundler，还需将 Gemfile 的版本约束改为相同版本，运行 `bundle update jekyll-obsidian-site`，然后将两个依赖文件与工作流一并提交。独立的本地安装可以运行 `gem update jekyll-obsidian-site`。

## 可选的本地预览

在已安装 Ruby 4.0.x 的 macOS、Linux 或 WSL 中，从仓库根目录运行：

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

打开 `http://127.0.0.1:58000/`。修改内容或配置会触发重新构建；构建失败时保留上一次成功的站点。运行 `jekyll-obsidian dev --help` 可查看主机地址、端口、基础路径和主题选项。gem 已包含前端资源，无需安装 Node.js。

若要在本地创建配置和工作流，运行 `jekyll-obsidian init --source docs`。只有内容目录不存在或为空时，它才会添加一篇公开的欢迎笔记；遇到冲突文件时会报告问题，不会覆盖。Bundler 命令见[宿主集成](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Integration.md)。

若要部署到其他服务，运行 `jekyll-obsidian build --url https://example.com --baseurl /project`，然后上传 `.jekyll-obsidian-cache/site/`。`jekyll-obsidian clean` 可清理本项目的缓存和输出。

## 指南与贡献

- [宿主集成](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Integration.md)：安装、Bundler 和升级。
- [快速开始](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Getting%20Started.md)：发布和写作。
- [语法](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Syntax.md)：Obsidian 风格 Markdown 和媒体嵌入。
- [自定义](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Customization.md)：主题、导航、归档栏目、推荐内容和受信任的 HTML 幻灯片。
- [项目集](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Portfolio.md)：项目集合和公开的 GitHub Markdown 正文。
- [访问统计](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Analytics.md)：可选的 Cloudflare 或 Google 流量统计。
- [评论](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Comments.md)：GitHub Discussions 设置与隐私。
- [本地化](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Localization.md)：翻译、回退页面和 SEO。
- [部署](website/jekyll-obsidian-docs/_translations/zh-CN/docs/Deployment.md)：托管、URL 路径和自定义域名。

开发环境设置和原生 Windows PowerShell 命令见[开发指南](website/jekyll-obsidian-docs/docs/development/index.md)。在 macOS、Linux 或 WSL 中，从仓库根目录运行 `website/bin/test`。该命令先构建前端资源并打包 gem，再执行 Ruby、TypeScript、前端和 Node 检查。若要在 `website/` 下单独运行 Ruby 测试，先运行 `npm run build` 和 `bundle exec ruby scripts/package.rb --skip-assets`，再运行 `bundle exec rake test`；测试套件会验证实际安装的 gem。

## 许可证

MIT
