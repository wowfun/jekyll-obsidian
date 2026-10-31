---
publish: true
title: 自定义
description: 调整站点信息、视觉 token、导航和仓库链接。
updated: 2026-10-30
---

# 自定义

本页介绍站点信息、主题、导航、页脚、属性显示与输出限制。发布规则见 [[Publishing|内容发布]]，读者操作见 [[Reading|阅读与导航]]，归档功能见 [[Archives|归档与收藏]]。

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
  repository: owner/repository
  edit_branch: main
  features: {}
  contacts:
    - label: GitHub
      url: https://github.com/owner
    - label: Email
      url: mailto:hello@example.com
```

`website.source` 相对于宿主仓库根目录，默认值为 `docs`。配置优先级依次为包内默认值、宿主配置、显式命令行参数或 Pages 值。构建命令及隔离规则见 [[Integration|宿主集成]]。

## 站点信息

`title`、`description`、`lang`、`url` 和 `baseurl` 位于 YAML 根级，内容、主题和功能设置位于 `website` 下。

`title`、`description` 和 `lang` 会进入站点外壳、元数据、Atom 和无障碍标签。将 `website.repository` 设为 `owner/repository` 可以显示 Edit 链接。该值为空时，构建会检查 `GITHUB_REPOSITORY` 和本地 `origin` remote。无法识别仓库时，操作会保持隐藏。这个宿主仓库配置不会更改页脚中的 Built by Jekyll Obsidian 链接；页脚始终指向官方项目 `https://github.com/wowfun/jekyll-obsidian`。

`website.edit_branch` 决定 Edit 与其他宿主源码链接所用的分支，默认值为 `main`。

### 页脚联系方式与站点导航

配置 `website.contacts` 后，Minimal 和 Docs 的所有页面都会在页脚显示联系方式，首页最近文章区不再重复显示。每个条目都需要简短的 `label`，以及采用 `https:`、`mailto:` 或 `tel:` 的 URL。基础配置没有联系方式时，可以省略该项或使用空数组。Email、Phone、GitHub、LinkedIn、X/Twitter、Mastodon、Bluesky、Instagram、YouTube、Telegram、RSS 和 Website 链接会自动获得无障碍图标。其他服务会直接显示文本标签，因此配置保持服务中立，不需要额外的 icon 字段。

`website.footer.links` 在联系方式旁增加「站点」区块，默认值为 `[]`。空区块不占位。两种主题共用页脚；移动端纵向排列区块，下方保留主题署名、许可证和年份。

```yaml
website:
  contacts:
    - label: GitHub
      url: https://github.com/wowfun
  footer:
    links:
      - label: Jekyll Obsidian
        url: https://sinputer.top/jekyll-obsidian/
        locale_urls:
          zh-CN: https://sinputer.top/jekyll-obsidian/zh-CN/
```

每项必须包含非空 `label` 和不含用户名、密码的完整 HTTPS `url`。可选的 `locale_urls` 将语言标识映射到完整 HTTPS 地址；优先选择当前界面语言的覆盖值，没有覆盖时使用默认 `url`。链接直接使用配置地址，即使目标是同域的另一个站点，也不会追加当前站点的 `baseurl` 或语言前缀。链接在同一标签页打开。区块标题可通过 locale 消息 `footer_sites` 和 `contact` 修改；主题署名仍链接官方 GitHub 仓库。

自定义 locale 消息需要设置 `website.i18n.enabled: true`，并将消息写在根目录 `_locale.yml` 或 `_translations/<locale>/_locale.yml` 的 `messages` 下。单语言站点可只在 `locales` 中列出根配置 `lang` 指定的语言，无需创建译文副本即可修改这些标题。

最多配置 12 个链接，单行标签不超过 64 个字符，URL 不超过 2,048 个字符（含各语言覆盖地址）。首尾 Unicode 空白和字节顺序标记（`U+FEFF`）会被移除，制表符和换行不被接受。语言标识不区分大小写，例如 `zh-cn` 可匹配 `zh-CN`；仅大小写不同的重复键会报错。当前未启用语言的覆盖地址会保留但不使用，便于单语言和多语言构建共用配置。

