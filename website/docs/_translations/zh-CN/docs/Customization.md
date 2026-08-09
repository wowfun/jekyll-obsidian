---
publish: true
title: 自定义
description: 调整站点信息、视觉 token、导航和仓库链接。
---

# 自定义

项目自带的默认值位于 `website/_config.yml`。宿主仓库应把覆盖值写入由 `website/bin/integrate` 生成的 `.github/jekyll-obsidian.yml`，以便日后替换 `website/`。最终生效的公开配置仍可在一个文件中审阅：

```yaml
title: My Site
description: Built from Markdown
lang: en
url: ""
baseurl: ""

website:
  # jekyll-obsidian:managed-start
  source: docs
  theme: minimal
  # jekyll-obsidian:managed-end
  syntax_profile: ofm@1
  repository: owner/repository
  edit_branch: main
  content:
    publish_by_default: []
    default_type: doc
    directories:
      post: []
      doc: []
  features: {}
  contacts:
    - label: GitHub
      url: https://github.com/owner
    - label: Email
      url: mailto:hello@example.com
```

`website.source` 相对于宿主仓库根目录。项目自带的默认配置使用 `source: website/docs`，生成的宿主覆盖通常使用 `source: docs`，或 `website/` 之外的其他目录。

规范命令会依次合并 `website/_config.yml`、`.github/jekyll-obsidian.yml`，以及临时命令行值或 Pages 值。集成命令只管理宿主文件中标记之间的 `source` 和 `theme`；标题、仓库链接、内容分类和功能覆盖仍可在标记外编辑。`bin/build` 会把 Jekyll source、实现目录、缓存、目标目录和安全设置固定在 `website/`。直接运行 `jekyll` 不会载入宿主覆盖或这些归属保护，因此不是受支持的入口。

`website.theme` 用于选择 `minimal` 或 `docs`。`website.syntax_profile` 固定 Markdown 契约，目前只接受 `ofm@1`。`website.edit_branch` 决定 Edit 与其他宿主源码链接所用的分支，默认值为 `main`。

## 发布默认值

`website.content.publish_by_default` 是一个目录数组，其中的路径相对于 `website.source`。每个条目会选择该目录及其后代中的 Markdown 文件。默认数组为空，因此笔记必须通过 `publish: true` 明确加入。如果除显式排除的笔记外，整个内容树都应发布，可以使用 `.`：

```yaml
website:
  content:
    publish_by_default:
      - .
```

显式 YAML 布尔值始终优先。`publish: false` 会从已选择目录中排除一篇笔记，`publish: true` 则可以加入目录范围外的一篇笔记。发布目录不会决定内容分类；已发布笔记是页面、文章还是文档，仍由 `default_type`、`directories.post`、`directories.doc` 和笔记的 `content_type` 决定。附件只有在已发布笔记、其 `image` 属性或嵌入闭包引用时才会公开。

## 站点信息

`title`、`description` 和 `lang` 会进入站点外壳、元数据、Atom 和无障碍标签。将 `website.repository` 设为 `owner/repository` 可以显示 Edit 链接。该值为空时，构建会检查 `GITHUB_REPOSITORY` 和本地 `origin` remote。无法识别仓库时，操作会保持隐藏。这个宿主仓库配置不会更改页脚中的 Built by Jekyll Obsidian 链接；页脚始终指向官方项目 `https://github.com/wowfun/jekyll-obsidian`。

Minimal Home 会先显示公开的根 `index.md`，再用编辑式列表显示最近六篇文章。带图片的条目在宽屏中把 16:9 缩略图放在摘要旁边，在窄屏中放到摘要上方；没有图片的条目会占满宽度，不显示占位图。摘要还可以显示 `subtitle`、正文摘录、作者和发布日期。Blog 链接会打开 `/blog/` 中完整的倒序文章列表。

配置 `website.contacts` 后，可以在最近文章区之后显示联系方式。每个条目都需要简短的 `label`，以及采用 `https:`、`mailto:` 或 `tel:` 的 URL。基础配置没有联系方式时，可以省略该项或使用空数组。Email、Phone、GitHub、LinkedIn、X/Twitter、Mastodon、Bluesky、Instagram、YouTube、Telegram、RSS 和 Website 链接会自动获得无障碍图标。其他服务会直接显示文本标签，因此配置保持服务中立，不需要额外的 icon 字段。

