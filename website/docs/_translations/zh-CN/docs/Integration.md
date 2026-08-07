---
publish: true
title: 宿主集成
description: 无需本地构建工具链，即可把 website 工作区加入其他仓库并部署其内容。
---

# 宿主集成

将完整的 `website/` 目录复制到宿主仓库根目录。宿主内容保留在该目录之外，因此以后更换或更新发布实现时，无需移动原始笔记。

## 无需安装工具链即可部署

宿主中必须已有至少一篇公开笔记，例如 `docs/Start.md`：

```yaml
---
publish: true
title: Documentation
---
```

在 macOS、Linux 或 WSL 中，从宿主仓库根目录运行：

```sh
website/bin/integrate
```

在原生 Windows 的命令提示符中运行：

```bat
website\bin\integrate.cmd
```

也可以在 PowerShell 中运行：

```powershell
.\website\bin\integrate.cmd
```

CMD 启动器会优先使用 PowerShell 7；如果系统没有安装，则回退到 Windows PowerShell 5.1，并且不会修改计算机的执行策略。也可以直接调用适配器：

```powershell
.\website\bin\integrate.ps1
```

该命令不需要 Ruby 或 Node.js。默认内容目录为 `docs/`，默认主题为 `minimal`。它会创建 `.github/jekyll-obsidian.yml` 并生成 `.github/workflows/pages.yml`，但不会访问 GitHub 或修改仓库设置。

随后打开 **Settings → Pages → Build and deployment**，将 **Source** 设为 **GitHub Actions**，提交生成的文件并推送。GitHub Actions 会安装 Ruby、Node.js、依赖和 Chromium，再构建并部署站点。

**Verify and deploy Pages** 成功后，可以从其 `deploy` 作业或 **Settings → Pages** 打开站点。普通项目仓库使用 `https://<owner>.github.io/<repository>/`；名称为 `<owner>.github.io` 的仓库使用 `https://<owner>.github.io/`。配置自定义域名后，该域名会取代默认地址。工作流如何取得并应用最终 URL，详见 [[Deployment|部署]]。

## 选择内容目录与主题

两个平台适配器接受相同选项：

```text
--source PATH
--theme minimal|docs
--check
--force-workflow
--help
```

例如：

```sh
website/bin/integrate --source handbook --theme minimal
website/bin/integrate --check
```

Windows 路径分隔符会在写入可移植配置前完成规范化：

```powershell
.\website\bin\integrate.cmd --source "Documentation\User Guide" --theme docs
```

内容目录必须是仓库中已经存在的相对目录。路径遍历、与站点重叠、符号链接、Windows junction、reparse point 和路径大小写不一致都会被拒绝。内容根目录及其所有子目录都可以没有 `index.md`。无依赖命令负责校验集成路径；Actions 中的编译器继续负责 YAML、路由、链接、附件和发布规则，并要求发布策略至少选中一篇笔记。

主题标识只支持 `minimal` 和 `docs`。

## 自定义宿主配置

生成的宿主配置包含一个托管块：

```yaml
title: My Project Documentation

website:
  # jekyll-obsidian:managed-start
  source: docs
  theme: minimal
  # jekyll-obsidian:managed-end
  repository: ""
  edit_branch: main
  content:
    publish_by_default: []
    default_type: doc
    directories:
      post: []
      doc: []
```

`integrate` 只更新标记之间的 `source` 和 `theme` 行，其他配置项和注释都归宿主管理，其中包括所有主题都能使用的 `website.comments`、`website.i18n` 和 `website.analytics` 映射。评论需要仓库所有者另行配置 GitHub Discussions 与 Giscus；流量统计默认关闭。新宿主的 `publish_by_default` 为空，因此笔记需要显式设置 `publish: true`。添加 `.` 可以默认发布整个内容树，也可以列出一个或多个相对目录。生成的内容默认值会把 `docs/` 直属的已发布文件分类为文档，所以 `docs/guide.md` 被发布后会出现在 Docs 导航中。

发布接口是根级 `website:` 映射。`integrate` 要求只存在一个受管的 `website:` 根；托管标记缺失或格式错误时，它会安全失败。

配置优先级依次为 `website/_config.yml`、`.github/jekyll-obsidian.yml`、显式的 `bin/build` 与 Pages 值。`bin/build` 会把 Jekyll 的 source、实现目录、缓存、目标目录和安全设置固定在 `website/` 中，宿主配置无法移动这些路径或绕过适配器。

生成的工作流完全由工具管理。更新 `website/` 或更改内容目录后，请重新运行 `integrate`。已有但不受管理的 `pages.yml` 会触发安全失败；检查其内容后，只有确定需要替换时才使用 `--force-workflow`。只读的 `--check` 模式会报告偏差但不写文件，CI 开始时也会运行它。

