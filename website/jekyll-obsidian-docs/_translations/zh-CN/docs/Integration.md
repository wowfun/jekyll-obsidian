---
publish: true
title: 宿主集成
description: 通过 RubyGems 或 GitHub Actions 安装发布工具，内容和配置保留在自己的仓库中。
---

# 宿主集成

宿主仓库只需保留内容、`.github/jekyll-obsidian.yml` 和 Pages 工作流。`jekyll-obsidian-site` gem 提供编译器、主题和预编译前端资源，命令名为 `jekyll-obsidian`。

## 无需安装工具链即可部署

将[配置示例](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.0/examples/jekyll-obsidian.yml)复制到 `.github/jekyll-obsidian.yml`，将 [Pages 工作流](https://github.com/wowfun/jekyll-obsidian/blob/v0.2.0/examples/pages.yml)复制到 `.github/workflows/pages.yml`。

```yaml
title: My Site
website:
  source: docs
  theme: minimal
```

在 `docs/` 中添加一篇带 `publish: true` 的 Markdown 笔记。在 **Settings > Pages > Build and deployment > Source** 中选择 **GitHub Actions**，然后提交并推送。Actions 会安装 Ruby 和对应版本的 gem，本地无需安装 Ruby 或 Node.js。

`website.source` 相对于仓库根目录，支持 `docs/`、`website/docs/`，以及带空格或中文名称的嵌套目录。本项目自己的文档位于 `website/jekyll-obsidian-docs/`，不会打进 gem。

## 本地初始化

在 macOS、Linux 或 WSL 中安装 Ruby 4.0.x，然后从仓库根目录运行：

```sh
gem install jekyll-obsidian-site
jekyll-obsidian init --source website/docs --theme docs
jekyll-obsidian dev
```

`init` 创建配置和 Pages 工作流，只在内容目录不存在或为空时添加公开的欢迎页。重复执行相同初始化会保留已匹配的文件；遇到冲突会在写入前报错。已有配置或工作流时，请参考上面的示例直接编辑。

所有配置项都可以直接编辑，包括 `source` 和 `theme`，修改会在下一次构建时生效。发布默认值和功能配置见 [[Customization|自定义]]。

## 使用 Bundler

如果项目使用 Gemfile，可以加入：

```ruby
source "https://rubygems.org"
gem "jekyll-obsidian-site", "~> 0.2.0"
```

```sh
bundle install
bundle exec jekyll-obsidian init --source docs
bundle exec jekyll-obsidian dev
```

提交 `Gemfile` 和 `Gemfile.lock` 以锁定本地依赖。Action 会独立选择与其版本对应的 gem，请让工作流引用与本地 gem 版本保持一致。本工具不会载入宿主已有的 Jekyll `_config.yml` 或插件。

## 更新

将工作流中的 `uses: wowfun/jekyll-obsidian@v0.2.0` 改为需要的发行 tag，Action 会安装该版本对应的 gem。

直接安装的 gem 用 `gem update jekyll-obsidian-site` 更新。使用 Bundler 时，按需要调整版本约束，运行 `bundle update jekyll-obsidian-site` 并提交锁文件。包更新不会改写宿主内容和配置。

本版本不再支持旧的目录复制安装。请保留内容和 `.github/jekyll-obsidian.yml`，删除配置中的托管标记注释，替换旧工作流，再移除旧实现文件。保留 `website/` 内自己编写的文件。

## 预览与构建

`jekyll-obsidian dev` 在 `http://127.0.0.1:58000/` 提供预览，并监听内容和配置。重建失败时继续提供上次成功的输出。

```sh
jekyll-obsidian build --url https://example.com --baseurl /project
jekyll-obsidian clean
```

生成站点位于 `.jekyll-obsidian-cache/site/`。`clean` 清理本工具的缓存和输出，保留笔记、配置、已安装依赖和其他工具的 `_site/` 目录。使用过程中不会写入已安装的 gem。

## 排查问题

- 找不到配置：在仓库根目录运行 `init`，或添加两个示例文件。
- 没有公开笔记：添加 YAML 布尔值 `publish: true`，或显式配置 `website.content.publish_by_default`。
- `init` 报告文件冲突：直接编辑已有文件，命令不会覆盖它们。
- 安装到了其他项目：gem 包名为 **jekyll-obsidian-site**，命令名为 **jekyll-obsidian**。
- 内容或缓存路径包含符号链接：改用仓库中的真实目录。
