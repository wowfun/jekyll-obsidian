---
publish: true
title: 内容发布
description: 控制发布范围，组织页面，并填写笔记属性、日期和来源信息。
---

# 内容发布

本页说明哪些内容会发布、页面如何组织，以及笔记属性和来源信息的写法。Markdown 正文语法见 [[Syntax|语法]]；主题和标签页配置见 [[Customization|自定义]]。

`website.syntax_profile` 固定 Markdown 契约，目前只接受 `ofm@1`。

## 发布默认值

`website.content.publish_by_default` 是一个目录数组，其中的路径相对于 `website.source`。每个条目会选择该目录及其后代中的 Markdown 文件。默认数组为空，因此笔记必须通过 `publish: true` 明确加入。如果除显式排除的笔记外，整个内容树都应发布，可以使用 `.`：

```yaml
website:
  content:
    publish_by_default:
      - .
```

显式 YAML 布尔值始终优先。`publish: false` 会从已选择目录中排除一篇笔记，`publish: true` 则可以加入目录范围外的一篇笔记。发布目录不会决定内容分类；已发布笔记是页面、文章还是文档，仍由 `default_type`、`directories.post`、`directories.doc` 和笔记的 `content_type` 决定。附件只有在已发布笔记、其 `image` 属性或嵌入闭包引用时才会公开。

## 内容与导航

显式的 `content_type: post | doc | page` 优先于目录默认值。文章发布时间依次使用 `date`、`published`、`created` 和第一次 Git 提交时间。生产构建会拒绝没有确定日期的文章。在 Minimal Home 和 Blog 中，设置了 `pinned: true` 的文章排在普通文章之前，两组内部都保持时间倒序。置顶只影响卡片展示，不改变 Atom Feed 的时间顺序以及上一篇、下一篇文章序列。

Docs 导航沿用内容目录结构。`nav_order` 对同级文档排序，`nav_exclude: true` 只移除当前笔记链接，子页面仍然可以访问。所有层级都可以没有 `index.md`。物理 `index.md` 不存在时，同级且文件名精确为 `README.md` 的公开笔记会成为文件夹索引。已有的 `index.md` 即使未发布也会保留该位置，此时 `README.md` 仍是普通笔记。公开的根索引始终拥有 `/`，因此该笔记使用其他 `permalink` 会被拒绝。没有公开索引的文件夹会打开依次按 `nav_order`、标题和路径排序的第一个可见子页面。

存在文章时，Minimal Home 可以不需要根索引；两者都不存在时，根路径会重定向到第一个可见顶层导航目标，或可用的自动生成作品集入口。没有栏目入口时，根路径会重定向到一篇公开笔记：优先选择未设置 `nav_exclude` 的笔记，再按显式 `nav_order` 优先、数值升序、源路径升序选择。如果全部公开笔记都设置了 `nav_exclude: true`，则按同样顺序从所有公开笔记中选择。该属性只隐藏导航链接，不隐藏已发布内容。译文标题不会改变所选笔记。重定向保留笔记原 URL，以该 URL 为规范链接，且不进入站点地图。没有公开笔记的站点仍会构建失败。

无根索引的 Minimal 站点不会把收藏页选为根路径的跳转目标。无论导航中是否显示收藏，它的首页链接和 canonical URL 都指向已选定的内容首页。如果该页缺少译文，canonical URL 会指向可索引的默认语言页面。

Docs 没有根索引时会重定向到第一项导航。

## 首页与文章摘要

Minimal Home 会先显示公开的根目录索引，再用编辑式列表显示最近六篇文章。索引默认为 `index.md`；物理 `index.md` 不存在时，才会使用同级且文件名精确为 `README.md` 的公开笔记。被选中的目录索引没有正文一级标题时，不会再通过文件名或 frontmatter 标题补出可见标题；解析后的标题仍用于元数据和导航。带图片的条目在宽屏中把 16:9 缩略图放在摘要旁边，在窄屏中放到摘要上方；没有图片的条目会占满宽度，不显示占位图。摘要还可以显示 `subtitle`、正文摘录、作者和发布日期。Blog 链接会打开 `/blog/` 中完整的倒序文章列表。

## 页面属性

编译器为发布行为保留以下笔记属性，并按封闭结构逐项校验：

- `publish`、`title`、`subtitle`、`aliases`、`tags`、`author`、`categories` 和 `description`
- `permalink`、`image` 和 `cssclasses`
- `created` 和 `updated`
- `content_type`、`date`、`date_basis`、`pinned`、`nav_order`、`nav_exclude`、`tab` 和 `tabs`
- `comments`、`github_markdown`、`related`、`source_url`、`source`、`source_title`、`published` 和 `lang`

