---
publish: true
title: 作品集
description: 发布项目页面，并将公开的 GitHub README 作为项目正文。
---

# 作品集

Minimal 可以将内容目录中的一个文件夹变成作品集标签页、集合页和项目网格。是否存在作品集、哪些页面属于作品集，都由编译器判断；模板和浏览器代码不会检查源目录。

## 让 Minimal 自动检测作品集

未配置作品集时，Minimal 会检查内容根目录下的 `portfolio` 文件夹。只要其中存在至少一篇已发布且没有设置 `nav_exclude: true` 的 Markdown 项目，作品集就会出现。

检测会递归查找子目录。文件夹中只有附件、草稿、`index.md` 或全部被排除的项目时，不会启用作品集。索引页用于介绍作品集，但不算项目。

可以在 `website.navigation` 下修改路径、标签、顺序或标签页可见性：

```yaml
website:
  theme: minimal
  navigation:
    portfolio:
      path: work
      label: Work
      order: 30
      visible: true
```

`path` 相对于 `website.source`，可以包含多层 POSIX 路径片段。显式路径会取代 `portfolio`；路径不存在或没有项目时，作品集保持关闭。设置 `visible: false` 只会隐藏内置标签页，不会删除作品集索引、项目路由或激活范围。自定义文件夹导航不能重复使用当前作品集路径。

Docs 会校验作品集配置，但不会生成标签页、集合索引或项目网格。该路径下的笔记保留普通 Docs 分类。

## 编写项目页面

在 Minimal 中，当前作品集路径下的所有已发布 Markdown 后代都属于作品集，其有效类型统一为 `page`。目录默认值不能把它改成文章或文档。显式设置 `content_type: post` 或 `content_type: doc` 会让构建失败。

设置 `nav_exclude: true` 可以让项目不进入网格。详情路由仍然公开；直接打开该路由时，如果作品集标签页可见，它仍保持激活状态。

设置了 `pinned: true` 的项目排在普通项目之前。各组内部优先排列设置了 `nav_order` 的项目，再依次按 `nav_order`、本地化标题和源路径排序。卡片使用标题、可选的 `image` 与 `description`；未设置 `description` 时，沿用现有正文预览。缺少图片或摘要时不会显示占位内容。

本地 GIF、WebP、AVIF 和 APNG 文件会逐字节复制，并通过普通图片元素显示。编译器不会转码或生成缩略图。

## 添加介绍或自定义路由

创建 `<path>/index.md` 后，可以在项目网格上方显示自定义介绍。其 frontmatter、正文、译文、大纲、图谱和源码操作与普通公开笔记一致。索引页中的 `permalink` 决定作品集入口路由。

没有索引页时，编译器会通过虚拟的 `<path>/index.md` 推导路由，并生成系统页面。该页面没有源文件、Markdown 端点、评论或源码操作。

## 引用 GitHub Markdown 文件

作品集项目可以将 `github.com` 中的一篇公开 Markdown 文件用作完整正文：

```yaml
---
publish: true
title: 示例项目
description: 显示在作品集卡片中的简短摘要。
github_markdown: https://github.com/owner/repository/blob/main/README.md
---
```

本地项目页的正文必须为空。frontmatter 后出现任何非空白内容时，构建会报告 `github_markdown_body_conflict`。发布状态、标题、描述、图片、置顶、顺序、路由和其他页面元数据仍由该项目页管理。

URL 简写接受公开的 GitHub `blob` URL，其中分支、tag 或 commit 引用只能包含一个路径片段。引用中包含 `/` 时，请使用映射形式：

```yaml
github_markdown:
  repository: owner/repository
  ref: release/v2
  path: docs/README.md
```

首版只支持公开的 `github.com` 仓库及 `.md` 或 `.markdown` 文件。私有仓库、访问令牌、GitHub Enterprise、Gist、GitHub 原始内容 URL、任意域名、凭据、未知配置项，以及逃出仓库根目录的路径都会被拒绝。

构建会先把引用解析为 commit，再读取该 commit 中的精确版本。因此，分支会在下一次推送、拉取请求或手动构建时跟随最新 commit，同一次构建生成的所有页面则使用同一版本。项目不会新增定时构建。移动引用无法解析时，构建会失败，不会发布过期的缓存正文。

精确文档会按仓库、commit 和路径缓存。单个文件最大为 1 MiB；一个站点最多引用 28 个文件，总计不超过 8 MiB。随附的 GitHub Actions 工作流会让验证与部署复用同一份经过验证的不可变内容。标准测试使用本地固定数据，不会连接 GitHub。

## 理解引用后的正文

外部文件使用安全的 CommonMark 与 GFM 规则。原始 HTML、远程 frontmatter、Obsidian Wiki 链接、嵌入和块 ID 都不会被解释。文件中的第一个一级标题会保留，页面外壳不会再添加重复标题。正文会进入项目详情、大纲、预览、Search 和 View as Markdown 输出，但不会创建远程 Graph 关系，也不会递归引用链接到的其他 Markdown 文件。

只有片段的链接仍指向当前项目页。相对链接会指向 GitHub 中同一 commit 下的对应文件或目录；目录目标应以 `/` 结尾，而 `LICENSE` 等无扩展名文件仍按文件处理。相对图片使用同一 commit 的原始文件地址。相对路径不能逃出仓库根目录。

Edit 仍然打开本地项目页，查看导入的 Markdown 则打开实际提供正文的精确 GitHub commit。译文项目页可以声明另一份 `github_markdown`。没有对应译文项目页时，现有本地化回退会显示默认语言项目，并继续禁止搜索引擎收录。

## 排查作品集问题

| 现象 | 检查项 |
| --- | --- |
| 看不到作品集标签页 | 确认当前主题为 Minimal，并且配置路径中存在已发布且没有设置 `nav_exclude: true` 的项目。 |
| 已有索引页，但作品集仍未启用 | `index.md` 不算项目。请另行添加一篇已发布 Markdown。 |
| 项目报告内容类型冲突 | 删除显式的 `post` 或 `doc` 类型。作品集项目统一为页面。 |
| 外部正文与本地内容冲突 | 保留项目页 frontmatter，并删除其后的所有非空白字符。 |
| GitHub 链接无法通过校验 | 使用公开的 `github.com` Markdown 文件。引用中包含 `/` 时改用映射形式。 |
| 分支更新没有出现在站点中 | 推送更改或手动运行 Pages 工作流。分支内容只在构建时刷新，不会定时刷新。 |

完整导航配置请参阅 [[Customization#Minimal 导航|自定义]]，翻译归属规则请参阅 [[Localization|本地化]]。