## 站点主题

每次构建会选择一个完整展示方案。`minimal` 在通用站点外壳中提供 Home、Blog、Docs 和自定义栏目，`docs` 则提供专注的分层手册。两个主题共享 Search、Wiki 链接预览、页面大纲、笔记关系和交互式图谱。可以用命令行覆盖配置，在不修改文件的情况下比较同一份内容：

```sh
website/bin/dev --theme docs
website/bin/build --theme minimal --url https://example.test --baseurl "" --destination _site
```

构建会把指定目标写入 `website/` 下，因此 `_site` 实际为 `website/_site`。主题标识只支持 `minimal` 和 `docs`。

`website.features` 中省略的功能会继承主题默认值。可以用显式 YAML 布尔值覆盖 `search`、`tags`、`feed`、`graph`、`relations`、`previews` 和 `outline`。

| 功能 | Minimal | Docs |
| --- | --- | --- |
| `search`、`previews`、`outline`、`relations`、`graph` | 开启 | 开启 |
| `tags`、`feed` | 开启 | 关闭 |

将任意共享功能设为 YAML 布尔值 `false` 即可移除。例如：

```yaml
website:
  features:
    graph: false
    previews: false
```

## Minimal 导航

Minimal 默认提供 Home、Blog、Docs 和 Portfolio，顺序分别为 `0`、`10`、`20` 和 `30`。内容树中没有公开文章或文档时，Blog 与 Docs 会自动消失。Portfolio 默认使用相对于内容根目录的 `portfolio` 文件夹；其中存在至少一个可见的已发布项目时才会显示。空文件夹或只有未发布内容的文件夹不会增加标签页。可以在 `website.navigation` 中覆盖内置标签、顺序、可见性或作品集路径：

```yaml
website:
  theme: minimal
  navigation:
    home:
      label: Home
      order: 0
      visible: true
    blog:
      label: Writing
      order: 10
      visible: true
    docs:
      label: Handbook
      order: 20
      visible: true
    portfolio:
      path: work
      label: Work
      order: 30
      visible: true
    folders:
      - path: team
        label: Team
        order: 40
```

作品集路径相对于 `website.source`；显式路径会取代默认的 `portfolio`。该路径下的已发布 Markdown 后代统一变成作品集页面，因此其中显式设置的 `content_type` 必须为 `page`。公开的 `<path>/index.md` 会在项目网格上方保留自定义介绍；没有索引时，编译器会在该路由生成作品集索引。索引本身不算项目。设置了 `pinned: true` 的项目排在最前；置顶组和普通组内部再依次按 `nav_order`、标题和路径排序。项目设置 `nav_exclude: true` 后不会显示卡片；设置 `website.navigation.portfolio.visible: false` 只会隐藏标签页，作品集索引和项目页面仍然公开。

项目卡片使用 `image`、标题和 `description`；未设置描述时，会回退到正文预览。本地 GIF、WebP、AVIF 与 APNG 文件会逐字节复制并通过 `<img>` 显示，从而保留动画。编译器不会转码或生成缩略图。

项目可以通过 `github_markdown` 将本地正文替换为公开的 GitHub Markdown 文件。本地项目页继续管理卡片元数据和路由，解析后的远程正文则用于详情页、大纲、Search 文本、预览和 Markdown 端点。接受的 URL 与映射格式、空正文规则、分支刷新、内容上限、相对 URL、本地化和安全边界详见 [[Portfolio|作品集]]。

自定义文件夹路径同样相对于 `website.source`，但它只选择有效 `content_type` 为 `page` 的已发布页面。存在公开 `index.md` 时，该索引是标签页目标；没有索引时，标签页会打开依次按 `nav_order`、标题和路径排序的第一个可见页面。文件夹标签优先使用索引标题，否则使用最后一个路径片段的可读形式。自定义文件夹默认顺序为 `100`，`visible` 默认为 `true`。普通文件夹只有在此处列出后才会成为标签页。自定义文件夹不能重复使用当前作品集路径。

