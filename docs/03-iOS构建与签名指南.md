# iOS 构建与签名指南

《江湖夜雨录》v0.2 起支持 iOS 端（与 Windows 共用同一套 Godot 4.7 工程）。
代码侧已就绪：触屏虚拟操控、内嵌 Noto Sans SC 中文字体、横屏适配、云存档互通。
本文覆盖需要你完成的**构建与签名**步骤。

## 前置认知

- Godot 的 iOS 导出**只能在 macOS + Xcode 上完成**（Windows 无法直接出 ipa）——没有 Mac 就走**路线 C**：云构建出未签名 ipa + Windows 上 Sideloadly 侧载，全程无需 Mac
- 仓库已内置：`export_presets.cfg`（iOS 预设）、`.github/workflows/ios-build.yml`（云构建）、`assets/icons/icon_1024.png`（应用图标）
- 渲染器 `gl_compatibility`（mobile 变体已预设）；中文不依赖系统字体（内嵌 OFL 开源字体）

## 路线 A：GitHub Actions 云构建（无 Mac 出包，签名仍需 Mac）

1. 把项目推到 GitHub（`main` 分支，或打 `v*` tag 自动触发）
2. Actions → 「测试与 iOS 构建」→ Run workflow：
   - `tests` job：ubuntu 上跑 107 项逻辑回归
   - `export-ios` job：macOS runner 导出**未签名** Xcode 工程 + 未签名 ipa → Artifacts `JiangHuYeYuLu-iOS-Xcode`、`JiangHuYeYuLu-iOS-unsigned-ipa`
3. 下载 artifact 解压，得到 `JiangHuYeYuLu.xcodeproj` 工程目录
4. 在任意一台 Mac（可借、可租云端 Mac）：
   ```bash
   unzip JiangHuYeYuLu-iOS-Xcode.zip
   open JiangHuYeYuLu.xcodeproj
   ```
5. Xcode → Signing & Capabilities → 勾选 Automatically manage signing → 选择 Team（免费 Apple ID 也可）
6. iPhone 连接 Mac → 选中设备 → Run。免费账号首次需在 iPhone：设置 → 通用 → VPN与设备管理 → 信任开发者证书
7. 免费证书 **7 天过期**，过期重跑一次即可；不想碰 Mac 的免费账号直接走**路线 C**；$99/年 开发者账号可走 TestFlight 长期分发（见附录）

## 路线 B：本机 Mac 全流程

```bash
# 0. 安装 Godot 4.7.2（macOS 版）与导出模板
#    模板放入 ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
# 1. 导入资源（生成字体/图标的 .imported 产物）
Godot.app/Contents/MacOS/Godot --headless --path <项目目录> --import
# 2. 导出
Godot.app/Contents/MacOS/Godot --headless --path <项目目录> --export-release "iOS" build/JiangHuYeYuLu.xcodeproj
# 3. Xcode 打开工程 → 签名 → 真机 Run；正式分发用 Product → Archive
```

## 路线 C：纯 Windows 全流程（无 Mac，个人使用推荐）

适用：只有 Windows 电脑 + 免费 Apple ID + iPhone + 数据线。
原理：GitHub 云构建产出**未签名 ipa** → Windows 上用 Sideloadly 免费签名并 USB 侧载，全程无需 Mac。

### C1. 推送仓库并触发云构建

1. 项目推到 GitHub（`.github/workflows/ios-build.yml` 已内置，push `main` 或手动 Run workflow 触发）
2. 等 `tests` 与 `export-ios` 两个 job 全绿（首次约 10-20 分钟）
3. 在 Artifacts 下载 `JiangHuYeYuLu-iOS-unsigned-ipa`（未签名 ipa），放到如 `build/` 目录
   （`JiangHuYeYuLu-iOS-Xcode` 是未签名 Xcode 工程，供路线 A 在 Mac 上签名用）

### C2. Windows 准备 Sideloadly

