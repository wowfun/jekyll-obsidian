---
publish: true
title: 自定义
description: 调整站点信息、视觉 token、导航和仓库链接。
updated: 2026-10-21
---

# 自定义

两个主题的顶栏操作均使用图标，涵盖搜索、语言选择和明暗切换。可访问名称与悬停提示说明各项操作；搜索保留 Ctrl/⌘ K 快捷键。重复的栏目标题和描述自动省略，语言菜单宽度适应选项文字。按日归档默认只展开当前页最新一天；筛选和翻页保留手动开合状态，刷新后重置。这些显示默认行为无需额外开关；归档首页、分页和浏览器本地收藏仍由站点显式选择。

两个主题的索引、文章、文档、归档和收藏页均提供**回到顶部**箭头。只有向下滚动超过一屏后，按钮才会出现在右下角；回到首屏范围内时隐藏。移动端按钮位于底部工具栏上方，并避让翻译提示。按钮显示时，其键盘导航顺序紧随跳至正文链接。激活按钮会将焦点移至正文并平滑回顶；系统偏好减少动态效果时立即回顶，URL 保持不变。此默认行为无需配置，禁用 JavaScript 和打印时按钮均保持隐藏。可通过语言消息 `back_to_top` 翻译其无障碍名称和悬停提示。

将按钮安排在键盘导航顺序前端，是为了在恢复已滚动页面时快速访问；再按 Tab 时会进入顶栏。强制颜色模式下，按钮及其正文焦点目标均保留可见轮廓。

直接编辑 `.github/jekyll-obsidian.yml` 即可配置站点。gem 提供默认值，宿主只需填写要覆盖的设置：

```yaml
title: My Site
description: Built from Markdown
lang: en
url: ""
baseurl: ""

website:
  source: docs
  theme: minimal
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
  html:
    slides/runtime: /presentations/runtime/
  contacts:
    - label: GitHub
      url: https://github.com/owner
    - label: Email
      url: mailto:hello@example.com
```

`website.source` 相对于宿主仓库根目录，默认值为 `docs`。可以使用 `website/docs` 或其他仓库内目录。本项目自己的文档目录为 `website/jekyll-obsidian-docs`，不会随 gem 安装。

配置优先级依次为包内默认值、`.github/jekyll-obsidian.yml`、显式命令行参数或 Pages 值。所有宿主配置都可以直接编辑。`jekyll-obsidian build` 会在专属缓存中创建隔离的 Jekyll source，并将输出写入 `.jekyll-obsidian-cache/site/`。请使用 `jekyll-obsidian` 命令，宿主已有的 Jekyll `_config.yml` 和插件不会参与构建。

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

## 独立 HTML Slides

`website.html` 用于显式发布不经过主题渲染的可信 HTML。把内容目录中的相对源路径映射到一个根相对公开路由：

```yaml
website:
  html:
    slides/runtime: /presentations/runtime/
    slides/status.html: /status.html
```

文件映射要求源文件名精确以 `.html` 结尾，目标也是 `.html` 文件路由，并且只发布该文件。目录映射要求目录中存在精确的 `index.html`，目标以 `/` 结尾，并保留普通 bundle 文件的相对结构。因此 bundle 可以包含 CSS、JavaScript、字体、图片和应用自己的数据文件。Markdown 和 `_locale.yml` 等编译器语言清单仍按普通编译规则处理，不会随 bundle 一起复制。

源必须是经过 NFC 规范化的内容目录相对 POSIX 路径，且多个源不能重叠。目标不能包含 `baseurl`、query、fragment、编码后的路径分隔符，也不能使用 `/`、`/assets/website/` 或 `/assets/vault/`。HTML 与 Markdown 页面、目录首页、语言路由、系统产物和宿主 Jekyll 输出发生目标冲突时，构建会在写入前失败。

