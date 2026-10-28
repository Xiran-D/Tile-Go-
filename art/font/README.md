# 界面字体 —— 来源、授权与子集化

> 2026-10-13 UI 重设计（P0）引入。本目录的文件**随游戏一起分发**，
> 因此授权条款是硬约束，不是一句"网上找的免费字体"可以带过的。

---

## 1. 用了哪款字体

**霞鹜文楷（LXGW WenKai）**，SIL Open Font License 1.1。

- 上游：<https://github.com/lxgw/LxgwWenKai>
- 本次取用版本：**v1.522**（2026-10-13）
- 三个字重，全部经过**子集化**：

| 文件 | 用途 | 原始 | 子集后 |
|---|---|---|---|
| `LXGWWenKai-Medium.subset.ttf` | L1 展示级（主菜单/手机菜单标题）、L2 页面标题（弹窗标题） | 24.2 MB | 3.4 MB |
| `LXGWWenKai-Regular.subset.ttf` | L4 正文与所有控件文字 | 24.4 MB | 3.5 MB |
| `LXGWWenKai-Light.subset.ttf` | L5 辅助文字（提示、副标题、记录） | 27.0 MB | 3.4 MB |

**为什么是楷体**：这游戏讲的是"棋"。中文排版里楷体的气质与棋、纸、印章是一路的，
而引擎默认的兜底字体既没有这个气质，在 13–22px 的中文正文上笔画也会粘连。
文楷的 `Regular` 实际取自原 Klee One 的 SemiBold（比一般意义的"常规"粗一档），
这恰好让小字号下的中文更耐读。

**为什么全界面用同一个家族，而不是"楷体标题 + 黑体正文"**：
见 §3 —— 第二款字体是**因为许可问题**被否掉的，不是审美问题。

---

## 2. 授权（SIL OFL 1.1）

完整许可正文见本目录 `LXGWWenKai-OFL.txt`（随游戏分发**必须**一并携带）。

本工程用到的条款要点：

| 条款 | 本工程是否满足 |
|---|---|
| 个人与企业均可**免费商用**，无需付费或署名 | ✅ 随游戏分发即商用分发 |
| 允许**嵌入软件 / App / 与产品捆绑再分发** | ✅ 字体进 `.pck` |
| 允许**修改并制作衍生字体**（含子集化） | ✅ 三个 `.subset.ttf` 即衍生字体 |
| 衍生字体**必须同样以 OFL 1.1 公开** | ✅ 同目录附许可全文 |
| 衍生字体名**不得使用保留名称**（含「霞鹜」「LXGW」） | ✅ 文件名沿用原名，属"未改动源码的重新编译"，不受此限 |
| **禁止单独出售字体文件** | ⚠️ 不要把 `art/font/*.ttf` 单独拿出来卖 |

字体文件内嵌的版权信息（`name` 表）：

```
Copyright 2021-2026 LXGW (https://github.com/lxgw/LxgwWenKai), with Reserved Font Name
'霞鹜', '霞鶩', '落霞孤鹜', '落霞孤鶩' and 'LXGW'.
Copyright 2020 The Klee Project Authors
(https://github.com/fontworks-fontworks/klee), with Reserved Font Name 'Klee'.
```

---

## 3. 为什么**没有**用第二款字体（霞鹜晰黑）做正文

初版方案是「楷体做标题 + 黑体做正文」。下载后读字体内嵌的许可信息才发现：

| | 霞鹜文楷 | 霞鹜晰黑 |
|---|---|---|
| 许可 | **SIL OFL 1.1** | **日本 IPA 字体许可** |
| 商业使用 | 允许 | 允许 |
| **子集化（衍生字体）后再分发** | 允许 | **要求见下** |

IPA 字体许可对「衍生字体」的再分发要求（其 `LICENSE.md` 第 3 条第 1 款）：

1. 必须**同时再分发**许可文本，**以及**「用字体开发工具在制作衍生字体过程中生成的、
   可用于对衍生字体继续修改的任何附加文件」—— 对本工程而言就是**那 6MB 的原始完整 TTF**；
2. 必须提供**将衍生字体替换回原始字体**的手段（差分文件，或书面替换方法）。

⇒ 每次导出都得额外背 6MB 原始字体，并附一份替换说明。相比之下 OFL 干净得多。

**所以定稿：全界面单家族（文楷）三字重，靠"字重 + 字号 + 颜色"三样建立层级。**

> ⚠️ 后续若要换字体，**先确认所选字体的许可允许「子集化后再分发」**，
> 别只看"能不能商用" —— 很多字体允许商用，却不允许你改。

