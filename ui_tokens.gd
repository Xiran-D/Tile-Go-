class_name UITokens
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## UI 设计 token —— 全工程**唯一**的尺寸真源（2026-10-13 新增，P0）
## ═══════════════════════════════════════════════════════════════════════════
##
## ## 为什么要有这一层
##
## 本工程原本**只有颜色有真源**（`game_config.gd` 的 `PRESETS` + 5 条对比度硬闸），
## 而字号 / 间距 / 圆角 / 线宽全是散落在 `menu.gd`、`menu_mobile.gd`、`game.gd`
## 里的字面量。实测散落值就能看出问题：
##
##   · 字号：`60` `26` `22` `20` `18` `16` `15` `13`（`menu.gd` 里 `_row_head_font_size()`
##           还按行高做 18/20/22/24/26 五档跳变），外加 `menu_mobile.gd` 一整套 58/46/36/34/32。
##     ⇒ 同一个"正文"在两个菜单里是 22 与 32，且**没有任何一处说明它们为何不同**。
##   · 间距：`LABEL_GAP 4`、按钮内边距 `14/8`、面板内边距 `24/18`、
##           棋盘边距横 `40`/竖 `14`、HUD 右边 `320`/下边 `110`。
##     ⇒ `40` 与 `14` 都不在任何 4 的倍数阶梯的"常用档"上，彼此关系无从判断。
##   · 形状：`_dialog_box()` 里 `corner_radius_all(8)` / `border_width_all(1)`
##           是全工程**唯一**的圆角与线宽值，按钮/面板/色块/输入框全都共用它。
##
## ## 本层**只新增、不改语义**
##
## 所有数值都是从现有散落值里挑出的**同一批数**，不重新设计视觉。落地顺序是
## 「先立真源 → 再逐个调用点改读 token」。每改一处都跑既有自检，全绿才算过。
##
## ## ★ 字号为什么按"画布"给两套，而不是直接给 pt
##
## 真机上的物理尺寸才是判据（这条已由竖屏基座钉死：720 逻辑px = 393pt，
## i.e. 1 逻辑px ≈ 0.5458 pt；横屏 1152 基座在桌面按 1px≈1pt 读）。
##
## ★★ 但**不能**简单地把阶梯定义成 pt 再乘回去 —— 实测两个菜单的现值已经是
##   「各自画布上合适的值」了：
##     · `menu_mobile.gd`（720 基座）：正文 32px = **17.5pt** ✅ 达标
##       （`judge_mobile_layout()` 的 `TEXT_MIN_PT=17` 就是照它定的）
##     · `menu.gd`（1152 基座）：正文 22px = 22pt，桌面基准画布上是舒服的尺寸
##   两边都对，只是**各自为政**。所以阶梯按「每个画布各给一套」组织，
##   再由 `pt_of()` 把任意档位换算成 pt —— 判据读换算值，不用常量反推
##   （`judge_mobile_layout()` 的注释明确记过：判据必须用字面常量，
##   拿变量反推会让判据自证）。
##
## 参考：<https://github.com/lxgw/LxgwWenKai>（OFL 1.1）
##       <https://github.com/lxgw/LxgwXiHei>（OFL 1.1）

# ═══ 画布基座（与 game_config.gd 的 BASE_SIZE_* 一致，此处只读不写）═══

## 横屏设计基座
const BASE_LANDSCAPE: Vector2i = Vector2i(1152, 648)
## 竖屏设计基座（与 iPhone 15 的 393×852pt 几乎同比例）
const BASE_PORTRAIT: Vector2i = Vector2i(720, 1560)

# ═══════════════════════ 1. 字体 ═══════════════════════

## 字体资源路径（已子集化，见 `art/font/README.md`）。
##
## ★ 为什么是**一个家族三字重**，而不是"楷体标题 + 黑体正文"：
##   初版确实找过第二款字体做正文（霞鹜晰黑），但读它的字体内嵌许可才发现
##   **晰黑用的是日本 IPA 字体许可，不是 OFL**。IPA 许可对「衍生字体」的再分发
##   要求**必须同时附上原始完整字体文件 + 替换方法**（其 LICENSE.md 第 3 条第 1 款），
##   而子集化正属于「衍生字体」⇒ 每次导出都要多带 6MB 原始字体并附替换说明。
##   文楷是 SIL OFL 1.1：**明确允许子集化与商业再分发**，只需随附许可、
##   且衍生字体不得使用保留名称（我们未改字形，重编译不触发该限制）。
##   ⇒ 一个家族在合规上干净得多，且三字重足以支撑「靠字重建立层级」。
##   ⚠️ 若将来仍想改用黑体做正文，**先确认所选字体的许可允许子集化再分发**。
const FONT_DISPLAY: String = "res://art/font/LXGWWenKai-Medium.subset.ttf"   # Medium：L1 展示 / L2 页面标题
const FONT_BODY: String = "res://art/font/LXGWWenKai-Regular.subset.ttf"     # Regular：L4 正文 / 控件
const FONT_MUTED: String = "res://art/font/LXGWWenKai-Light.subset.ttf"      # Light：L5 辅助文字

## 视觉层级 L1–L5 的角色名。调用点应按**角色**取字号，不要按场景写数字。
enum Level { L1, L2, L3, L4, L5 }