公开独立页面也可以通过 frontmatter 加入同一导航：

```yaml
---
publish: true
content_type: page
navigation:
  label: About
  order: 15
  visible: true
---
```

标签默认使用页面标题，顺序默认为 `100`，可见性默认为 `true`。只有有效内容类型为 `page` 的已发布笔记才能声明 `navigation`。来源或目标重复、与保留的内置项目冲突、路径无效，以及文件夹中没有可见目标都会让构建失败。译文可以替换 `navigation.label`；`order` 与 `visible` 由默认语言页面管理。

桌面标题栏放不下的标签页会进入无障碍 More 菜单。移动端 Browse 面板和 Search 对话框的快速导航会复用同一组有序目标和激活状态。Search 会按配置标签筛选快速链接，同时查询笔记正文。没有 JavaScript 时，标题栏链接仍然可见，并会自然换行。从 Minimal 打开 Docs 时会保留 Minimal 站点外壳，同时加入手册目录、页面大纲及上一篇或下一篇链接。

## 图谱与 Wiki 链接预览

已发布笔记只有在当前语言分区中与另一篇公开笔记存在链接、嵌入、反向链接或反向嵌入时，才会在右侧上下文栏的大纲与关系上方显示一跳图谱。图谱包含当前笔记及这些直接邻居。孤立笔记和仅包含自链的笔记不会显示局部图谱，但完整图谱仍会包含它们。节点面积会随其在完整公开图谱中的度数增加。

图谱左侧按钮打开完整图谱，右侧按钮放大当前笔记的局部图谱。在任一视图中，都可以在画布上滚动鼠标滚轮，以指针为中心缩放；拖动空白画布可以平移；拖动相邻节点可以改变位置。当前节点始终固定在视觉中心。单击节点可以访问对应笔记；键盘聚焦后按 Enter 或 Space 也可以打开。完整图谱 JSON 只在打开对话框时载入，并始终包含全部公开节点与关系。为了保持响应速度，SVG 查看器不会渲染超过 250 个节点或 1,000 条关系的完整图谱，而会提示读者使用局部图谱或 Search。站点不会生成 `/graph/` 页面或导航标签，因此已发布笔记可以使用该路由。

鼠标在 Wiki 链接上停留 0.3 秒，或使用键盘聚焦链接时，会打开阅读预览。在延迟结束前移出指针会取消预览；键盘聚焦仍会立即打开。预览先显示目录元数据，再以较小的可见高度显示目标笔记经过清理且可独立滚动的正文。点击预览标题可以进入目标笔记；正文中的链接仍只显示为文本。触摸屏点击原 Wiki 链接会直接进入目标页面。设置 `previews: false` 可以关闭该行为。

## GitHub Discussions 评论

