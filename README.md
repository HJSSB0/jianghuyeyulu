# 江湖夜雨录

> 大侠立志传 × 烟雨江湖 融合复刻 · Godot 4.7 垂直切片
> 调研拆解 → 系统对比 → 融合设计 → 代码实现 → **双端互通（Windows ↔ iOS）** 的完整交付。

## 运行方式

**方式一（推荐）**：双击启动
```
.tools/Godot_v4.7.2-stable_win64.exe   （打开后选择本项目文件夹打开并 F5 运行）
```
**方式二**：命令行直接运行
```
.tools/Godot_v4.7.2-stable_win64_console.exe --path . 
```

## 玩法速览（约 1-2 小时内容）

| 系统 | 来源 | 说明 |
|---|---|---|
| 开局构建 | 大侠立志传 | 五维 15 点分配 + 武器四选一 + 特性 Roll（可重掷一次） |
| 九宫格战斗 | 烟雨江湖 | 上中下三路 × 前中后三列；近战打对位、突进直取后排 +25% |
| ATB 时序条 | 大侠立志传 | 身法决定集气速率，先手与连动博弈；支持自动战斗 |
| 战意系统 | 大侠立志传 | 攻受击积攒：100 放绝招、200 必爆 |
| 阵法 | 烟雨江湖 | 梅花/天罡/流云/四象，按站位给全队加成 |
| 武学三件套 | 烟雨江湖 | 套路+内功+轻功各装备一门；品级 丁/丙/乙/甲 × 五重境界 × 修为突破 |
| 经脉 | 烟雨江湖 | 8 条经脉每条顺通/逆通二择一；真气随游戏内时辰恢复（无现实时间墙） |
| 品格三维 | 大侠立志传 | 仁/义/勇 ±100，联动结局 |
| 时辰系统 | 两者 | 十二时辰驱动黑市营业（子丑）、醉侠出现（戌亥子）、护法现身（酉后） |
| 采集/炼制 | 两者 | 钓鱼/采药/挖矿/伐木 + 炼丹烹饪，资源点按时辰恢复 |
| 悬赏/奇遇 | 大侠立志传 | 告示板甲乙丙悬赏 + 11 个多条件奇遇 |
| 门派 | 大侠立志传 | 铁剑门/伏虎禅寺/烟波楼，入门试炼+镇派武学+可退门 |
| 多结局 | 大侠立志传 | 第一章三结局：入世/出世/沉沦，按品格+武学+选择分支 |

**操作（桌面）**：WASD/方向键移动 · E/空格 交互 · M 行囊 · C 炼制 · F5 保存 · 点击大地图行进
**操作（触屏/iOS）**：左下虚拟方向键移动 · 右下 交互/行囊/炼制/保存 按钮（与键位一一对应）

## 双端互通（Windows ↔ iOS）

- 云存档同步：存档为纯 JSON（v2，含时间戳/设备名元数据），REST 上传/下载
- 服务器：`server/save_server.mjs`（Node ≥18 零依赖单文件）；双击 `server/start_server.bat` 启动（默认 8787）
- 游戏内入口：标题页「云同步」拉取进度；行囊 → 云同步页签 注册/上传/下载
- 冲突裁决：时间戳新者胜；两端接近（≤2 分钟）时由玩家二选一
- 自动同步：配置过账号后，每次保存自动上传；云端较新时不覆盖并提示
- 部署（局域网/公网/HTTPS）：[server/README.md](server/README.md)

## iOS 端

- 同一套 Godot 工程：触屏虚拟按键 + 内嵌 Noto Sans SC 中文字体 + 横屏（sensor_landscape）
- 无 Mac 也可全流程：GitHub Actions 云构建出**未签名 ipa** → Windows 上 Sideloadly 免费签名侧载（7 天续签）；有 Mac 走 Xcode 签名：[docs/03-iOS构建与签名指南.md](docs/03-iOS构建与签名指南.md)（路线 C / 路线 A）
- 桌面调试触屏：环境变量 `JH_TOUCH=1` 强制显示虚拟按键；鼠标模拟触屏已开启（emulate_touch_from_mouse）

## 测试与验证

```
# headless 逻辑回归（107 项断言）
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/run_tests.gd
# 云同步端到端（18 项断言；先启动服务器：node server/save_server.mjs）
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/test_cloudsync.gd
# 截图巡检（生成 .zcode/shots/*.png 13 张，含触屏 HUD 与云同步页签）
.tools/Godot_v4.7.2-stable_win64_console.exe --path . --script .zcode/tests/screenshot_tour.gd
```

## 文档

- [docs/01-调研拆解对比.md](docs/01-调研拆解对比.md) —— 两款游戏五模块系统化拆解对比 + 弱点规避清单
- [docs/02-融合设计方案.md](docs/02-融合设计方案.md) —— 25 项融合决策映射、架构、循环、数值框架
- [docs/03-iOS构建与签名指南.md](docs/03-iOS构建与签名指南.md) —— 云构建/纯 Windows 侧载（路线 C）/Mac 本地导出/TestFlight 附录

## 项目结构

```
project.godot          Godot 4.7 配置（960×540 像素风、横屏、触屏模拟）
autoload/              EventBus / GameDB / GameState / Battle / SaveSystem(v2) / CloudSync
data/*.json            30 武学 · 64 物品 · 35 NPC · 21 任务 · 18 敌人 · 11 奇遇 · 8 经脉 · 4 阵法 · 13 地图
scenes/main.gd         视图状态机 Title→Create→World⇄Town⇄Battle→Ending
scenes/views/*.gd      各视图 + 交互面板 + touch_controls（虚拟方向键/动作按钮）
scripts/art/           程序化像素美术（tile/角色/头像/标题画，零外部素材）
scripts/ui_theme.gd    暗色水墨主题（内嵌 Noto Sans SC + 系统字体回退链）
assets/fonts/          NotoSansSC-Regular.otf（OFL 开源许可，跨平台中文渲染）
assets/icons/          icon_1024.png（iOS 图标，程序化生成：.zcode/tools/gen_icon.gd）
server/                save_server.mjs + start_server.bat + 部署指引
export_presets.cfg     iOS 导出预设（bundle id 占位，首次构建时改）
.github/workflows/     测试与 iOS 云构建（macOS runner）
.zcode/tests/          headless 回归 + 云同步端到端 + 截图巡检
```
