---
publish: true
title: 评论
description: 配置 GitHub Discussions 评论，理解讨论串标识，并排查 Giscus 问题。
---

# 使用 GitHub Discussions 提供评论

Jekyll Obsidian 通过 [Giscus](https://giscus.app/) 为已发布的文章关联 GitHub Discussion。站点本身仍是静态站点，不运行评论数据库或服务端 API，讨论数据保存在 GitHub 中。

访客可以直接在页面中阅读公开讨论。发表评论或表情回应时，需要通过 Giscus 使用 GitHub 身份验证。页面始终保留前往 GitHub Discussions 的普通链接，因此即使 JavaScript 被禁用或嵌入服务不可用，读者仍可在 GitHub 中继续讨论。

## 哪些页面会显示评论

所有内置主题都支持评论，但只有分类为 `content_type: post` 的页面可以挂载评论组件。普通页面、文档笔记、Blog 索引、标签及其他生成页面都不会显示评论。

要启用评论，必须先配置 `website.comments`。没有这个映射时，所有主题都会关闭评论。该映射存在但省略 `enabled` 时，由主题决定默认状态：

| 主题 | 配置 `website.comments` 后的默认状态 |
| --- | --- |
| `minimal` | 开启 |
| `docs` | 关闭 |

任何主题都可以通过 `enabled: true` 或 `enabled: false` 覆盖默认状态。

## 准备 Discussions 仓库

发布仓库和评论仓库可以是同一个公开仓库，也可以把社区讨论放在单独的公开仓库中。

1. 在评论仓库中打开 **Settings → General → Features**，启用 **Discussions**。具体步骤请参阅 [GitHub 的仓库设置文档](https://docs.github.com/zh/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/enabling-or-disabling-github-discussions-for-a-repository)。
2. 创建一个分类，例如 `Blog comments`。建议使用 Announcement 格式，只有维护者和 Giscus 可以在该分类中创建讨论，访客仍可回复。
3. 为评论仓库安装 [Giscus GitHub App](https://github.com/apps/giscus)。
4. 在 [giscus.app](https://giscus.app/zh-CN) 中填写仓库。在 **页面 ↔️ discussion 映射关系** 中选择 **Discussion 的标题包含特定字符串**，并勾选 **使用严格的标题匹配**。特定字符串可以留空，Jekyll Obsidian 会为每篇文章提供严格匹配的 `website:post:...` 标识。不要选择 `pathname`、URL、页面标题、`og:title` 或特定 discussion 号。
5. 选择分类，然后复制生成的仓库 ID 与分类 ID。不要根据显示名称猜测这些 ID，也不要复制生成的 `<script>` 标签；映射方式、标识和运行时选项都由 Jekyll Obsidian 管理。

评论仓库必须公开，否则访客无法读取讨论。这些属于运行时前置条件，不是构建前置条件。构建过程不会启用 Discussions、创建分类、安装 GitHub App、检查其远程状态，也不会连接 GitHub。尚未满足或之后被关闭的远程条件都不会让静态构建失败。

## 配置站点

在 `.github/jekyll-obsidian.yml` 中，把评论配置放在受管的 `source` 和 `theme` 行之外：

```yaml
website:
  # jekyll-obsidian:managed-start
  source: docs
  theme: minimal
  # jekyll-obsidian:managed-end
  repository: owner/site
  comments:
    enabled: true
    # 可选。省略后复用 website.repository。
    repository: owner/community
    repository_id: R_kgDOxxxxxxxx
    category: Blog comments
    category_id: DIC_kwDOxxxxxxxx
```

只有当 `website.repository` 已经指向评论仓库时，才可以省略 `repository`。启用评论时必须能取得格式正确的仓库标识。

Giscus 需要 `repository_id`、`category` 和 `category_id` 才能载入，但构建不要求这些值全部就绪。缺少任意一项时，编译器会产生 `comments_unconfigured` 警告。符合条件的文章会显示不可交互的待配置提示和评论仓库链接，但不会载入 Giscus 客户端。你可以先启用评论，等 Discussions 与 Giscus App 准备完成后再补充这些值。

未知配置项、非布尔值的 `enabled`、格式错误的仓库名，以及非字符串的服务配置值仍属于致命配置错误。

`website/bin/integrate` 会保留已有的评论配置，但不会主动创建它。修改宿主配置后，请运行一次生产构建：

```sh
JEKYLL_ENV=production website/bin/build \
  --url https://docs.example.com \
  --baseurl "" \
  --destination _site
```

## 控制单篇文章

站点级评论启用后，每篇已发布文章都会显示评论。可以用 YAML 布尔值关闭其中一篇：

```yaml
---
publish: true
content_type: post
date: 2026-08-04
comments: false
---
```

如果 `website.comments` 缺失或已关闭，页面属性无法单独开启评论。`comments: true` 也不会把普通页面或文档笔记改成文章；请使用 `content_type: post`，或把文件放入配置的文章目录。

## 讨论串标识与创建时机

每篇文章都使用由逻辑笔记路径生成的严格标识：

```text
website:post:blog/my-post
```

修改站点域名、`baseurl` 或 permalink 不会更换 Discussion。移动或重命名源笔记会改变标识，从而使用新的讨论串。已有 Discussion 不会自动迁移。

同一逻辑文章的不同语言版本共享一个 Discussion。Giscus 支持当前页面语言时，组件会使用该语言；否则回退到英文。

构建和首次打开页面都不会创建空 Discussion。访客第一次提交评论或表情回应时，Giscus 才会创建讨论。因此，尚无 Discussion 是正常且可用的状态。

## 运行时与降级行为

本地开发环境不会连接 Giscus，只显示“评论仅在发布站点中载入”的提示，以及指向 Discussions 页面的链接。

只有服务配置完整时，生产和 CI 构建才会在符合条件的文章中载入 Giscus 客户端。iframe 会在评论区域接近视口时延迟载入，自动匹配站点的浅色或深色配色，并在配色切换后同步更新。

如果 Discussions 未启用、Giscus App 未安装或外部客户端不可用，站点本身仍会正常运行。评论区域会进入非致命的暂不可用状态，并保留服务器渲染的 GitHub 链接。这些运行时问题不会影响页面的其他功能或之后的构建。

启用评论的页面会获得范围受限的内容安全策略，允许 Giscus 脚本、iframe 和默认样式表。其他页面继续使用仅允许站点自身资源的策略。

## 隐私与来源限制

评论和表情回应是评论仓库中的公开 GitHub 数据。访客发表评论前需要使用 GitHub 身份验证，维护者也需要在 GitHub Discussions 中进行审核和管理。如果站点有额外的隐私或合规要求，请先评估 GitHub 与 Giscus 的相关政策。

若要阻止其他站点嵌入你仓库中的 Discussions，请在评论仓库根目录添加 `giscus.json`：

```json
{
  "origins": ["https://docs.example.com"]
}
```

> [!important] 只填写页面源（origin）
> Giscus 会用 `window.origin` 检查 `origins`。不要加入路径或 `baseurl`。例如页面地址是 `https://owner.github.io/project/` 时，应填写 `https://owner.github.io`。

`originsRegex` 等仓库级配置请参阅 [Giscus 高级用法](https://github.com/giscus/giscus/blob/main/ADVANCED-USAGE.md#giscusjson)。

## 排查问题

| 现象 | 检查项 |
| --- | --- |
| 页面没有评论区域 | 确认 `website.comments` 已配置，当前主题已启用评论，笔记分类为文章，且前置元数据中没有 `comments: false`。 |
| 构建报告 `invalid_comments` | 确认 `enabled` 是 YAML 布尔值，仓库名称采用 `owner/repository` 格式，服务配置值都是字符串，且没有未知配置项。 |
| 构建提示 `comments_unconfigured` | 构建已经成功，但 Giscus 暂不启用。请启用 Discussions、安装 Giscus App，再从 giscus.app 补齐缺少的 ID 与分类。 |
| 页面提示评论仅在发布站点中载入 | 这是本地开发环境的预期行为。请使用生产构建测试外部客户端。 |
| 评论组件暂不可用 | 站点的其他部分仍可使用。请确认仓库公开、Discussions 已启用、Giscus App 已安装、分类仍存在，并且 `giscus.json` 允许生产站点的 origin。 |
| 文章还没有 Discussion | 提交第一条评论或表情回应，Giscus 会在第一次互动时创建 Discussion。 |
| 重命名文章后出现新的讨论串 | 稳定标识包含源文件路径。需要时可以重命名原 Discussion 以便查找，但站点不会自动迁移它。 |
