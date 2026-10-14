# IPPure Bar — 设计说明

一个没有常规窗口的 macOS 小工具：把 `https://my.ippure.com/v1/info` 的结果展示在 **Dock 图标**和**菜单栏**里。

## 接口

`GET https://my.ippure.com/v1/info`，返回调用方出口 IP 的信息，示例：

```json
{
  "ip": "103.23.75.11", "asn": 2914, "asOrganization": "NTT Communications Corporation",
  "country": "Japan", "countryCode": "JP", "region": "Tokyo", "regionCode": "13",
  "city": "Tokyo", "timezone": "Asia/Tokyo", "longitude": "139.69171", "latitude": "35.6895",
  "postalCode": "101-8656", "fraudScore": 12, "isResidential": false, "isBroadcast": false,
  "userAgent": "curl/8.7.1"
}
```

所有字段都按可选解析，缺字段不能导致解码失败。

## 技术选型

- Swift + AppKit，SwiftPM 可执行目标（无 Xcode 工程），macOS 13+。
- `scripts/build_app.sh` 把产物组装成 `build/IPPure Bar.app`（Info.plist、ad-hoc 签名）。
- 不引入第三方依赖。

## 网络与代理

- 默认 **跟随系统代理**：`URLSessionConfiguration.ephemeral` 且不设置 `connectionProxyDictionary`，系统代理（含 PAC）由 CFNetwork 自动应用。
- 可选 **直连**：`connectionProxyDictionary = [:]`。
- 每次请求新建 session 并在结束后 `finishTasksAndInvalidate()`，避免 keep-alive 连接沿用旧的出口线路；缓存策略 `reloadIgnoringLocalCacheData`。
- 超时 15 秒。
- 菜单里显示当前生效的系统代理（读 `CFNetworkCopySystemProxySettings`，例如 `HTTPS 127.0.0.1:7897`，或 `PAC`、`无`）。

## 刷新时机

- 启动时、手动「立即刷新」(⌘R)、点击 Dock 图标（reopen）。
- 定时：1 / 5 / 15 / 30 分钟或关闭，默认 5 分钟。
- 网络变化（`NWPathMonitor`）、系统代理变化（`SCDynamicStore` 监听 `State:/Network/Global/Proxies`）、从睡眠唤醒，均去抖 2 秒后刷新。
- 同一时间只允许一个请求在飞；新的触发会取消旧请求。

## 风险分级（fraudScore 越低越好）

| 分数 | 等级 | 颜色 |
| --- | --- | --- |
| 0–24 | 低风险 | 绿 |
| 25–49 | 中风险 | 黄 |
| 50–74 | 高风险 | 橙 |
| 75–100 | 极高风险 | 红 |

IP 属性：
- `isResidential == true` → 住宅 IP，否则 机房 IP。
- `isBroadcast == true` → 广播 IP，否则 原生 IP。

## Dock 图标（动态绘制，512×512）

- 圆角方形深色底。
- 上半部：风险分数进度环，颜色按等级，弧长 = 分数/100；环内上方国旗 emoji（由 countryCode 生成），下方大号分数数字。
- 下半部：IP 铭牌，底色按风险等级着色，等宽数字、字号自适应铺满；IPv6 单行放不下时从中间冒号处拆成两行。
- 不展示原生/广播、住宅/机房（这些只在菜单里显示）。
- 加载中 / 出错：铭牌显示「加载中」/「请求失败」；加载中环为灰色并显示「…」；出错：灰底 + 「!」，`dockTile.badgeLabel = "!"`，成功时清空 badge。
- 通过 `NSApp.applicationIconImage` 设置。

## 菜单栏

- 状态项标题：`🇯🇵 12`，分数带等级颜色（`attributedTitle`），加载中显示 `…`，出错显示 `⚠︎`。
- 下拉菜单（Dock 右键菜单 `applicationDockMenu` 复用同样的信息区）：
  - IP（点击复制）
  - 位置：`Tokyo, Tokyo, Japan`
  - ASN：`AS2914 · NTT Communications Corporation`
  - 风险：`12 · 低风险`
  - 类型：`原生 IP · 机房 IP`
  - 时区、坐标、邮编
  - 代理：当前系统代理描述
  - 更新时间 / 错误信息
  - ——
  - 立即刷新 ⌘R
  - 自动刷新 ▸（关闭 / 1 / 5 / 15 / 30 分钟）
  - 网络模式 ▸（跟随系统代理 / 直连）
  - 在 Dock 中显示（切换 `.regular` / `.accessory`）
  - 开机启动（`SMAppService.mainApp`）
  - 在 IPPure 网页查看（打开 https://ippure.com）
  - 退出 ⌘Q
- 设置存 `UserDefaults`。

## 代码结构

```
Package.swift
Sources/IPPureBar/
  main.swift            入口
  AppDelegate.swift     生命周期、菜单栏、Dock 菜单组装
  IPInfo.swift          模型 + 风险分级 + 国旗
  IPInfoClient.swift    网络请求、代理模式
  ProxyInfo.swift       读取系统代理描述
  RefreshScheduler.swift 定时、网络/代理/唤醒触发
  DockIconRenderer.swift 绘制 Dock 图标
  MenuBuilder.swift     菜单内容
  Settings.swift        UserDefaults 封装
scripts/build_app.sh
Resources/Info.plist
```
