# 瓷砖围棋 · Tile Go

在**非周期密铺**棋盘上下的围棋。没有角，没有边，每一格的邻居数都不一样。

用 Godot 4.7 写的个人项目，约 5.7 万行 GDScript。棋盘不是网格，而是由菱形、筝形、帽子等瓷砖拼成的密铺 —— 落子点就是瓷砖本身，气与连通块按「共享边」定义，其余规则照围棋来。

![主菜单](docs/screenshot-menu.png)

![对局](docs/screenshot-board.png)

---

## 下载即玩

到 [Releases](../../releases) 下载最新 `TileGo-windows-x64.zip`，解压，双击 `TileGo.exe`。

- 平台：Windows 10/11 64 位
- 免安装，无需 Godot 引擎
- 存档与棋谱在 `%APPDATA%/Godot/app_userdata/瓷砖围棋/`

## 有什么不一样

| 盘型 | 结构性来源 |
|---|---|
| 彭罗斯 | Penrose P3 菱形密铺（Robinson 三角形替换法生成） |
| 立方体 | 每 3 块菱形拼成正六边形，再排成蜂窝大盘 |
| 筝形 | 每 3 块筝形钝角相对拼成等边三角形，三角形再密铺 |
| 雪花 | Ammann–Beenker 密铺（八格网对偶），盘心 8 块锐角共点 |
| 爱因斯坦 | 帽子 / 海龟 / 幽灵（单瓦片非周期密铺），替换系统迭代生成 |

每种盘型都有「随机 / 标准 / 加强」三档大小。随机盘每局现场生成，约 200 格。

**四个 AI 对手**

- **磐石** —— 主引擎，MCTS + 启发式评估，三档难度（简单 / 普通 / 困难）
- **疾风** —— 变体，更激进
- **流水** —— 另一套搜索结构，用于交叉验证
- **野马** —— 神经网络评估（自训练权重，`ai/yema_weights.json`）

**其他**

- 本地双人 / 人机 / 联机（联机需要 Steam 版，见下）
- 棋谱记录与回放，标准 JSON 格式
- 图模式：把棋盘画成落子点连线的对偶图
- 12 套配色主题，明度与对比度受硬性约束
- 程序化生成的背景音乐（无音频文件，全部实时合成）

## 从源码跑

需要 **Godot 4.7.2**（GL Compatibility 渲染，无需 C#／无需编译）。

```bash
git clone https://github.com/<你的账号>/<仓库名>.git
cd 瓷砖围棋
godot --path .
```

主场景是 `menu.tscn`；直接进对局可用 `godot --path . res://game.tscn`。

**注意**：本仓库**不含 Steam SDK**。`addons/godotsteam/`、`steam_api64.dll`、`steam_appid.txt` 已在 `.gitignore` 中排除。
`steam_net.gd` 全程用反射调用 Steam 接口，插件缺失时 `is_available()` 返回 `false`，游戏照常运行，点「对弈」只会弹一句「Steam 不可用」，不会崩。

想自己接联机：从 [GodotSteam](https://github.com/GodotSteam/GodotSteam) 取对应版本放进 `addons/godotsteam/`，并在工程根放 `steam_appid.txt`。

## 构建发布包

打 tag 会触发 GitHub Actions 自动导出并附到 Release：

```bash
git tag v0.9.0 && git push origin v0.9.0
```

本地手动导出（需先在编辑器里装好 4.7.2 导出模板）：

```bash
godot --headless --path . --export-release "Windows Desktop" dist/TileGo.exe
```

导出预设用 `embed_pck = true`，产物是单文件 exe。

## 目录

```
game.gd           对局主逻辑（渲染 / 落子 / 动画 / 自检入口）
rules_kernel.gd   规则内核（气 / 块 / 提子 / superko / 数子）
ai_engine.gd      主 AI（MCTS + 启发式）
ai_engine_*.gd    疾风 / 流水 / 野马变体
menu.gd           主菜单（瓷砖式布局，自绘）
game_config.gd    全部可调参数与存档
music.gd          程序化音乐合成
record.gd / replay.gd  棋谱
steam_net.gd      Steam 门面（反射调用，可缺）
themes/           12 套主题 .tres
art/font/         霞鹜文楷子集（OFL 1.1）
ai/               野马权重与 golden 基准
```

## 已知限制

- 联机依赖 Steam，Steam 版才能用；开源版这块是灰的
- 只有 Windows 预设（Linux / macOS 需自行加导出预设，引擎侧没做特殊适配）
- 移动端竖屏布局已暂停开发
- AI 棋力约业余级，不追求段位强度

## 授权

代码 MIT，见 [LICENSE](LICENSE)。

随包字体 **霞鹜文楷 LXGW WenKai**：SIL Open Font License 1.1，条款与子集化说明见 `art/font/README.md` 与 `art/font/LXGWWenKai-OFL.txt`。

引擎 **Godot Engine** 4.7.2：MIT。