宿主已有配置但缺少托管标记时，命令会打印需要合并的配置块，并保持两个文件不变。添加标记后，再次运行同一命令。省略的参数会保留当前托管值。

## 更新带 tag 的安装

复制的 `website/` 工作区属于 `jekyll-obsidian`，但它位于具有独立 Git 历史的宿主仓库中。不要把本项目添加为 upstream remote，也不要对宿主运行指向本项目的 `git pull`。请使用已经安装的命令更新：

```sh
website/bin/update --check
website/bin/update
website/bin/update --to 2026.8.1
```

原生 Windows 可以通过 CMD 启动器使用相同选项：

```bat
website\bin\update.cmd --check
website\bin\update.cmd
```

未提供 `--to` 时，命令会选择最新的官方 annotated `vYYYY.M.D` tag。目标可以是当前已安装版本，也可以向前更新，但不能降级。`--check` 不写文件。安装已经是目标版本时返回 `0`，存在更新或可首次记录来源时返回 `2`，参数无效、本地偏离、网络失败或 release 无效时返回 `1`。

`--to` 接受不含前缀 `v` 的官方 annotated 日历版本；上面的 `2026.8.1` 只用于展示格式。没有稳定 release 时，命令会报告该状态，并保持宿主不变。安装必须与某个官方 tag 匹配，严格更新才能建立或验证其来源。

更新器需要 Git，但不需要 Ruby 或 Node.js。它只会把官方仓库获取到隔离的事务目录中，不会修改宿主的 remote、ref、分支、索引、提交或 GitHub 设置。它会更新 `website/` 中由 release 管理的跟踪文件、托管配置块、生成的 Pages 工作流和 `.github/jekyll-obsidian.lock`。安装版本与目标版本都忽略的文件会保持不变；如果目标新增的跟踪路径会覆盖本地忽略状态，更新会安全失败。

更新前，请提交或撤销对托管工作区、工作流和锁文件的旧修改。无关的内容更改和托管块外的配置可以继续保持未提交。命令会拒绝 `website/` 中已提交的自定义、暂存或未暂存的托管文件修改，以及未忽略的额外文件；它不提供强制或合并模式。应把需要保留的自定义移动到宿主配置或内容目录。

没有来源锁的安装只有在已提交 `website/` 的路径与内容集合完全匹配其内置日历版本对应的官方 tag 时，才能被接管。未带 tag 的 checkout 无法证明来源。没有匹配 tag 时，请先用完整的带 tag 快照替换一次 `website/`，重新运行 `integrate`，然后再次运行 `update`。Release tag 不可变；已安装 tag 后续被删除或移动都会被视为错误。

目标 release 会先在影子宿主中生成并检查集成文件，之后才修改真实宿主。应用阶段会使用备份与事务日志支持回滚。后续命令只有在记录的旧文件或新文件摘要完全匹配时，才会恢复中断的事务；状态不明确时会保留现场供检查，不会直接覆盖。更新成功后，请检查 `git diff`，在本地预览前运行 `website/bin/setup`，并自行提交托管文件。

## 让编辑器状态留在本地

编译器和 watcher 会排除 `.obsidian/` 与 `.trash/`，但仓库读者仍能看到所有已提交文件。配置的内容目录尚未忽略这些文件时，请添加对应规则：

```gitignore
docs/.obsidian/workspace*.json
docs/.trash/
```

只有被 `publish: true` 或 `website.content.publish_by_default` 选中的笔记才会进入生成站点，选中范围内的笔记仍可通过 `publish: false` 排除。这些开关不是仓库隐私机制。不要把密钥或私密记录提交到他人可读的仓库。

## 可选的本地开发

部署不需要本地工具链。只有需要本地预览或测试时，才安装 Ruby 4.0.x 和 Node.js 26.x：

```sh
website/bin/setup
website/bin/dev
```

本指南中的原生 Windows 支持覆盖集成与部署。本地 Jekyll 开发命令请在 WSL 中运行。接下来可以阅读 [[Customization|自定义]]或 [[Deployment|部署]]。

## 排查问题

- 编译器报告内容目录没有公开笔记时，请为一篇笔记添加未加引号的顶层 `publish: true`，或在 `website.content.publish_by_default` 下配置一个目录。
- 命令报告站点重叠时，请把宿主内容放在 `website/` 之外。只有项目自带的 `website/docs/` 示例允许位于其中。
- 出现 `pages.yml is not managed` 时，请检查已有工作流。只有确定要替换它时才使用 `--force-workflow`。
- 更新 `website/` 后，`--check` 报告偏差时，请先运行一次不带 `--check` 的 `integrate`，再提交刷新后的文件。
- GitHub 完成构建但没有部署时，请确认 **Settings → Pages → Build and deployment → Source** 已设置为 **GitHub Actions**。
