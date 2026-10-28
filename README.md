# 瓷砖围棋 · Tile Go

在**非周期密铺**棋盘上下的围棋。没有角，没有边，每一格的邻居数都不一样。

单人机对战，Windows 免安装，MIT 开源。约 5.7 万行 GDScript（Godot 4.7）。

![主菜单](docs/screenshot-menu.png)

![对局](docs/screenshot-board.png)

---

## 下载即玩

到 [Releases](../../releases) 下载 `TileGo-windows-x64.zip`，解压，双击 `TileGo.exe`。

- Windows 10/11 64 位，无需安装引擎
- 存档在 `%APPDATA%/Godot/app_userdata/瓷砖围棋/`

### 这个版本刻意砍掉了什么

| 砍掉 | 原因 |
|---|---|
| 联机对战 | 依赖 Steam SDK，要账号体系与大厅服务 |
| 棋谱 / 复盘 | 完整版功能，与"下一盘棋"无关 |
| 主题切换 | 只留一套「经典」配色（宣纸） |

留下的是：**棋盘 + 规则 + AI**。完整版（12 套主题、棋谱复盘、Steam 联机）留给 Steam 版。

## 有什么

| 盘型 | 结构性来源 |
|---|---|
| 彭罗斯 | Penrose P3 菱形密铺（Robinson 三角形替换法生成） |
| 立方体 | 每 3 块菱形拼成正六边形，再排成蜂窝大盘 |
| 筝形 | 每 3 块筝形钝角相对拼成等边三角形，三角形再密铺 |
| 雪花 | Ammann–Beenker 密铺（八格网对偶），盘心 8 块锐角共点 |
| 爱因斯坦 | 帽子 / 海龟 / 幽灵（单瓦片非周期密铺），替换系统迭代生成 |

每种盘型三档大小：随机（每局现场生成，约 200 格）/ 标准（约 120 格）/ 加强（约 360 格）。

规则照围棋来：气、连通块、提子、打劫、超级劫、数子。邻接按**共享边**定义 —— 所以"一眼"的形状是三角形/四边形/五边形混着的，方格盘上的棋形直觉到这里全部失效。

四个 AI 对手：

| 名字 | 是什么 |
|---|---|
| 磐石 | 主引擎，MCTS + 启发式评估（三档难度） |
| 疾风 | 更激进的变体 |
| 流水 | 另一套搜索结构，用于交叉验证 |
| 野马 | 神经网络评估（自训练权重，`ai/yema_weights.json`） |

---

## 🎯 来做这个 AI 吧

这是我把游戏开源出来的**主要原因**。

它的棋力大约业余级，而我很清楚它卡在哪 —— 该撞的墙我都撞过了，数据和结论都留在这个仓库里。你需要的东西全在：

| 你要的 | 在哪 |
|---|---|
| 主引擎 | `ai_engine.gd`（约 5200 行）MCTS + 启发式评估 + 策略性 rollout |
| 所有旋钮 | 同一文件顶部的 `@export`，每个都是运行期可调参数 |
| 变体引擎 | `ai_engine_liushui.gd` / `ai_engine_yema.gd` |
| 神经网络雏形 | `nn_score.gd` + `ai/yema_weights.json` + `ai/yema_golden.json` |
| 自弈 / A-B 仪器 | `game.gd` 里的 `--aispec` / `--aiprof` / `--aibud` |

### 五分钟上一次实验

```bash
# 两个版本的引擎互下 16 局（自动换色配对），只差一个参数
godot --headless --path . -- --aispec=r16:pw100:a=count_prisoners=false:b=count_prisoners=true
```

`a=` 与 `b=` 各是一组"参数名=值"的覆盖（多组用 `,` 分隔），冒号分隔 token。跑完直接给胜率、目差、时间比。可复现（有种子）、可配对（同局换色），不用手工摆棋。

### 我先替你把死路标出来

以下是我实测过的结论，**别再花时间**：