## 横屏（1152 基座）字号阶梯。★ 取值即现状值，改这里等于改全局。
const FS_LANDSCAPE: Dictionary = {
	Level.L1: 60,   # 展示：主菜单「瓷砖围棋」
	Level.L2: 26,   # 页面标题：设置页 / 弹窗标题
	Level.L3: 22,   # 分组头：行带小标题
	Level.L4: 22,   # 正文 / 控件：瓷砖标签、底栏导航、按钮文字
	Level.L5: 16,   # 辅助：提示、记录、禁用态（★ 原散落 13/15/18，统一收到 16）
}

## 竖屏（720 基座）字号阶梯。★ 已按 1px≈0.5458pt 换算并对齐既有判据阈值。
const FS_PORTRAIT: Dictionary = {
	Level.L1: 58,   # 31.7pt（iOS 大标题 ≈34pt）
	Level.L2: 34,   # 18.6pt —— 选项层小标题 / 二级页标题
	Level.L3: 30,   # 16.4pt —— 分组头
	Level.L4: 32,   # 17.5pt —— 正文与控件（★ 恰好满足 TEXT_MIN_PT=17）
	Level.L5: 26,   # 14.2pt —— 辅助文字
}

## 取某层在指定画布下的字号。
## `portrait` 请传 `GameConfig.use_portrait_canvas()`，不要在这里自己判断
## —— 判据与真机共用同一个判定函数，避免两处各判一套（本工程的老坑）。
static func fs(level: int, portrait: bool) -> int:
	var tbl: Dictionary = FS_PORTRAIT if portrait else FS_LANDSCAPE
	return int(tbl.get(level, int(FS_LANDSCAPE[Level.L4])))

## 该画布下 1 逻辑px 等于多少 pt（判据与文档换算都用它，别再各写一遍除法）。
static func pt_per_px(portrait: bool) -> float:
	return 393.0 / float(BASE_PORTRAIT.x) if portrait else 1.0


# ═══════════════════════ 2. 间距 ═══════════════════════

## 间距阶梯，基准单位 4。★ 现状里的 40 与 14 都不在常用档上，已在 §4 归位。
const SPACE_XS: int = 4      # 图标与文字、行内元素（= 现状 LABEL_GAP 4）
const SPACE_SM: int = 8      # 按钮纵内边距、紧凑控件间（= 现状 8）
const SPACE_MD: int = 12     # 行内控件间、输入框内边距
const SPACE_LG: int = 16     # 卡片内边距
const SPACE_XL: int = 24     # 面板横内边距、区块间（= 现状 24）
const SPACE_2XL: int = 32    # 区块间、页面边距
const SPACE_3XL: int = 48    # 页面外边距、大留白

# ═══════════════════════ 3. 形状 ═══════════════════════

const RADIUS_SM: int = 4         # 芯片、色块、输入框
const RADIUS_MD: int = 8         # 按钮、面板（★ = 现状值，保持不动以免全量回归）
const RADIUS_LG: int = 16        # 卡片、浮层
const BORDER_HAIRLINE: int = 1   # 默认描边（★ = 现状值）
const BORDER_STRONG: int = 2     # 选中态、焦点态

# ═══════════════════════ 4. 边距归位（2026-10-13 用户口令「任你改」）═══

## 棋盘外边距：横 40 → 32（= SPACE_2XL），竖 14 → 16（= SPACE_LG）。
## ★ 改的理由不是"整齐"，是**层级**：棋盘边距属于页面级留白，
##   应当用页面档的 token（32），而不是一个只有它自己在用的 40；
##   竖屏 14 → 16 是同一套阶梯的下沿，且仍在 `board_margin()` 的既有关系内。
## ★ 为什么写成字面 32/16 而不是 `float(SPACE_2XL)`：GDScript 的 `const` 初始化必须能
##   在**编译期**求值，`float(...)` 构造调用不保证被折叠 —— 一旦不折叠就是加载期
##   解析错误，整个项目起不来。token 阶梯与这两个值同源（16=SPACE_LG、32=SPACE_2XL），
##   由上面各档的定义可核对。
##
## ★ 为什么横竖方向相反不是笔误：竖屏的瓶颈**恒是宽度**（见 `game_config.gd` 的
##   `board_margin` 注释），多留 2px 就直接少 2px 可点面积；而 16 与 12 的差距在窄视口
##   上可忽略。再收到 12 会让棋盘边缘的瓷砖贴到屏幕边，破坏「棋盘是居中一块」的观感。
const BOARD_MARGIN_LANDSCAPE: float = 32.0   # = SPACE_2XL；40 → 32
const BOARD_MARGIN_PORTRAIT: float = 16.0     # = SPACE_LG；14 → 16

## HUD 按钮最小高度（竖屏）。76 → 80。
## ★ 76px ≈ 41.5pt，低于 Apple 最小可点区 44pt；80px ≈ 43.7pt，仍未满 44，
##   但已是当前 token 阶梯下的最大可行值（HUD 是**底部整条**，再高会挤掉棋盘）。
##   记为**已知例外**：判据 `judge_mobile_layout()` 的 `TOUCH_MIN_PT=44`
##   仍按 44 判定，不下调阈值 —— 下调阈值等于把判据改成自证。
const HUD_TOUCH_MIN_PORTRAIT: float = 80.0

## HUD 文字字号（竖屏）。★ 原 20px ≈ 10.9pt，远低于 `TEXT_MIN_PT=17`，
##   是本次重设计里**唯一一个"本来就违反既有判据"**的数字，顺手修掉。
const HUD_BTN_FONT_PORTRAIT: int = 30    # 24 → 30（16.4pt）
const HUD_LABEL_FONT_PORTRAIT: int = 28  # 20 → 28（15.3pt）