编译器会逐字节复制这些文件，不套主题、不执行 Liquid、不注入元数据或 CSP，也不改写相对 URL。Raw HTML 中写死的根相对 URL 必须由作者自行包含部署 `baseurl`；相对 URL 通常更便于迁移。普通 Markdown 链接或 `[[slides/runtime/index.html|打开 Slides]]` 会解析到配置路由。主题页通过 Markdown embed 或 `image` 属性引用非 HTML bundle 媒体时，会复用其映射路由，不再生成第二份 vault asset；`![[...html]]` 仍会被拒绝，因为 raw HTML 不能嵌入主题页面。

HTML 映射本身就是发布授权，不受 `website.content.publish_by_default` 控制。Raw 文档由所有语言共享，不会进入导航、Search、Graph、Feed、sitemap、Markdown 资源或自动语言副本；请从公开 Markdown 页面手动链接。它们会以可信同源代码运行，因此应把整个映射目录当作公开可执行内容审查。Manifest 授权的是路径，而不是响应 MIME；使用少见扩展名时，应确认部署服务器返回预期的 `Content-Type`，并禁用不安全的内容嗅探。本仓库提供了可直接查看的 [[slides/jekyll-obsidian/index.html|五分钟 Jekyll Obsidian Slide]]。

## 站点信息

`title`、`description` 和 `lang` 会进入站点外壳、元数据、Atom 和无障碍标签。将 `website.repository` 设为 `owner/repository` 可以显示 Edit 链接。该值为空时，构建会检查 `GITHUB_REPOSITORY` 和本地 `origin` remote。无法识别仓库时，操作会保持隐藏。这个宿主仓库配置不会更改页脚中的 Built by Jekyll Obsidian 链接；页脚始终指向官方项目 `https://github.com/wowfun/jekyll-obsidian`。

Minimal Home 会先显示公开的根目录索引，再用编辑式列表显示最近六篇文章。索引默认为 `index.md`；物理 `index.md` 不存在时，才会使用同级且文件名精确为 `README.md` 的公开笔记。被选中的目录索引没有正文一级标题时，不会再通过文件名或 frontmatter 标题补出可见标题；解析后的标题仍用于元数据和导航。带图片的条目在宽屏中把 16:9 缩略图放在摘要旁边，在窄屏中放到摘要上方；没有图片的条目会占满宽度，不显示占位图。摘要还可以显示 `subtitle`、正文摘录、作者和发布日期。Blog 链接会打开 `/blog/` 中完整的倒序文章列表。

配置 `website.contacts` 后，可以在最近文章区之后显示联系方式。每个条目都需要简短的 `label`，以及采用 `https:`、`mailto:` 或 `tel:` 的 URL。基础配置没有联系方式时，可以省略该项或使用空数组。Email、Phone、GitHub、LinkedIn、X/Twitter、Mastodon、Bluesky、Instagram、YouTube、Telegram、RSS 和 Website 链接会自动获得无障碍图标。其他服务会直接显示文本标签，因此配置保持服务中立，不需要额外的 icon 字段。

## 站点主题

每次构建会选择一个完整展示方案。`minimal` 在通用站点外壳中提供 Home、Blog、Docs 和自定义栏目，`docs` 则提供专注的分层手册。两个主题共享 Search、Wiki 链接预览、页面大纲、笔记关系和交互式图谱。可以用命令行覆盖配置，在不修改文件的情况下比较同一份内容：

```sh
jekyll-obsidian dev --theme docs
jekyll-obsidian build --theme minimal --url https://example.test --baseurl ""
```

