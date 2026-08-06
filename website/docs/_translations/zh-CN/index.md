---
publish: true
title: Jekyll Obsidian
description: 从同一个 Obsidian 仓库发布通用站点或文档手册。
---

# 一个仓库，两种发布方式

本站既是入门示例，也是 `jekyll-obsidian` 的使用手册。所有页面都来自普通 Markdown 笔记。Minimal 把首页、Blog、Docs 和自定义栏目组成通用站点；Docs 则提供专注的文档手册。

> [!note] 在 Obsidian 中打开源码
> 编译器读取 `website/docs/`，但不会改写内容。你可以直接在 Obsidian 中打开这个目录，继续使用链接、属性、提示块与嵌入。

## 从这里开始

- [[Integration|主机集成]]介绍如何把 `website/` 接入其他仓库。
- [[Getting Started|快速开始]]介绍本地写作与发布边界。
- [[Syntax|语法]]列出 v1 支持的 Obsidian 风格 Markdown。
- [[Customization|自定义]]介绍主题、导航与仓库链接。
- [[Comments|评论]]介绍 GitHub Discussions 配置与讨论串行为。
- [[Localization|本地化]]介绍语言清单、译文覆盖层、回退页面与 SEO 行为。

尚未翻译的页面会保留中文 URL，并明确提示当前显示的是英文原文。

默认构建和部署主题为 Minimal。Docs 适用于独立文档手册；两个主题共用同一组内容路由，不会将 Docs 导航结构带入通用站点。