自定义模板通过 `page.website.footer.contacts` 读取联系方式，通过 `page.website.footer.links` 读取当前语言的导航链接。前者替代了 `page.website.theme_data.contacts`；使用旧首页数据的模板需要更新。用户配置仍使用 `website.contacts`。

自定义联系方式 CSS 也需要将 `.minimal-contact` 和 `.minimal-contact__*` / `.minimal-contact--*` 改为对应的 `.site-contact` 类。旧首页容器 `.minimal-contacts` 已移除，共享 footer 的联系方式列表使用 `.site-footer__contacts`。

## 站点主题

每次构建会选择一个完整展示方案。`minimal` 在通用站点外壳中提供 Home、Blog、Docs 和自定义栏目，`docs` 则提供专注的分层手册。两个主题共享 Search、Wiki 链接预览、页面大纲、笔记关系和交互式图谱。可以用命令行覆盖配置，在不修改文件的情况下比较同一份内容：

```sh
jekyll-obsidian dev --theme docs
jekyll-obsidian build --theme minimal --url https://example.test --baseurl ""
```

生成站点位于 `.jekyll-obsidian-cache/site/`。主题标识只支持 `minimal` 和 `docs`。切换主题后，仍然发布的笔记会保留原 URL；请显式设置 `website.i18n.enabled: true`，以继续发布译文。

`website.features` 中省略的功能会继承主题默认值。可以用显式 YAML 布尔值覆盖 `search`、`tags`、`feed`、`graph`、`relations`、`previews`、`outline` 和 `reading_time`。

| 功能 | Minimal | Docs |
| --- | --- | --- |
| `search`、`previews`、`outline`、`relations`、`graph`、`reading_time` | 开启 | 开启 |
| `tags`、`feed` | 开启 | 关闭 |

独立的 `i18n` 和 `comments` 配置在已提供但省略 `enabled` 时，使用以下默认值：

| 设置 | Minimal | Docs |
| --- | --- | --- |
| `website.i18n` | 关闭 | 开启 |
| `website.comments` | 开启 | 关闭 |

未提供相应配置时，该功能关闭。显式设置 `enabled: true` 或 `enabled: false` 可覆盖主题默认值。

将任意共享功能设为 YAML 布尔值 `false` 即可移除。例如：

```yaml
website:
  features:
    graph: false
    previews: false
```

### 阅读时长