生成站点位于 `.jekyll-obsidian-cache/site/`。主题标识只支持 `minimal` 和 `docs`。

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
```

作品集路径相对于 `website.source`；显式路径会取代默认的 `portfolio`。该路径下的已发布 Markdown 后代统一变成作品集页面，因此其中显式设置的 `content_type` 必须为 `page`。公开的目录索引会在项目网格上方保留自定义介绍。可以使用 `<path>/index.md`；没有物理索引时，也可以使用 `<path>/README.md`。选中的索引未发布时，编译器会在该路由生成作品集索引。索引本身不算项目。设置了 `pinned: true` 的项目排在最前；置顶组和普通组内部再依次按 `nav_order`、标题和路径排序。项目设置 `nav_exclude: true` 后不会显示卡片；设置 `website.navigation.portfolio.visible: false` 只会隐藏标签页，作品集索引和项目页面仍然公开。

项目卡片使用 `image`、标题和 `description`；未设置描述时，会回退到正文预览。本地 GIF、WebP、AVIF 与 APNG 文件会逐字节复制并通过 `<img>` 显示，从而保留动画。编译器不会转码或生成缩略图。

项目可以通过 `github_markdown` 将本地正文替换为公开的 GitHub Markdown 文件。本地项目页继续管理卡片元数据和路由，解析后的远程正文则用于详情页、大纲、Search 文本、预览和 Markdown 端点。接受的 URL 与映射格式、空正文规则、分支刷新、内容上限、相对 URL、本地化和安全边界详见 [[Portfolio|作品集]]。

## 自定义标签页

Minimal 与 Docs 使用同一套自定义标签页契约。在已发布的文件夹索引上声明标签页，可以使用 `index.md`，也可以使用符合条件的 `README.md` 回退。该笔记仍是标签页的 canonical 主页，其正文显示在自动生成的成员卡片之前：

```yaml
---
publish: true
content_type: page
tab:
  id: favorites
  label: 收藏
  order: 40
  topics:
    - favorite
    - reference
---
```

`id` 必填，并且必须是 `favorites`、`team-work` 这类小写 ASCII 标识符；`home`、`blog`、`docs` 和 `portfolio` 已保留。标签默认使用本地化后的索引标题，顺序默认为 `100`。自定义标签页始终可见。其根必须是可见的 `content_type: page` 文件夹索引，且不能位于当前 Portfolio 路径内。

成员取三类来源的并集：标签页文件夹下所有已发布后代、通过 `tabs` 指定该标签页的已发布笔记，以及 `tags` 或 `categories` 与标签页任一 `topics` 匹配的已发布笔记。多个 topic 使用 OR 关系，并在 Unicode 规范化和大小写折叠后精确匹配。文件夹外的页面可在不改变路由的情况下加入：

```yaml
---
publish: true
tabs:
  - favorites
---
```

成员关系只用于额外展示：文章仍在 Blog 下激活，文档仍在 Docs 下激活，作品集页面仍在 Portfolio 下激活。只有普通页面后代会激活自定义标签页；存在嵌套根时，以最深层根为准。卡片会去重，并依次按 `pinned`、`nav_order`、本地化标题和源路径排序。`nav_exclude: true` 会移除文件夹或 topic 匹配结果，且不能与 `tabs` 同时使用。topic 没有匹配项是有效状态，此时只显示索引正文。

ID、标签或目标重复，`tabs` 引用未知标签页，根无效或与保留项冲突，都会让构建失败。即使一个页面加入多个标签页，它也只保留一个 canonical URL；自定义标签页不会创建重定向，也不会在 Search、订阅源或 sitemap 中复制页面。

在 Minimal 中，设置 `tab.layout: archive` 可让标签页使用与首页归档相同的分页列表、时间归档和分面筛选。默认布局为 `collection`。归档标签页沿用 `website.blog` 中的分页大小、时区、日期分组、时间归档粒度及来源/主题前缀；计数、筛选、分页和 Markdown 导出均限定在当前标签页成员内。成员按日期倒序排列，无日期条目置于末尾，`pinned` 和 `nav_order` 不改变归档时间顺序。索引正文仍显示在筛选器上方。Docs 仅支持默认的 collection 布局。译文继承默认语言索引的 `tab.layout`，仍可覆盖 `tab.label`。

桌面标题栏放不下的标签页会进入无障碍 More 菜单。移动端 Browse 面板和 Search 对话框的快速导航会复用同一组有序目标和激活状态。Search 会按配置标签筛选快速链接，同时查询笔记正文。没有 JavaScript 时，标题栏链接仍然可见，并会自然换行。从 Minimal 打开 Docs 时会保留 Minimal 站点外壳，同时加入手册目录、页面大纲及上一篇或下一篇链接。

## 有时效的推荐

在内容根目录放置 `_recommendations.json`，可提供外部推荐而不增加关系图边：

```json
{ "version": 1, "items": { "a.md": [{ "path": "b.md", "expires_at": "2026-10-18T00:00:00Z" }] } }
```

路径指向默认语言目录中的公开文章，标题和链接按当前语言显示；手工 `related` 优先。不存在、私有、自身及过期目标不展示，元数据文件不发布。自动推荐需要 JavaScript，即使站点未重新构建也会到期隐藏；手工关联仍可在禁用 JavaScript 时显示。

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

一个站点只能启用一家服务。本地开发和重定向页面不会载入统计客户端。服务配置、Docs 导航跟踪、内容安全策略来源、隐私差异和问题排查详见 [[Analytics|流量统计]]。

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

Minimal 需要在 `i18n` 下添加 `enabled: true`；Docs 可以通过 `enabled: false` 暂停已经配置的语言方案。默认语言保留在普通内容树中。其他语言的笔记放在 `_translations/<locale>/` 下相同的相对路径中。译文继承公开默认语言笔记的发布状态；设置 `publish: false` 后，该语言 URL 会显示现有的默认语言回退内容。每个配置的语言都需要在其根目录提供 `_locale.yml`。`name` 为必填项；`hreflang`、`dir` 和封闭的 `messages` 目录可选。译文缺失或停用不会让构建失败。对应本地化 URL 会在默认语言正文上短暂显示提示，并从搜索引擎索引与站点地图中排除。

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

## 输出数量限制

大型站点可以限制生成索引的大小，同时保留全部公开页面。每种语言分别应用这些配置。省略时维持全文搜索、不限条数的订阅源，以及 Minimal 首页的六篇最新文章。

```yaml
website:
  search:
    mode: summary
    max_entries: 3000
    excerpt_length: 240
    content_types: [post]
  feed:
    max_entries: 100
  home:
    recent_posts_limit: 0
