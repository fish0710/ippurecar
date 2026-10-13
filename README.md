# IPPure Bar

一个没有常规窗口的 macOS 小工具：把 `https://my.ippure.com/v1/info` 返回的出口 IP 信息展示在 **Dock 图标**和**菜单栏**里。

## 功能

- Dock 图标动态绘制：风险分数进度环（绿/黄/橙/红）、国旗、分数，底部胶囊显示 `JP · 原生 · 机房`；加载中为灰色「…」，出错为「!」并带红色角标。
- 菜单栏显示 `🇯🇵 12`（分数按风险等级着色）；下拉菜单（Dock 右键菜单同样包含信息区）展示 IP（点击复制）、位置、ASN、风险、IP 类型、时区、坐标、邮编、当前系统代理、更新时间/错误信息。
- 默认跟随系统代理（含 PAC），也可切换为直连；每次请求新建会话，避免沿用旧出口线路。
- 刷新时机：启动、手动（⌘R）、点击 Dock 图标；定时（关闭 / 1 / 5 / 15 / 30 分钟，默认 5 分钟）；网络变化、系统代理变化、睡眠唤醒（去抖 2 秒）。
- 可选「在 Dock 中显示」（默认显示）、开机启动。设置保存在 `UserDefaults`。

## 构建与运行

要求：macOS 13+，Swift 工具链（Xcode 或 Command Line Tools）。无第三方依赖。

```bash
./scripts/build_app.sh
open "build/IPPure Bar.app"
```

## 调试参数

直接运行二进制 `build/IPPure Bar.app/Contents/MacOS/IPPureBar`：

- `--dump-icon /tmp/x.png`（或环境变量 `IPPURE_DUMP_ICON`）：首次成功获取后写出 Dock 图标 PNG，并在标准输出打印解码后的 `IPInfo`。
- `--dump-states /tmp/dir`：写出 `loading.png`、`error.png` 以及分数 5/35/60/90 的样例图标。
