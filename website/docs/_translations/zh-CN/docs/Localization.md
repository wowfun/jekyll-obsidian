---
publish: true
title: 本地化
description: 使用语言覆盖层发布本地化导航、搜索与 SEO 元数据。
---

# 本地化

Minimal 和 Docs 主题均支持静态本地化。一次构建会发布所有已配置语言，因此本地化站点不需要再次调用 Jekyll，也不依赖翻译服务或浏览器语言检测。

## 启用本地化

未配置 `website.i18n` 时，所有主题都关闭本地化。存在该映射但省略 `enabled` 时，当前主题采用以下默认值：

| 主题 | 存在 `website.i18n` 时的默认值 |
| --- | --- |
| `minimal` | 关闭 |
| `docs` | 开启 |

顶层 `lang` 是默认语言，必须出现在 `locales` 中。列表顺序同时决定语言切换器的顺序。

```yaml
lang: en

website:
  theme: docs
  i18n:
    locales:
      - en
      - zh-CN
```

Minimal 主题需要在 `i18n` 下添加 `enabled: true`。若要暂时停用已配置的 Docs 语言方案，请添加 `enabled: false`。语言标签采用类似 BCP 47 的形式，例如 `en`、`zh-CN` 或 `ar-EG`；比较时不区分大小写，重复标签会被拒绝，`assets` 是保留名称。

## 组织各语言内容

默认语言保留在普通内容树中。其他语言在 `_translations/<locale>/` 下镜像该目录结构：

```text
content/
├── _locale.yml
├── Start.md
├── guide/
│   └── Advanced.md
└── _translations/
    └── zh-CN/
        ├── _locale.yml
        ├── Start.md
        └── guide/
            └── Advanced.md
```

相对路径用于配对译文。在此示例中，`_translations/zh-CN/guide/Advanced.md` 是 `guide/Advanced.md` 的译文。如果同一路径下没有默认语言笔记，译文就是孤立译文，构建会失败。各语言根目录都不要求提供 `index.md`；它们会跳转到默认内容树排序首项所对应的本地化页面。

默认内容树决定站点结构，包括有哪些笔记、笔记如何分类与排序，以及使用哪些公开路由。译文只提供本地化内容，不会创建另一套信息架构。

## 定义语言清单

每个已配置语言都必须在其语言根目录提供 `_locale.yml`。默认语言清单位于内容根目录；其他语言清单位于 `_translations/<locale>/_locale.yml`。

```yaml
name: 简体中文
hreflang: zh-Hans
dir: ltr
messages:
  search: 搜索
```

`name` 为必填项，并显示在语言切换器中。`hreflang` 默认使用配置的语言标签。`dir` 默认为 `ltr`，且只接受 `ltr` 或 `rtl`。

`messages` 用于覆盖主题中的固定界面文案。值必须是字符串，键必须属于内置文案目录。未知键和非字符串值都会导致构建失败。省略的文案使用内置英文，因此可以先提交一小组经过检查的覆盖项，再逐步完善。

## 编写译文

每篇译文都会继承其公开默认语言笔记的发布状态，因此译文 frontmatter 可以省略 `publish`：

```yaml
---
title: 快速开始
description: 安装并构建第一个站点。
tags:
  - 指南
---
```

译文可以替换正文，以及 `title`、`subtitle`、`description`、`tags`、`author`、`categories`、`image` 和 `cssclasses` 这些可翻译属性。默认语言页面加入顶部导航后，译文也可以替换 `navigation.label`。省略的值从默认语言笔记继承。如需只停用该译文，请设置 YAML 布尔值 `publish: false`；对应的本地化 URL 会显示默认语言回退内容。

结构属性由默认语言笔记决定，包括 `permalink`、`content_type`、`date`、`created`、`updated`、`nav_order`、`nav_exclude`、`aliases` 和 `comments`。请在译文中省略这些属性；如果保留，其值必须与默认语言笔记完全一致。译文必须始终省略 `navigation.order` 和 `navigation.visible`，尝试设置任意一项都会被拒绝。文章未设置 `date` 或 `created` 时，会继承默认语言笔记由 Git 推导的发布时间。`updated` 不会从 Git 推导；只有默认语言笔记明确声明更新日期时才应设置。仅提交译文不会改变文章时间顺序或 Blog 排序。

## 理解本地化 URL 与资源

默认语言保留原有 URL。其他语言把配置的语言标签放在路径的第一个分段：

```text
guide/Start.md
→ /guide/Start/

_translations/zh-CN/guide/Start.md
→ /zh-CN/guide/Start/
```

站点 `baseurl` 仍会添加到两种路径之前。公开路径会原样保留配置中的语言标签。

每个语言都有独立的导航、上一篇与下一篇、标签、图谱、关系、搜索索引、订阅源和适用的系统页面。默认语言资源位于 `/assets/website/`；其他语言使用 `/assets/website/i18n/<locale>/`。这样可以避免不同语言的导航与搜索数据混用。

## 链接笔记并共享附件

Wikilink、嵌入、反向链接和源码操作会优先在当前语言中解析。没有可用译文时，编译器使用默认语言笔记。编辑和历史记录操作会指向实际提供当前显示内容的源文件。

二进制附件继续由默认内容树共享。不要在 `_translations/` 下存放语言专用的图片、PDF、Canvas 文件或其他二进制资源。译文可以继续引用默认内容树中的共享附件。

## 处理缺失译文

笔记缺少译文时，构建仍会成功，编译器也会生成带语言前缀的 URL。缺少译文本身不会产生警告或错误。页面显示本地化的缺失译文提示，并展示默认语言内容。正文保留默认语言及其文字方向，即使外层语言采用从右到左的排版也是如此。

回退页面把 canonical 链接指向默认语言页面，并带有 `noindex` 指令。它不会进入 sitemap 或互惠 `hreflang` 组。语言切换器仍可链接到该页面，从而保持本地化导航完整，并明确区分搜索引擎收录边界。

## 切换语言并发布 SEO 元数据

语言切换器由服务器渲染，使用普通链接，并按照已配置语言的顺序排列。禁用 JavaScript 后仍可切换。JavaScript 只增强关闭与焦点行为；站点不会检测浏览器语言，也不会自动重定向。

真实译文使用指向自身的 canonical URL。每个完整翻译组都会输出互惠 `hreflang` 链接，并为默认语言页面输出 `x-default`。页面外壳采用当前语言的 `<html lang dir>` 值；回退页面中的原文区域则保留自身的语言边界。

所有语言的日期都使用确定性的 ISO 格式，以免英文月份名称出现在已经本地化的导航和系统页面中。

## 排查本地化构建问题

| 构建失败 | 检查内容 |
| --- | --- |
| 缺少默认语言 | 把顶层 `lang` 加入 `website.i18n.locales`。 |
| 语言清单缺失或无效 | 在每个语言根目录添加 `_locale.yml`，填写 `name`，并检查 `hreflang`、`dir` 与文案值。 |
| 存在孤立译文 | 在相同相对路径创建默认语言笔记，或删除该译文。 |
| 译文覆盖了结构 | 从译文中移除结构属性，或使其与默认语言笔记完全一致。 |
| 不支持本地化附件 | 把二进制附件移到默认内容树，并引用该共享文件。 |
| 语言路由冲突 | 重命名冲突的笔记或 permalink。语言订阅源、资源和系统页面会保留各自的目标路径。 |

发布后应保持语言标签和笔记相对路径稳定。更改任一项都会改变本地化公开 URL；移动或重命名笔记还可能改变其评论讨论串标识。