```

`website.search.mode` 支持 `full` 和 `summary`。摘要模式使用现有页面预览文本，由正整数 `excerpt_length` 限制长度，默认 240。可选正整数 `max_entries` 按发布日期排序，未提供发布日期时采用更新时间，同时间按笔记 ID 稳定排序。`content_types` 可选择 `page`、`post`、`doc`，默认空数组包含全部类型。

`website.feed.max_entries` 用正整数限制现有排序下的订阅条目数。`website.home.recent_posts_limit` 为非负整数，设为零时隐藏自动生成的最新文章列表，保留手写首页正文。上述限制不会移除页面、归档、Markdown 下载或 sitemap 条目。

## 页面属性

编译器为发布行为保留以下笔记属性，并按封闭结构逐项校验：

- `publish`、`title`、`subtitle`、`aliases`、`tags`、`author`、`categories` 和 `description`
- `permalink`、`image` 和 `cssclasses`
- `created` 和 `updated`
- `content_type`、`date`、`date_basis`、`pinned`、`nav_order`、`nav_exclude`、`tab` 和 `tabs`
- `comments`、`github_markdown`、`related` 和 `source_url`

其他顶层属性可以使用标量或一层标量列表。自定义属性名必须是经过规范化的单行文本，且不能带首尾空白。两个主题默认在标签和原文链接下方、正文上方显示展开的属性区。标签使用原始字段名，字段保留书写顺序。不支持嵌套列表或映射。

普通字符串按纯文本转义，保留换行，不执行其中的 Markdown、HTML 或 Liquid。完整且不含凭据的 HTTP(S) URL 显示为可点击链接。数字和布尔值保留其值，包括 `0` 和 `false`。原生 YAML 日期和时间戳用 ISO 8601 `<time>` 显示；加引号的日期仍是字符串。空值、空字符串和空列表分别显示为 `null`、`""` 和 `[]`。一层列表保留顺序和重复项，每项按自身类型渲染。

作者填写的属性值与正文一样完整显示。搜索和订阅源的输出限制作用于生成的索引，不会截断页面属性。

完整 Wiki 链接只有写成 YAML 双引号字符串时，才会成为普通笔记关系。它也会在属性区链接到公开目标，文本使用作者提供的别名或目标标题。无法解析的链接按作者提供的别名或目标显示为纯文本，并保留现有编译诊断。Wiki 目标跟随页面语言，普通外部 URL 保持不变。

通过 `website.properties.hidden` 可以从显示投影中隐藏指定的自定义字段。默认值为空列表，不影响笔记关系的发现。上述保留字段已有独立渲染或发布逻辑，不进入属性区；`alias`、`layout` 和 `render_with_liquid` 也会被排除。自定义字段默认公开；编译器提供独立的类型化显示数据，不把原始属性混入 Jekyll 页面控制字段。

`date_basis` 是可选的作者元数据：`published` 将文章日期标为“发布”，`observed` 将其标为“首次发现”，省略时使用“发布”。它只改变日期标签，不改变日期选取和时间排序。编译器不会推导 `date_basis`，即使文章发布时间来自 Git。译文继承默认语言笔记的值，不能修改。

主题通过 `page.website.display_properties` 读取类型化字段数组。独立的 `site.website.properties` 映射保存站点级显示配置，包括 `hidden`。

```yaml
website:
  properties:
    hidden: [first_seen, internal_id]