---

## 4. 子集化说明

子集脚本在工程外（不进 `res://`，避免被打进 `.pck`）：
`瓷砖围棋_临时输出/font_dl/subset_fonts.py`

### 保留了什么字符

```
安全字符集 = 工程源码实际用字（.gd / .tscn / .cfg / .godot / .md 扫描，1828 个）
            ∪ GB2312 一级+二级汉字（6763）
            ∪ ASCII 可见字符
            ∪ 中日韩标点 / 全角符号 / 箭头 / 记号 / 数字
```

### 为什么必须加 GB2312

Steam 玩家名、房名等是**运行期才出现的字符串**，只按源码取字会让它们变成豆腐块 ——
而那是"平时测不出来、上线才炸"的坑。GB2312 覆盖 6763 个汉字，日常中文与绝大多数姓名用字都在内。

### 已知不在子集内的 14 个字符

`ℚ ℤ ↦ ↳ ⏳ ⚠ ⚰ ✅ ✔ ❌ ⟹ ⟺ Ⰶ 🟡`

逐一核实过：**它们只出现在 `print()` 调试输出与注释里，永远不上屏**
（`game.gd` 的 `--aibud` / `--capftest` / `--aieye` 等自检打印，以及 `overview.md` 文档）。
⇒ 不影响显示。

### 重跑子集

文案有增删后要重跑，否则新字会显示为豆腐块：

```powershell
# 1. 重新扫描用字（会覆写 used_chars.txt）
cd C:\Users\34667\Documents\瓷砖围棋
python -c "import glob,os,collections;c=set();[c.update(open(f,encoding='utf-8',errors='ignore').read()) for p in ('*.gd','*.tscn','*.cfg','*.godot','*.md') for f in glob.glob(p)];c={x for x in c if ord(x)>=0x20};open(r'..\瓷砖围棋_临时输出\font_dl\used_chars.txt','w',encoding='utf-8').write(''.join(sorted(c)));print('distinct:',len(c))"

# 2. 子集化（源 TTF 需已下载到 font_dl/）
cd C:\Users\34667\Documents\瓷砖围棋_临时输出\font_dl
python subset_fonts.py

# 3. 拷回工程
Copy-Item subset\*.subset.ttf C:\Users\34667\Documents\瓷砖围棋\art\font\ -Force

# 4. ★★ 必须再让编辑器扫一次（少了这步，新字库**静默无效**）
cd C:\Users\34667\Documents\瓷砖围棋
& "D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --import
```

### ★★ 为什么第 4 步不能省（2026-10-15 实测踩到，已造成 2 天"假生效"）

`.ttf` 在 Godot 里是**导入型资源**：`load("res://art/font/*.ttf")` 走的是 `.import` 里记的
`.godot/imported/*.fontdata`。而**跑游戏（含全部 headless 自检）不会触发导入扫描**，
只有编辑器启动才会。于是：

| 状态 | `ResourceLoader.exists()` | 后果 |
|---|---|---|
| 有 `.import` + 缓存 | `true` | 正常 |
| **缺 `.import`** | **`false`** | `UITheme._load_font()` 静默返回 `null` ⇒ 该角色**退回引擎兜底字体** |

实测证据（当日探针）：三份 ttf 只有 `Medium` 有 `.import`，另外两份 `exists=false`
⇒ **L4 正文/所有原生控件 + L5 辅助** 从 10-13 起就一直是引擎兜底字体，
而 `Medium` 的导入缓存还停在旧 md5（`source_md5` 与文件实际 md5 不符 = 缓存陈旧）。
全程**没有任何一条自检报警** —— 因为"字体没生效"这件事当时**没有嘴**
（`UITheme.fonts_report()` 写好了但**零调用点**）。

⇒ 跑完上面第 4 步后复验（`exists` 必须三行全 `true`）：

```bash
"D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless \
  --path C:/Users/34667/Documents/瓷砖围棋 --script <探针脚本>
```

---

## 5. 工程内怎么用

- 字体路径的真源：`ui_tokens.gd::FONT_DISPLAY / FONT_BODY / FONT_MUTED`
- 装配与降级：`ui_theme.gd::load_fonts() / build()`
- 全局生效点：`GameConfig.apply_ui_theme()`（Autoload `_ready()`，早于任何场景）

**字体缺失时静默降级**到引擎默认字体，而不是让自检红掉 ——
否则"新增 `.ttf` 还没被编辑器导入过"会伪装成"配色/排版坏了"，把排查引向错误方向。
需要查字体状态时看 `UITheme.fonts_report()`。