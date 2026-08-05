---
publish: true
title: 快速开始
description: 配置站点、发布第一篇笔记并启动本地预览。
---

# 快速开始

示例内容位于 `website/docs/`，发布工具位于 `website/`。Obsidian 可以直接打开内容目录，无需转换或额外导出。

## 安装工具链

本地预览需要 Ruby、Node.js 与 Git。请在仓库根目录运行：

```sh
website/bin/setup
website/bin/dev
```

`website/bin/dev` 默认预览 Minimal 通用站点；使用 `website/bin/dev --theme docs` 预览独立文档手册。

## 发布一篇笔记

在 `website/docs/` 下创建 Markdown 文件，并添加 YAML 布尔值：

```yaml
---
publish: true
title: 我的第一篇笔记
---
```

只有 `publish: true` 的笔记会进入 HTML、搜索与站点地图。未提交的私密内容仍应放在其他仓库或忽略目录中。

继续阅读 [[Syntax|语法]]，或查看 [[Deployment|部署]]流程。
