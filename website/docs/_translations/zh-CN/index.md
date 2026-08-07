---
publish: true
title: Jekyll Obsidian
description: 从同一个 Markdown 文件夹发布通用站点或文档手册。
---

# 一个 Markdown 文件夹，两种发布方式

**把 Markdown 文件夹直接变成完整的博客或文档站。推送到 GitHub 后，GitHub Actions 会自动构建并发布，本地不用安装构建工具，也不用运行构建命令。**

这个可直接使用的示例也是 `jekyll-obsidian` 的使用手册。继续用任意文本编辑器写普通 Markdown 即可；Minimal 会把同一个内容目录变成个人站点或博客，Docs 则把它变成专注的文档手册。推送更改后，随附的 GitHub Actions 工作流会构建所选主题并发布到 Pages。你无需在本地运行构建命令，也不用维护付费服务器。

> [!note] 在 Obsidian 中打开源码
> 编译器读取 `website/docs/`，但不会改写内容。你可以直接在 Obsidian 中打开这个目录，继续使用链接、属性、提示块与嵌入。

## 从这里开始

- [[Integration|宿主集成]]介绍如何把 `website/` 接入其他仓库。
- [[Getting Started|快速开始]]介绍 GitHub Actions 发布方式、写作边界和可选本地预览。
- [[Syntax|语法]]列出 v1 支持的 Obsidian 风格 Markdown。
- [[Customization|自定义]]介绍主题、导航与仓库链接。
- [[Portfolio|作品集]]介绍自动项目集合和外部 GitHub Markdown 正文。
- [[Comments|评论]]介绍 GitHub Discussions 配置与讨论串行为。
- [[Analytics|流量统计]]介绍可选的 Cloudflare 与 Google 访问统计。
- [[Localization|本地化]]介绍语言清单、译文覆盖层、回退页面与 SEO 行为。
- [[Deployment|部署]]介绍从拉取请求到 GitHub Pages 发布的工作流。

## 功能索引

- [[Integration|宿主集成]]、[[Getting Started|快速开始]]和 [[Deployment|部署]]介绍无需本地构建的 GitHub Actions 路径、可选预览、根路径或项目 `baseurl`，以及自定义域名。
- [[Customization|自定义]]介绍 Minimal 与 Docs、页面、文章、文档、Blog、导航、联系方式、标签、Atom 订阅源和生成的系统路由。[[Portfolio|作品集]]负责项目集合、外部 GitHub 正文和查看导入的 Markdown 操作。
- [[Syntax|语法]]和 [[Customization|自定义]]介绍 OFM、媒体、Search、预览、大纲、关系、局部与完整 Graph、Copy page、View as Markdown 和源码操作。
- [[Localization|本地化]]、[[Comments|评论]]和 [[Analytics|流量统计]]介绍语言覆盖层、Giscus 与可选流量统计。编译器还会生成 canonical 元数据、站点地图、404 页面，以及按语言分区的 Search 与 Graph 资源。

开发者文档尚未翻译时，会保留中文 URL，并明确提示当前显示的是英文原文。普通用户指南均提供中文版本。

默认构建和部署主题为 Minimal。Docs 适用于独立文档手册；两个主题共用同一组内容路由，不会将 Docs 导航结构带入通用站点。