1. 安装 iTunes 与 iCloud（**Apple 官网直装版，不要微软商店版**——它们提供 iPhone USB 驱动），装完重启电脑
2. 官网 https://sideloadly.io 下载 Windows 版 Sideloadly 并安装
3. iPhone 数据线连接电脑，手机上点「信任此电脑」

### C3. 侧载安装

1. 把未签名 ipa 拖入 Sideloadly 窗口
2. Apple ID 栏填你的免费 Apple ID：
   - 未开启双重认证：直接用账号密码
   - 已开启双重认证（多数账号）：先在 appleid.apple.com → 登录与安全 → **App 专用密码**生成一个，填这个专用密码
3. Sideloadly 默认自动改写 bundle id（绕开占位符 `com.example.*`），无需手动改
4. 点 Start → 输入密码 → 等待签名与安装完成（手机保持解锁与亮屏）
5. iPhone：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
6. 回桌面启动游戏；云同步联调见下文「云同步真机联调」

### C4. 免费账号限制与续期

- 签名 **7 天过期**：过期后 App 打不开，重连电脑对同一 ipa 重签一次即续期（游戏进度走云同步，不受影响）
- 每个免费 Apple ID 同时最多 **3 个侧载 App**，7 天内最多注册 10 个 App ID
- 想自动续签可用 AltStore（同原理，同一 Wi-Fi 下自动后台刷新，但要求电脑常驻 AltServer）

## 附录：付费账号（$99/年）CI 自动 TestFlight（备用，未实装）

若有付费开发者账号，可在 `ios-build.yml` 追加签名 job，全程仍无需 Mac：

1. Apple Developer 后台：创建 iOS Distribution 证书（Keychain 导出 .p12）+ App Store 描述文件
2. App Store Connect → 用户和访问 → 集成 → 生成 API 密钥（.p8，记录 Issuer ID 与 Key ID）
3. GitHub 仓库 Settings → Secrets and variables → Actions 添加：
   `APPLE_CERT_P12`（p12 的 base64）、`APPLE_CERT_PASSWORD`、`APPLE_PROFILE`（描述文件 base64）、
   `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`（p8 的 base64）
4. job 内：证书导入临时钥匙串 → `xcodebuild -exportArchive`（exportOptionsPlist，method=app-store）出签名 ipa → `xcrun altool --upload-app` 上传
5. iPhone 装 TestFlight App 安装，90 天有效，无需数据线

（本文档不实装该 job；免费账号用户忽略本节即可。）

## 首次构建注意

- **bundle id 是占位** `com.example.jianghuyeyulu`——改成你自己的：Xcode Signing 页直接改，或编辑 `export_presets.cfg` 的 `application/config/bundle_identifier`
- 若导出报"选项缺失/不识别"：用 Godot 编辑器打开项目 → 项目 → 导出 → 选中 iOS → 逐页确认（编辑器会自动补全/规范 preset 键，不同小版本键名有差异）
- 横屏在预设（orientation）与 `project.godot`（sensor_landscape）双重声明，无需改动
- 图标不显示：确认 `assets/icons/icon_1024.png` 存在且 preset 的 `icons/icon_1024` 指向它（重新生成：`.zcode/tools/gen_icon.gd`）

## iOS 端操作方式

- 左下虚拟方向键移动；右下 交互 / 行囊 / 炼制 / 保存 按钮（键位与桌面一一对应）
- 行囊 → 云同步页签：配置服务器、注册、上传、下载、冲突裁决
- 标题页「云同步」：新设备首次拉取进度

## 云同步真机联调

- 真机与服务器同一 Wi-Fi：填电脑**局域网 IP**（`ipconfig` 查 IPv4），如 `http://192.168.1.5:8787`；Windows 防火墙放行 Node
- 真机走蜂窝网络：需公网可达（云主机或内网穿透），**务必加 HTTPS 反代**——详见 [server/README.md](../server/README.md)