阅读时长的显示条件和计算方式见 [[Reading#阅读时长|阅读与导航]]。

全站隐藏提示：

```yaml
website:
  features:
    reading_time: false
```

配置语言消息 `reading_time` 时，必须且只能包含一个 `{minutes}` 占位符，不允许其他花括号或空白消息；中文示例为 `约 {minutes} 分钟阅读`。省略时使用英文默认文案，即使界面采用其他语言，也会标记为 `lang="en" dir="ltr"`。自定义模板可读取整数 `page.website.reading_time_minutes`，没有可计数文字时为 0。关闭 `reading_time` 只隐藏内置提示，仍会计算该值，以保持自定义模板的数据契约。

只有 `website.i18n.enabled` 为 true 时才会加载 locale 消息。单语言站点也可启用，例如在配置根层级设置 `lang: zh-CN`，并设置 `website.i18n: {enabled: true, locales: [zh-CN]}`，再在根 `_locale.yml` 中设置 `name: 简体中文` 和 `messages.reading_time`，不需要建立翻译副本。关闭 i18n 时，仅设置 `lang` 不会选择或自定义该文案，阅读时长提示使用英文。

## Minimal 导航

Minimal 默认提供 Home、Blog、Docs 和 Portfolio，顺序分别为 `0`、`10`、`20` 和 `30`。内容树中没有公开文章或文档时，Blog 与 Docs 会自动消失。Portfolio 默认使用相对于内容根目录的 `portfolio` 文件夹；其中存在至少一个可见的已发布项目时才会显示。空文件夹或只有未发布内容的文件夹不会增加标签页。可以在 `website.navigation` 中覆盖内置标签、顺序、可见性或

作品集的目录发现、介绍页、卡片排序及 GitHub 正文导入见 [[Portfolio|作品集]]。

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

Minimal 的 `tab.layout: archive` 可将标签页改为分页归档；默认值为 `collection`。成员范围、排序及共享配置见 [[Archives#归档标签页|归档标签页]]。

## 颜色与字体

两个主题共享一小组 CSS 自定义属性。浅色模式使用暖色纸张与表面色，深色模式使用中性黑灰色。蓝色标记链接与焦点，陶土色标记关系与次级注释。

正文和控件使用平台无衬线字体，系统已安装时会优先使用 Noto Sans CJK 或思源黑体。代码使用平台等宽字体。站点不会下载 Web Font，因此具体字形取决于读者操作系统，字号与间距仍保持一致。

请在自己的样式表中覆盖 token，不要编辑带 hash 的构建输出。浅色与深色配色中的文本和焦点对比度都应达到 WCAG AA。

## 页面属性

通过 `website.properties.hidden` 可以从显示投影中隐藏指定的自定义字段。默认值为空列表，不影响笔记关系的发现。上述保留字段已有独立渲染或发布逻辑，不进入属性区；`alias`、`layout` 和 `render_with_liquid` 也会被排除。自定义字段默认公开；编译器提供独立的类型化显示数据，不把原始属性混入 Jekyll 页面控制字段。

主题通过 `page.website.display_properties` 读取类型化字段数组。独立的 `site.website.properties` 映射保存站点级显示配置，包括 `hidden`。

```yaml
website:
  properties:
    hidden: [first_seen, internal_id]
```

隐藏列表必须使用不重复的合法属性名。该设置对整个站点生效，不支持单页显示覆盖。没有可见自定义字段的页面不生成属性区。`source_url` 仍作为标签下方独立的可点击原文链接显示。

属性类型、日期、作者、来源与关联笔记的写法见 [[Publishing#页面属性|内容发布]]。

## 输出数量限制

大型站点可以限制生成索引的大小，同时保留全部公开页面。每种语言分别应用这些配置。默认使用摘要搜索、不限条数的订阅源，以及 Minimal 首页的六篇最新文章。

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

`website.search.mode` 支持 `summary`（默认）和 `full`。摘要模式使用现有页面预览文本，由正整数 `excerpt_length` 限制长度，默认 240。需要匹配正文中的词句时，可显式选择 `full`。两种模式均最多索引 5,000 篇笔记，数据大小不超过 8 MiB。超出剩余容量的笔记不会进入搜索；构建时报告索引数量，搜索弹窗也会说明覆盖不完整。标题最多索引 512 个字符；别名和标签分别最多 32 个，每个最多 128 个字符。公开页面不受影响。

可选正整数 `max_entries` 可以降低 5,000 篇的上限。笔记按发布日期从新到旧排序，未提供发布日期时采用更新时间，同时间按笔记 ID 稳定排序。`content_types` 可选择 `page`、`post`、`doc`，默认空数组包含全部类型。Worker 最多索引 200,000 个字段词项，单字段最多 10,000 个；达到上限时会提示覆盖不完整。大型集合可缩小类型范围或使用摘要模式。

`website.feed.max_entries` 用正整数限制现有排序下的订阅条目数。`website.home.recent_posts_limit` 为非负整数，设为零时隐藏自动生成的最新文章列表，保留手写首页正文。上述限制不会移除页面、归档、Markdown 下载或 sitemap 条目。

## 其他功能配置

- [[Archives|归档与收藏]]：首页布局、分页、日期分组、筛选、导出与收藏开关。
- [[Comments|评论]]：GitHub Discussions 与 Giscus 配置。
- [[Analytics|流量统计]]：Cloudflare 或 Google Analytics 配置。
- [[Localization|本地化]]：语言列表、翻译文件、界面消息与标签名称。