```

隐藏列表必须使用不重复的合法属性名。该设置对整个站点生效，不支持单页显示覆盖。没有可见自定义字段的页面不生成属性区。`source_url` 仍作为标签下方独立的可点击原文链接显示。

被忽略的 Jekyll 控制字段 `alias`、`layout` 和 `render_with_liquid` 不生成笔记关系，即使其值看起来是 Wiki 链接。

```yaml
project: "[[portfolio/fauni-search|Fauni Search]]"
references:
  - background
  - "[[docs/development/architecture]]"
related:
  - "[[blog/launch-notes]]"
  - "[[docs/Getting Started|从这里开始]]"
```

`related` 是用于精选列表的专用字段。它只接受双引号 Wiki 链接列表，保留书写顺序并去除重复目标，在页面底部以「最新文章」相同的卡片样式显示。生产构建会拒绝断开的相关文章链接。其他自定义属性链接是否进入直接链接、反向链接和关系图，不受属性区显示设置影响：隐藏字段的显示不会移除它的笔记关系。

`aliases`、`tags`、`author`、`categories`、`cssclasses` 和 `tabs` 是字符串数组，`subtitle` 是字符串。`publish`、`pinned`、`nav_exclude` 和 `comments` 使用 YAML 布尔值。`tab` 是前文说明的封闭映射。`github_markdown` 只接受 [[Portfolio|作品集]]中说明的 URL 或映射形式，并且只能用于作品集项目页。日期使用 ISO 8601。笔记标题依次取自 `title`、第一个一级标题和文件名。

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

Wiki 链接条目必须使用 YAML 双引号字符串。可见标签优先使用 `|` 后的别名，没有别名时使用目标笔记标题。Home Topics 中的每个主题标签都会打开对应的 Blog 筛选；文章摘要中带 Wiki 链接的作者还可以直接打开公开作者页面。在 Minimal Blog 中，标签与分类会一起显示在归档列表的日期下方，并在文章页的发布日期右侧显示为筛选胶囊；`tags` 与 `categories` 中的同名项只显示一次。无法解析的 Wiki 链接会产生编译器警告，但仍保留为可筛选文本，不会把 `[[...]]` 泄漏到站点中。

作者和分类 Wiki 链接现在与正文链接、相关文章卡片、自定义属性链接一样，对片段进行 UTF-8 百分号编码。例如，标题片段 `#你好-世界` 在生成的 URL 中显示为 `#%E4%BD%A0%E5%A5%BD-%E4%B8%96%E7%95%8C`。标题 ID 和目标保持不变；已有的未编码片段链接仍指向同一标题。

## 内容与导航

显式的 `content_type: post | doc | page` 优先于目录默认值。文章发布时间依次使用 `date`、`created` 和第一次 Git 提交时间。生产构建会拒绝没有确定日期的文章。在 Minimal Home 和 Blog 中，设置了 `pinned: true` 的文章排在普通文章之前，两组内部都保持时间倒序。置顶只影响卡片展示，不改变 Atom Feed 的时间顺序以及上一篇、下一篇文章序列。

