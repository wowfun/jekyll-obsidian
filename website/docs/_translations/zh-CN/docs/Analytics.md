---
publish: true
title: 流量统计
description: 无需运行站点后端，即可选用 Cloudflare Web Analytics 或 Google Analytics。
---

# 流量统计

Jekyll Obsidian 可以在已发布站点中载入 Cloudflare Web Analytics 或 Google Analytics。未配置 `website.analytics` 时，流量统计保持关闭；一个站点只能选择一家服务。

构建过程不会向统计服务发送页面数据。它只负责校验配置，并在生产页面中加入对应客户端。本地开发不会载入这两个客户端；重定向页面也不会跟踪，以免一次跳转产生第二次页面浏览。

## 使用 Cloudflare Web Analytics

公开站点只需要基本流量数据时，建议使用 Cloudflare Web Analytics。它可以免费使用，无需把 DNS 或站点代理迁移到 Cloudflare。Cloudflare 将其说明为重视隐私的统计服务，并表示它不会收集或使用访客个人数据。启用前请阅读 [Cloudflare 产品说明](https://developers.cloudflare.com/web-analytics/about/)。

在 Cloudflare Web Analytics 控制台中创建站点，复制站点令牌（token），再把以下配置放在托管配置块之外：

```yaml
website:
  analytics:
    provider: cloudflare
    token: SITE_TOKEN
```

生产站点只会载入一次 Cloudflare 官方 beacon。Cloudflare 会自动跟踪 Docs 主题所用的 History API，包括 `pushState` 和 `popstate` 导航。具体行为请参阅 [Cloudflare 单页应用说明](https://developers.cloudflare.com/web-analytics/get-started/web-analytics-spa/)。

## 使用 Google Analytics

站点已经使用 Google Analytics 4 属性时，可以选择 Google。复制网站数据流的 measurement ID，并添加以下配置：

```yaml
website:
  analytics:
    provider: google
    measurement_id: G-XXXXXXXXXX
```

在 Google Analytics 中打开网站数据流的 Enhanced Measurement 设置，并保持 Page loads 与 Page changes based on browser history events 开启。站点只会载入 `gtag.js` 并配置一次属性；Docs 切换页面时，不会再发送一条自定义 `page_view`。具体设置请参阅 [Google 单页应用说明](https://developers.google.com/analytics/devguides/collection/ga4/single-page-applications)。

Google Analytics 可能使用 `_ga` 等 Cookie 和标识符来区分访客。启用前，请阅读 [Google 数据收集说明](https://support.google.com/analytics/answer/11593727?hl=zh-Hans)，并确认它符合站点受众所在地区的要求。

## 配置与安全边界

`provider` 只接受 `cloudflare` 或 `google`。Cloudflare 必须提供 `token`，Google 必须提供 `measurement_id`。不能混用两家服务的字段；未知配置项或错误类型都会让构建失败。删除完整的 `analytics` 映射即可关闭统计。

编译器只会加入所选服务需要的内容安全策略来源。Cloudflare 页面允许其 beacon 和上报端点；Google 页面允许 Google Tag Manager 与 GA4 数据收集端点。配置不会启用 Google Ads、DoubleClick、内联脚本或动态代码求值。

两种方案都会从访客浏览器向第三方发起网络请求。Jekyll Obsidian 不提供同意横幅、广告功能、自定义事件、双服务跟踪、服务端代理或统计面板。启用统计前，请根据站点所在地和受众补充必要的同意流程。

## 排查统计问题

| 现象 | 检查项 |
| --- | --- |
| 本地预览中没有统计请求 | 这是预期行为。统计客户端只会载入生产输出。 |
| 构建拒绝该映射 | 只选择一家服务，并提供与它匹配的字符串 ID。删除另一家服务的字段和所有未知配置项。 |
| Cloudflare 没有显示访问 | 确认 token 属于当前站点，并检查浏览器是否阻止了 beacon 请求。 |
| Google 漏掉 Docs 页面切换 | 在 GA4 网站数据流的 Enhanced Measurement 中开启页面载入和浏览器历史记录事件。 |
| Google 重复统计页面 | 删除另行安装的统计代码或标签管理器页面浏览规则。Jekyll Obsidian 只初始化一次客户端。 |

完整配置文件中的放置位置请参阅 [[Customization#流量统计|自定义]]，生产构建说明请参阅 [[Deployment|部署]]。