`aliases`、`tags`、`author`、`categories`、`cssclasses` 和 `tabs` 是字符串数组，`subtitle` 是字符串。`publish`、`pinned`、`nav_exclude` 和 `comments` 使用 YAML 布尔值。`tab` 的封闭映射见 [[Customization#自定义标签页|自定义标签页]]。`github_markdown` 只接受 [[Portfolio|作品集]]中说明的 URL 或映射形式，并且只能用于作品集项目页。日期使用 ISO 8601。笔记标题依次取自 `title`、第一个一级标题和文件名。

`lang` 用于声明 `website.i18n.shared_directories` 中笔记的正文语言，不改变界面语言，详见 [[Localization#在不同语言界面中共用正文|共享正文]]。

### 自定义属性

其他顶层属性可以使用标量或一层标量列表。自定义属性名必须是经过规范化的单行文本，且不能带首尾空白。两个主题默认在标签和原文链接下方、正文上方显示展开的属性区。标签使用原始字段名，字段保留书写顺序。不支持嵌套列表或映射。

普通字符串按纯文本转义，保留换行，不执行其中的 Markdown、HTML 或 Liquid。完整且不含凭据的 HTTP(S) URL 显示为可点击链接。数字和布尔值保留其值，包括 `0` 和 `false`。原生 YAML 日期和时间戳用 ISO 8601 `<time>` 显示；加引号的日期仍是字符串。空值、空字符串和空列表分别显示为 `null`、`""` 和 `[]`。一层列表保留顺序和重复项，每项按自身类型渲染。

作者填写的属性值与正文一样完整显示。搜索和订阅源的输出限制作用于生成的索引，不会截断页面属性。

上述保留字段已有独立渲染或发布逻辑，不进入属性区；`alias`、`layout` 和 `render_with_liquid` 也会被排除。自定义字段默认公开。隐藏字段的站点配置见 [[Customization#页面属性|自定义]]；隐藏显示不会移除笔记关系。

### 链接与关联笔记

完整 Wiki 链接只有写成 YAML 双引号字符串时，才会成为普通笔记关系。它也会在属性区链接到公开目标，文本使用作者提供的别名或目标标题。无法解析的链接按作者提供的别名或目标显示为纯文本，并保留现有编译诊断。Wiki 目标跟随页面语言，普通外部 URL 保持不变。

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

### 日期

`date_basis` 是可选的作者元数据：`published` 将文章日期标为“发布”，`observed` 将其标为“首次发现”，省略时使用“发布”。它只改变日期标签，不改变日期选取和时间排序。编译器不会推导 `date_basis`，即使文章发布时间来自 Git。译文继承默认语言笔记的值，不能修改。

`updated` 可选，只有作者明确提供时才会出现在页面元数据中；编译器不会从 Git 推导更新时间。文章发布时间依次使用 `date`、`published`、`created` 和第一次 Git 提交时间。Atom 条目优先使用显式 `updated`；未提供时，文章沿用其发布时间。没有 `updated` 的非文章笔记不会进入订阅源。

### 作者与分类

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

## 来源元数据与目录标签

Obsidian Web Clipper 笔记可以保留 `published`、`source` 和用引号包围的作者双链。`published` 接受 ISO-8601 日期或日期时间；文章日期依次使用 `date`、`published`、`created`、第一次 Git 提交时间。`source` 与 `source_url` 一样接受不含凭据的 HTTP(S) URL；两者都有时，原文链接优先使用 `source_url`。这些字段不会再重复显示为自定义属性。作者双链没有公开目标时显示原有名称，并产生警告。

通过目录配置发布剪藏，无需逐篇添加发布字段：

```yaml
website:
  content:
    publish_by_default: [clippings]
    directories:
      post: [clippings]
      doc: [docs]
    directory_tags:
      clippings: [source/clippings]
```

`directory_tags` 默认为 `{}`。键是相对于内容根目录的规范目录路径，`.` 表示整个内容目录；标签会追加到该目录及其后代。嵌套规则累加并去重，不会改写磁盘上的 Markdown，也不会自行授权发布。`publish: false` 仍可排除草稿；栏目首页保留 `content_type: page`。

标签必须是非空白字符串，仅含空白的值会被拒绝。有效标签保留手写拼写，包括内部空格。

目录规则（`publish_by_default`、`directories` 和 `directory_tags`）在所有平台上都按源路径区分大小写。配置应与目录的实际拼写一致：`clippings` 不会选中 `Clippings`。大小写折叠仅用于拒绝有歧义的路径冲突，不会扩大发布规则的范围。

可选的 `source_title` 用于文章头部、归档卡片、收藏和 Markdown 导出中的原文链接标题。首尾 Unicode 空白和字节顺序标记（`U+FEFF`）会被移除；省略或移除后为空时显示 URL。这项规范化不会改写 Markdown 原稿。它是纯文本，不执行 HTML，也不替代站内笔记标题；没有原文 URL 时不会单独生成链接。

## 有时效的推荐

在内容根目录放置 `_recommendations.json`，可提供外部推荐而不增加关系图边：

```json
{ "version": 1, "items": { "a.md": [{ "path": "b.md", "expires_at": "2026-10-18T00:00:00Z" }] } }
```

路径指向默认语言目录中的公开文章，标题和链接按当前语言显示；手工 `related` 优先。不存在、私有、自身及过期目标不展示，元数据文件不发布。自动推荐需要 JavaScript，即使站点未重新构建也会到期隐藏；手工关联仍可在禁用 JavaScript 时显示。

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