Docs 导航沿用内容目录结构。`nav_order` 对同级文档排序，`nav_exclude: true` 只移除当前笔记链接，子页面仍然可以访问。所有层级都可以没有 `index.md`。物理 `index.md` 不存在时，同级且文件名精确为 `README.md` 的公开笔记会成为文件夹索引。已有的 `index.md` 即使未发布也会保留该位置，此时 `README.md` 仍是普通笔记。公开的根索引始终拥有 `/`，因此该笔记使用其他 `permalink` 会被拒绝。没有公开索引的文件夹会打开依次按 `nav_order`、标题和路径排序的第一个可见子页面。存在文章时，Minimal Home 可以不需要根索引；两者都不存在时，根路径会重定向到第一个可见顶层导航目标。Docs 没有根索引时会重定向到第一项导航。每个 Docs 页面都由服务器渲染完整文档树；JavaScript 导航只替换页面内容与上下文，保留共享外壳。Search 在 Web Worker 中构建索引。局部图谱由编译器投影；浏览器只在打开对话框后读取完整图谱。

修改编译器或适配器边界前，请阅读 [[docs/development/architecture|架构]]。


使用 `website.home.layout: archive` 将倒序归档设为首页。
`website.blog.page_size` 开启分页（1–100，默认完整归档）。
`website.blog.facets` 将查询参数映射到标签前缀，例如
`{source: "source/", topic: "topics/"}`。组内为 OR，组间及时间范围为 AND。
查询参数 `page`、`year`、`month` 和 `day` 保留给分页与时间筛选使用。
`website.blog.utc_offset: "+08:00"` 设置归档日期显示偏移。
设置 `website.blog.timeline_granularity: day`，可在各年份下按倒序列出 `MM-DD` 日期、每日条数及 `?day=YYYY-MM-DD` 筛选链接，默认为 `month`。
日期边界遵循 `utc_offset`；日期筛选可与来源、主题组合，切换日期会回到第一页，再次选择同一天则取消日期筛选。
首屏由 HTML 输出，其他页按需加载带版本指纹的卡片分块和筛选位图。
加载失败保留上次成功页面并提供重试；未知标签匹配空结果。
每个条目显示 description；未设置时显示笔记预览。
分页提供最多五个邻近页码链接及数字输入跳转，两者都会保留当前筛选条件。Minimal 与 Docs 的顶栏操作使用图标、本地化无障碍名称及悬停提示；语言菜单保留完整语言名，阅读和配色状态仍有可见反馈。

顶栏的**平铺阅读**开关将当前页正文直接展开，随翻页和筛选更新，
并在刷新和切换语言后保留选择。开启后只加载距离视口不超过 400 像素的条目，
同时最多发出四个请求。
单篇加载失败时保留条目并提供重试；关闭开关恢复紧凑列表。
阅读、分页和导出共享最多四个网络请求的限制。正文经清理后保存在有上限的缓存中，
返回已访问条目时可复用；重试一篇不会重启其他正文加载。相对链接按重定向后的最终网址解析。

