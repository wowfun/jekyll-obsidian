---
publish: true
title: 快速开始
description: 通过 GitHub Actions 发布 Markdown 文件夹，需要时再使用本地预览。
---

# 快速开始

Jekyll Obsidian 可以将 Markdown 文件夹或 Obsidian 知识库发布为博客或文档站。你可以完全通过 GitHub Actions 发布，需要时再添加本地预览。

## 通过 GitHub Actions 发布

按照 [[Integration|宿主集成]]添加配置和工作流，选择 `docs/` 或 `website/docs/` 等内容目录，再将 Pages 发布来源设为 GitHub Actions。推送修改即可发布。

默认只公开带 YAML 布尔值 `publish: true` 的笔记：

```yaml
---
publish: true
title: My first note
---
```

如需发布整个目录，请将它显式加入 `website.content.publish_by_default`。路径相对于内容目录，`.` 表示整个内容树；带 `publish: false` 的单篇笔记仍会被排除。发布规则不会让公开 Git 仓库里的文件变成私密内容。

## 写作与链接

用 Obsidian 或文本编辑器打开内容目录。Wiki 链接、嵌入、提示块和受支持的 Markdown 会经过编译，源文件不会被改写。写作规则见 [[Syntax|语法]]。

公开的根目录 `index.md` 会成为主页；不存在物理 `index.md` 时，公开的 `README.md` 可以承担这个角色。文件夹不必包含索引文件，站点可以链接到其中第一篇公开页面。至少需要一篇公开笔记。

## 配置站点

直接编辑 `.github/jekyll-obsidian.yml`。`website.theme: minimal` 提供 Home、Blog 和自定义栏目，`website.theme: docs` 提供文档目录树。切换主题不会改变笔记 URL。导航和功能配置见 [[Customization|自定义]]。

## 本地预览

在 macOS、Linux 或 WSL 中安装 Ruby 4.0.x 后运行：

```sh
gem install jekyll-obsidian-site
jekyll-obsidian dev
```

打开 `http://127.0.0.1:58000/`。修改内容或配置会触发完整重建，构建失败时保留上一次成功的站点。可以用 `jekyll-obsidian dev --theme docs` 临时切换主题。

## 部署与更新

站点地址会显示在 **Settings > Pages** 和工作流部署结果中。Actions 会从 Pages 元数据读取域名和基础路径，自定义域名见 [[Deployment|部署]]。

更新时修改 Action 的固定版本引用，或通过 RubyGems/Bundler 更新本地安装。具体命令见 [[Integration|宿主集成]]，项目开发说明见 [[docs/development/index|开发者指南]]。
