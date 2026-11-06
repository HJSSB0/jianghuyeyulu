# 江湖夜雨录

> 大侠立志传式重制 · Godot 4.7
> 调研拆解 → 融合切片 → 双端互通 → 2.5D 重绘 → 世界观圣经 + 水墨美术 + ATB 战棋 → **v0.5 人际四层网 + 内容扩张**。

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
| 战棋战斗 | 大侠立志传 | **9×7 网格走位**：ATB 集气定行动，就绪获「移动力（轻功加成）+一次行动」；侧击+15%/背击+25%；招式带射程（邻格/横扫/突进）；支持自动战斗 |
| 战意系统 | 大侠立志传 | 攻受击积攒：100 放绝招、200 必爆 |
| 阵法（光环化） | 烟雨江湖（改造） | 战前布阵全队光环：天罡增伤减伤 / 流云集气 / 四象回血 |
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
| **人际四层网** | 大侠立志传 | **送礼**（每个 NPC 有至爱/喜欢/厌恶，按礼签判定）→ 好感阈值奖励（传功/赠财）→ **门派贡献晋升**（贡献达标掌门亲传甲乙武学）→ **名声门槛**（甲级悬赏需名声 25、乙级 10） |

**移动（双轨制）**：WASD/方向键 8 向平滑移动（带摄像机跟随）＋ 鼠标点击/触屏点按 A\* 寻路（点 NPC 自动走到面前；键盘随时接管）
**操作（桌面）**：WASD/方向键或点击地面移动 · E/空格 交互 · M 行囊 · C 炼制 · F5 保存 · 大地图点击行进
**操作（触屏/iOS）**：点按地面寻路（虚拟方向键在触屏设备自动出现）· 右下 交互/行囊/炼制/保存 按钮
**战斗（战棋）**：选招式 → 点蓝格走位（消耗移动力）→ 点红格出手 · 键盘光标+E 亦可

## v0.4 程序化水墨美术（零外部素材）

全部画面**纯代码绘制**：32px 斜45° 像素场景（瓦顶民居/竹林/山崖/水墨山门）、16×24 四向像素角色、
宣纸卷轴 UI（墨线双边框+朱砂印+木牌按钮）、水墨标题/结局/大地图画幅，OFL 书法字体
（Ma Shan Zheng）+ Noto Sans SC 内嵌。风格基准：《大侠立志传》公开画面 + 本作圣经意象（雨·月·灯）。

- 世界观与文案的唯一锚点：[docs/05-背景故事·世界观圣经.md](docs/05-背景故事·世界观圣经.md)
- 美术风格契约：[docs/06-美术风格规范.md](docs/06-美术风格规范.md)（色板/构图/程序化实现契约）
- 字体许可：[assets/CREDITS.md](assets/CREDITS.md)（均为 OFL，可入库分发）

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
# headless 逻辑回归（139 项断言：含战棋走位/朝向加成/阵法光环/送礼/阈值/贡献/名声门槛）
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/run_tests.gd
# 移动/寻路回归（30 项断言：A*、防穿角、步进引擎、拾取、归位）
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/test_movement.gd
# 云同步端到端（18 项断言；先启动服务器：node server/save_server.mjs）
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/test_cloudsync.gd
# 截图巡检（生成 .zcode/shots/*.png 14 张，含移动回归 MOVECHECK 与触屏 HUD）
.tools/Godot_v4.7.2-stable_win64_console.exe --path . --script .zcode/tests/screenshot_tour.gd
```

## 文档

- [docs/01-调研拆解对比.md](docs/01-调研拆解对比.md) —— 两款游戏五模块系统化拆解对比 + 弱点规避清单
- [docs/02-融合设计方案.md](docs/02-融合设计方案.md) —— 25 项融合决策映射、架构、循环、数值框架
- [docs/03-iOS构建与签名指南.md](docs/03-iOS构建与签名指南.md) —— 云构建/纯 Windows 侧载（路线 C）/Mac 本地导出/TestFlight 附录

## 项目结构

```
project.godot          Godot 4.7 配置（960×540、横屏、InputMap 动作、触屏模拟）
autoload/              EventBus / GameDB / GameState / Battle(战棋引擎) / SaveSystem(v2) / CloudSync
data/*.json            38 武学 · 66 物品 · 35 NPC(礼签/阈值) · 29 任务(甲乙丙悬赏+烟波支线) · 18 敌人 · 11 奇遇 · 8 经脉 · 4 阵法(光环) · 10 地图
docs/05/06             世界观圣经（剧情文案锚点）· 美术风格规范（色板/构图契约）
scenes/main.gd         视图状态机 Title→Create→World⇄Town⇄Battle→Ending
scenes/views/battle_view.gd  9×7 战棋战场（范围高亮/双轨操作/ATB）
scenes/views/town_view.gd    双轨移动引擎 + Y 排序 2.5D 渲染 + 摄像机
scenes/views/world_view.gd   宣纸水墨大地图（道路行进/时辰/遭遇）
scripts/art/           程序化美术：pixel_world(场景) / pixel_char(角色) / ink_paint(画幅) / art_lib(枢纽)
scripts/ui_theme.gd    宣纸卷轴主题（墨线双边框/朱砂印/木牌按钮/书法标题字）
scripts/pathfinding.gd 网格 A*（战斗走位与大地图/城镇寻路共用）
assets/fonts/          NotoSansSC（OFL）+ MaShanZheng（OFL 书法体）
assets/CREDITS.md      字体许可（零外部素材）
server/ .github/ .zcode/tests/   云存档 · iOS 云构建 · 回归/巡检
```