分页归档顶栏的**导出**按钮将所有匹配条目合并为当前语言的 UTF-8 Markdown 文件。
每次打开时复制首页当前来源和主题选择，面板内可独立修改，不改变首页筛选或 URL。
开始、结束日期均必填，包含起止两天，日期边界遵循 `utc_offset`。
`website.blog.export_max_days` 为正整数，默认 `7`。首页已选具体一天时默认该天；
否则以当前筛选下最新条目的日期为结束日，向前覆盖配置的天数。
无日期条目不参与导出，日期之间允许没有内容。
文件包含站点、筛选条件、条目数、文章元数据及完整的已发布 Markdown，媒体保留链接，
顺序沿用跨全部分页的归档顺序。同时最多加载四个资源；取消或关闭面板停止导出。
任一正文载入失败都不会下载不完整文件，重试复用本次任务已经取得的正文。
若面板打开期间站点更新，下载前会刷新选择。请核对新的筛选条件和条数，再次点击**下载 Markdown**。
进度仅计入成功载入的正文。连续修改日期时会短暂等待输入结束再计算，修改后立即禁用下载。
成功正文还可用于重复下载，直到筛选变化或面板关闭。文件使用 Blob 分段组装，
不再生成整份文档的大字符串。每次最多导出 5000 条，解压后的 Markdown 响应总量
最多 64 MiB，包含正在传输的正文；超限会停止任务并提示缩小范围，不下载残缺文件。
失败传输在重试前释放其占用的额度。加载条目信息时显示不定进度。
匹配条数超过上限时仍显示准确数量，但只收集前 5000 个匹配序号。
字节额度衡量的是响应数据，不是浏览器堆内存：解码后的字符串、保留的正文和
下载 Blob 还会占用内存。关闭面板即可释放保留的正文。

语言清单可用 `tag_labels` 提供完整稳定标签的显示名称，
用扁平化 `tag_aliases` 保留旧标签查询。语言切换保留筛选状态。

`source_url`: an absolute HTTP(S) URL without credentials; shown as a clickable original source link.

## 按日分组与本地收藏

设置 `website.blog.ledger_group_by: day`，可按日期折叠条目，并移除每条左侧的日期栏。标题显示本地化月日、星期及当前页本组条数，非当前年份补充年份。日期采用 `website.blog.utc_offset`，不受浏览器时区影响。默认只展开当前结果中最新的一天，各日期可独立开合；手动选择在当前页面的筛选、分页和历史前进后退中保留，刷新后重置。原生折叠控件在关闭 JavaScript 时仍可操作。平铺阅读按需加载已展开日期中的可见条目，收起时保留已加载正文。归档栏目页和收藏页共用此行为。默认仍按 `year` 分组，静态首屏与分页使用相同的日期标题。

日期组始终按时间倒序排列，置顶条目在所属日期内优先显示。参考年份取自构建请求中的显式参考时间，并按配置时区换算；静态标题会保留该参考年份，直到下次构建。

可通过本地化消息 `ledger_date`、`ledger_date_year`、`ledger_months`、`ledger_weekdays`、`ledger_entry` 和 `ledger_entries` 自定义日期标题。月份和星期名称以竖线分隔，必须分别包含 12 和 7 个非空名称，从一月和星期日开始。日期格式必须包含 `{month}` 和 `{day}`；`ledger_date_year` 还必须包含 `{year}`，`ledger_date` 则可选。条数格式必须包含 `{count}`。未知或不成对的占位符、无效名称列表会产生本地化诊断并停止编译。

minimal 主题支持 `website.features.favorites: true`（默认为 `false`），在 ledger 条目和文章操作区增加收藏按钮，并在导航中增加 `/favorites/` 收藏页。`website.navigation.favorites` 支持 label、order、visible 设置；启用功能时该路由由主题保留。

收藏保存在当前浏览器中，按站点 base URL 隔离，中英文页面共用收藏状态。清除浏览器存储会删除收藏；不同来源、浏览器和设备分别保存。快照包括标题、摘要、日期、来源、主题及链接，不保存文章正文。在站条目展示当前语言，下架条目保留已保存语言的快照和原文链接。网络失败时显示快照并提供重试，不误判下架；存储失败时保留原收藏并提示原因。

保存需要新版浏览器的 Web Locks，并通过 HTTPS 或 localhost 访问。各标签页及语言版本共用站点锁，收藏写入或快照更新不会覆盖其他标签页的改动；按钮在写入完成后显示成功。存储被禁用、空间不足和浏览器不支持会分别提示。损坏的条目或语言快照会单独隔离，可用收藏仍能查看；修复部分损坏的集合前，会将原始数据备份到 `website:favorites:v1:<scope>:recovery:current` localStorage 键。整个集合无法解析或存储版本未知时，保留原始数据。

恢复备份面板支持下载原始数据、补回可用收藏（不替换更新的快照），以及明确清理备份。每站最多自动保留一份新备份；出现不同的损坏数据时，需要先下载并清理现有备份，再进行修复，避免备份无限增长。已有的旧备份也能在同一面板中管理。