- **算力已经饱和。** 时间预算 200ms → 400ms（多花 1.64× 时间），32 局换色打 **16:16**。加线程同理（53.1%，z=0.35）。
- **评估里"影响/势力"那一项是承重墙。** 关掉它胜率掉到 **15.6%**（单线程 80.6% / 生产口径 84.4%，两批独立种子一致）。别动它。
- **死子修正闸门、提子奖励、全盘扫描** 三样都试过，A/B 全是噪声（提子项合并 56 局 z=−0.27），默认值已是最优。
- **评估半径**（影响扩散距离）四个方向全试完：7 格最优，收窄或放大都只有害处。

真正剩下的只有一件事：**评估函数的"形状"** —— 不是算力、不是噪声、不是搜索宽度。

### 我会想看的方向

1. **换搜索形态。** 120 格的小盘上 MCTS 未必是对的答案 —— 我有一条旧观察说它打不过 90ms 的贪心。要是你能证明这一点，这个仓库值得改写。
2. **学习型先验。** 现有 `yema` 权重是自己训的，历史上没超过手调启发式。问题可能出在"指标选错"（拿 val loss 当棋力代理，而两者可能反向），不是模型不行。
3. **更好的终局评估。** 现在数子口径很朴素。
4. **任何能让评估更懂密铺棋形的东西。** 这是这盘棋真正有意思的地方。

### 提交前请读这一句

**16 局不足以定结论。** 8 局换色配对的 95% 置信区间大约是 **[38%, 82%]** —— 你会先看到"68.8% 大胜"，下一批掉回 43.8%。

**要报结论：至少三批独立种子，|z| ≥ 3 且目差同向。**

---

## 从源码跑

需要 **Godot 4.7.2**（GL Compatibility，无 C#、无编译步骤）。

```bash
git clone https://github.com/<你的账号>/<仓库名>.git
cd 瓷砖围棋
godot --path .
```

主场景 `menu.tscn`；直接进对局：`godot --path . res://game.tscn`。

仓库**不含 Steam SDK**（`addons/godotsteam/`、`steam_api64.dll` 已在 `.gitignore` 排除）。`steam_net.gd` 全程反射调用，插件缺失时只是 `is_available()` 返回 false，游戏照常运行 —— 精简版本就不显示联机入口。

## 构建发布包

打 tag 触发 GitHub Actions 自动导出并附到 Release：

```bash
git tag v0.8.0 && git push origin v0.8.0
```

本地手动导出（需先在编辑器装好 4.7.2 导出模板）：

```bash
godot --headless --path . --export-release "Windows Desktop (Lite)" dist/TileGo.exe
```

预设 `Windows Desktop (Lite)` 带 `custom_features="lite"`，这是精简版的唯一开关（见 `game_config.gd` 的 `lite` 字段）。

## 目录

```
game.gd                 对局主逻辑（渲染 / 落子 / 动画 / 自检入口）
rules_kernel.gd         规则内核（气 / 块 / 提子 / superko / 数子）
ai_engine.gd            主 AI（MCTS + 启发式）★ 想改 AI 从这里开始
ai_engine_liushui.gd    流水变体
ai_engine_yema.gd       野马（学习型评估）
nn_score.gd             神经网络前向与特征
menu.gd                 主菜单（瓷砖式布局，自绘）
game_config.gd          全部可调参数与存档（含 lite 开关）
music.gd                程序化音乐合成（无音频文件，实时生成）
themes/                 主题 .tres（精简版只用 00_宣纸）
art/font/               霞鹜文楷子集（OFL 1.1）
ai/                     野马权重与 golden 基准
```

## 已知限制

- 只有 Windows 预设，Linux/macOS 需自行加导出预设
- AI 是业余级，不追求段位强度
- 移动端竖屏布局已暂停开发

## 授权

代码 MIT，见 [LICENSE](LICENSE)。

随包字体 **霞鹜文楷 LXGW WenKai**：SIL Open Font License 1.1，详见 `art/font/README.md`。

引擎 **Godot Engine** 4.7.2：MIT。