两个主题都可以通过 [Giscus](https://giscus.app/) 为每篇 `content_type: post` 关联 GitHub Discussion。未配置 `website.comments` 时，评论保持关闭。该映射存在但省略 `enabled` 时，Minimal 默认开启，Docs 默认关闭。首先需要准备一个公开 GitHub 仓库：

1. 打开 **Settings → General → Features → Discussions**。
2. 创建 `Blog comments` 分类。建议使用 Announcement 格式，维护者和 Giscus 可以创建讨论，访客仍可回复。
3. 为该仓库安装 [Giscus GitHub App](https://github.com/apps/giscus)。
4. 在 [giscus.app](https://giscus.app/) 中填写仓库和分类，并复制生成的 ID。

随后把这些值加入宿主配置：

```yaml
website:
  theme: minimal
  repository: owner/site
  comments:
    # 可选。省略后复用 website.repository。
    repository: owner/community
    repository_id: R_kgDOxxxxxxxx
    category: Blog comments
    category_id: DIC_kwDOxxxxxxxx
```

Docs 主题需要在 `comments` 中添加 `enabled: true`；如果只想保留 Minimal 配置但暂不启用，请添加 `enabled: false`。评论仓库可以是发布仓库，也可以是独立的公开社区仓库。构建不会检查 Discussions 是否启用或 Giscus App 是否安装。服务 ID 不完整时，构建会产生警告，并显示不可交互的降级内容，不会直接失败。需要把嵌入限制在生产站点来源时，可以在评论仓库中添加 `giscus.json`。

启用后，任意主题中的每篇 `content_type: post` 都会显示评论。可以用 YAML 布尔值关闭单篇文章：

```yaml
---
publish: true
content_type: post
comments: false
---
```

讨论串使用由笔记路径生成的严格标识，不依赖路由。更改域名、`baseurl` 或 permalink 不会更换讨论串；移动或重命名源笔记则会产生新的标识。站点启用表情回应，输入框显示在现有评论上方，Giscus iframe 在评论区域接近视口时延迟载入。Giscus 客户端仍会在已发布评论页初始化时发出请求。

本地开发不会连接 Giscus，而会显示仅限发布站点的提示和普通 Discussions 链接。已发布站点和 CI 构建会载入组件，使其跟随站点浅色或深色配色，并在 JavaScript 或外部服务不可用时保留 GitHub 链接。本地化页面共享文章的路由无关讨论串；Giscus 支持该页面语言时使用相应界面，否则回退到英文。

讨论串标识、来源限制、隐私边界和问题排查详见 [[Comments|使用 GitHub Discussions 提供评论]]。

## 流量统计

未配置 `website.analytics` 时，流量统计保持关闭。生产站点可以选择 Cloudflare Web Analytics：

```yaml
website:
  analytics:
    provider: cloudflare
    token: SITE_TOKEN
```

也可以选择一个 Google Analytics 4 属性：

```yaml
website:
  analytics:
    provider: google
    measurement_id: G-XXXXXXXXXX
```

一个站点只能启用一家服务。本地开发和重定向页面不会载入统计客户端。`website/bin/integrate` 会保留已有映射，但不会主动创建。服务配置、Docs 导航跟踪、内容安全策略来源、隐私差异和问题排查详见 [[Analytics|流量统计]]。

## 本地化

两个主题都可以通过 `website.i18n` 中的语言列表启用静态本地化。该映射存在时，Docs 默认启用，Minimal 默认关闭，需要显式设置 `enabled: true`。顶层 `lang` 是默认语言；本地化启用时，它必须出现在列表中：

```yaml
lang: en

website:
  theme: docs
  i18n:
    locales:
      - en
      - zh-CN
```

Minimal 需要在 `i18n` 下添加 `enabled: true`；Docs 可以通过 `enabled: false` 暂停已经配置的语言方案。默认语言保留在普通内容树中。其他语言的笔记放在 `_translations/<locale>/` 下相同的相对路径中。译文继承公开默认语言笔记的发布状态；设置 `publish: false` 后，该语言 URL 会显示现有的默认语言回退内容。每个配置的语言都需要在其根目录提供 `_locale.yml`。`name` 为必填项；`hreflang`、`dir` 和封闭的 `messages` 目录可选。译文缺失或停用不会让构建失败。对应本地化 URL 会显示默认语言正文和提示，并从搜索引擎索引与站点地图中排除。

```yaml
name: 简体中文
hreflang: zh-Hans
dir: ltr
messages:
  search: 搜索
```

`dir` 只接受 `ltr` 或 `rtl`。文案值必须是字符串，配置键必须属于内置主题文案目录；未知键会让构建失败。省略的文案使用内置英文。语言列表顺序也是语言切换器顺序。

默认语言保留现有 URL。其他语言使用配置的 tag 作为路径前缀，例如 `/zh-CN/docs/Getting%20Started/`。Minimal 与 Docs 的导航、Search、主题系统页、语言切换、SEO 元数据和语言资源都会保持分区。

语言清单、译文归属、回退页面、SEO 行为和问题排查详见 [[Localization|本地化]]。

## 颜色与字体

两个主题共享一小组 CSS 自定义属性。浅色模式使用暖色纸张与表面色，深色模式使用中性黑灰色。蓝色标记链接与焦点，陶土色标记关系与次级注释。

正文和控件使用平台无衬线字体，系统已安装时会优先使用 Noto Sans CJK 或思源黑体。代码使用平台等宽字体。站点不会下载 Web Font，因此具体字形取决于读者操作系统，字号与间距仍保持一致。

请在自己的样式表中覆盖 token，不要编辑带 hash 的构建输出。浅色与深色配色中的文本和焦点对比度都应达到 WCAG AA。

## 页面属性

编译器只接受以下笔记属性：

- `publish`、`title`、`subtitle`、`aliases`、`tags`、`author`、`categories` 和 `description`
- `permalink`、`image` 和 `cssclasses`
- `created` 和 `updated`
- `content_type`、`date`、`pinned`、`nav_order`、`nav_exclude` 和 `navigation`
- `comments` 和 `github_markdown`

未知属性不会进入 Liquid 或生成数据。`aliases`、`tags`、`author`、`categories` 和 `cssclasses` 是字符串数组，`subtitle` 是字符串。`publish`、`pinned`、`nav_exclude` 和 `comments` 使用 YAML 布尔值。`navigation` 是前文说明的封闭映射。`github_markdown` 只接受 [[Portfolio|作品集]]中说明的 URL 或映射形式，并且只能用于作品集项目页。日期使用 ISO 8601。笔记标题依次取自 `title`、第一个一级标题和文件名。

`updated` 可选，只有作者明确提供时才会出现在页面元数据中；编译器不会从 Git 推导更新时间。文章发布时间依次使用 `date`、`created` 和第一次 Git 提交时间。Atom 条目优先使用显式 `updated`；未提供时，文章沿用其发布时间。没有 `updated` 的非文章笔记不会进入订阅源。

Minimal Home 会在文章标题下显示 `subtitle`，然后使用 `description` 或编译器生成的正文摘录作为摘要。存在 `author` 时，摘要页脚会列出作者。`author` 和 `categories` 会与 `tags` 一起进入 Home 的 Topics 区域。条目可以是普通字符串，也可以是指向公开笔记的 Wiki 链接：

```yaml
---
subtitle: Dreamers among programmers
author:
  - "[[People/Ada Lovelace|Ada]]"
  - Editorial team
categories:
  - "[[AI]]"
  - "[[Machine Learning|ML]]"
---
```

Wiki 链接条目必须使用 YAML 双引号字符串。可见标签优先使用 `|` 后的别名，没有别名时使用目标笔记标题。Home Topics 中的每个主题标签都会打开对应的 Blog 筛选；文章摘要中带 Wiki 链接的作者还可以直接打开公开作者页面。无法解析的 Wiki 链接会产生编译器警告，但仍保留为可筛选文本，不会把 `[[...]]` 泄漏到站点中。

## 内容与导航

显式的 `content_type: post | doc | page` 优先于目录默认值。文章发布时间依次使用 `date`、`created` 和第一次 Git 提交时间。生产构建会拒绝没有确定日期的文章。在 Minimal Home 和 Blog 中，设置了 `pinned: true` 的文章排在普通文章之前，两组内部都保持时间倒序。置顶只影响卡片展示，不改变 Atom Feed 的时间顺序以及上一篇、下一篇文章序列。

Docs 导航沿用内容目录结构。`nav_order` 对同级文档排序，`nav_exclude: true` 只移除当前笔记链接，子页面仍然可以访问。所有层级都可以没有 `index.md`。公开的根 `index.md` 始终拥有 `/`，因此该笔记使用其他 `permalink` 会被拒绝。没有索引的文件夹会打开依次按 `nav_order`、标题和路径排序的第一个可见子页面。存在文章时，Minimal Home 可以不需要根索引；两者都不存在时，根路径会重定向到第一个可见顶层导航目标。Docs 没有根索引时会重定向到第一项导航。每个 Docs 页面都由服务器渲染完整文档树；JavaScript 导航只替换页面内容与上下文，保留共享外壳。Search 在 Web Worker 中构建索引。局部图谱由编译器投影；浏览器只在打开对话框后读取完整图谱。

修改编译器或适配器边界前，请阅读 [[docs/development/architecture|架构]]。