收藏页按文章日期倒序、同日按文章 ID 排序，每页 50 条。来源、主题和时间线计数只包括收藏条目。平铺阅读按需加载仍在站的正文，下架条目保留摘要。导出入口位于普通索引页。独立文章 ID 索引只定位涉及的卡片分块，避免加载所有条目。

即使未开启索引分页，启用收藏也会为每种语言生成 manifest、文章 ID 索引、部署描述文件及卡片分块。筛选位图文件仅在开启分页时生成。索引始终按日期排序，不受首页置顶文章影响。禁用 JavaScript 时，收藏页会提示启用后读取浏览器中的收藏。

返回普通索引页时，若无法检查当前部署，仍可使用已加载版本进行筛选和分页，并通过重试检查更新。收藏页继续使用快照，直到部署验证成功。平铺阅读开启时显示勾选标记，悬停提示包含开关状态；搜索提示包含 Ctrl/⌘ K 快捷键。

筛选和分页复用已加载的收藏集合及所需筛选位图。重试和浏览器恢复页面时，从当前页面重新定位索引版本，避免重复请求旧部署的路径。同一页刷新会保留正在输入的页码；在新标签页打开来源或主题链接，也会保留已选筛选条件。

### 归档筛选的可见性

Minimal 归档首页可设置 `website.home.hide_tab_sources: true`（默认 false），要求 `website.blog.facets` 中包含 `source` 筛选组；在 `website.home.layout: recent` 或 Docs 主题中启用时，编译器会给出警告。该设置根据实际归档 tab 的来源标签排除首页来源及条目。“来源”标题下方的按钮可一并展开，计数、日期导航、分页与 Markdown 导出均遵循当前范围。独立栏目、搜索、文章页与收藏保留完整内容。

该选项要求 `website.blog.facets` 中包含名为 `source` 的筛选项；其前缀可配置，通常为 `source/`。缺少该筛选项时构建会报错。仅解析别名后匹配此前缀的 `tab.topics` 值用于排除来源。仅按主题划分的栏目、未明确声明来源标签的栏目，或拼写错误且没有匹配文章的来源标签，都不会排除内容；系统不会从栏目名称或成员推断来源。首页范围未变化时，请检查栏目声明的来源标签 ID。

语言目录的 `_locale.yml` 支持 `hidden_tags`，使用完整标签 ID 的唯一列表，例如 `topics/research`。别名通过 `tag_aliases` 解析后去重，各语言必须表示同一个规范标签集合。单语言站点也可在内容根目录的 `_locale.yml` 中设置 `hidden_tags`、`tag_aliases` 和 `tag_labels`，无需开启 i18n；两种模式均拒绝未知清单键。隐藏标签仍显示在文章和收藏条目中，但默认不出现在归档、栏目、收藏和导出的候选项中。筛选标题下方的按钮仅展开本组的隐藏选项：“主题”使用“显示隐藏主题”，其他筛选项使用“显示隐藏标签”。“来源”可同时提供标签展开与独立栏目展开按钮，两者分别控制。收起后仍保留已选隐藏标签，便于取消筛选。

URL 使用 `include_tabs=1` 和可重复的 `show_hidden` 参数保存展开状态，后者取值为筛选组名称，例如 `show_hidden=source&show_hidden=topic`。明确选择独立栏目来源的链接自动展开。导出弹窗继承各组状态，内部调整独立于页面。未明确选择来源时，导出标题使用“全部（不含独立栏目来源）”说明默认范围，不逐一列出所有剩余来源。静态 HTML 首屏始终使用默认范围；JavaScript 加载后才应用 URL 筛选并显示已选隐藏标签。无 JavaScript 时，条目及计数保持默认范围，不显示展开按钮。文案键为 `include_tab_sources`、`hide_tab_sources`、`show_hidden_topics`、`hide_hidden_topics`、`show_hidden_tags`、`hide_hidden_tags`、`all_without_tab_sources`。
