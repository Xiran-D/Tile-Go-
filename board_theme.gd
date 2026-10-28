class_name BoardTheme
extends Resource

## ═══════════════════════════════════════════════════════════════════════════
## 一个棋盘主题的**全部数据**（2026-10-20 第 1 步：从 game_config.gd 的硬编码 Dictionary 搬出来）
## ═══════════════════════════════════════════════════════════════════════════
##
## 为什么要改成 Resource：
##   · 硬编码 `Dictionary` **没有 schema** —— 缺一个键就是静默回退到上一个主题的颜色，
##     编译器一个字都不会说（P2 痛点，见 `瓷砖围棋_主题系统重构方案_2026-10-20.md`）；
##   · Resource 的字段**有类型**：检查器里能改、能即时预览，缺键 = 类型错误而不是静默降级；
##   · 12 个主题各一个 `.tres`，改色不用在 2000 行的 `game_config.gd` 里翻。
##
## ★ 主题的**显示顺序**由文件名前缀决定（`themes/00_宣纸.tres` … `11_玄石.tres`），
##   不靠文件系统返回顺序 —— 那东西在不同平台/不同时刻会变，而设置页色块的排列是**用户可见**的。
##
## ★★ `has_stone_colors` 为什么必须是显式开关：
##   旧 Dictionary 用"有没有 `stone_black` 这个键"表达"这个主题自带棋子色"，
##   而 Resource **没有"键不存在"这回事**（字段总有值）。
##   所以这里用 bool 表达"用我的棋子色"还是"跟随全局默认"。
##   ⚠️ 不要简化成"两个 Color 各给个默认值就算了"：霓虹 / 赛博的棋子色与棋盘色是**一对**
##   （深底 + 荧光子），而其余 10 个主题必须**继续跟随** `STONE_*_DEFAULT`
##   —— 写死就等于把"继承"变成了"覆盖"，以后改默认黑白子会漏掉那 10 个主题。

## 主题名（也是落盘在 `appearance.cfg` 里的标识、设置页色块的 tooltip）。
## ★ 不要改名：`_migrate_preset_name()` 的别名表与老用户的 cfg 都按这个名字认。
@export var display_name: String = ""

## 背景色（棋盘外的底）。
## ★ 默认值 = **宣纸**主题的当前值（2026-10-20 配色重做后）：新建一个 BoardTheme
##   资源时应当直接得到"默认主题"的样子，而不是另一套颜色。
@export var bg: Color = Color(0.945, 0.918, 0.852)

## 棋盘色（**瓷砖 / 托盘 / 菜单色块**都是它 —— 见 game.gd `board_tile_color` 的同步）。
@export var board: Color = Color(0.792, 0.606, 0.322)

## 棋盘轮廓线色（注意带 alpha：多数主题是半透明的暗线）。
@export var line: Color = Color(0.315, 0.205, 0.095, 0.60)

## 该主题的**专属标题色**。alpha = 0 表示"未设" ⇒ `accent_color()` 按背景明暗推算兜底。
@export var accent: Color = Color(0, 0, 0, 0)

## true ⇒ 本主题自带棋子色（只有霓虹 / 赛博）；false ⇒ 跟随 `STONE_BLACK_DEFAULT` / `STONE_WHITE_DEFAULT`。
@export var has_stone_colors: bool = false
@export var stone_black: Color = Color(0.06, 0.06, 0.08)
@export var stone_white: Color = Color(0.90, 0.90, 0.95)


## 本主题实际生效的黑子色（`has_stone_colors` 为 false 时回退到全局默认）。
## ★ 调用方一律走这里，**不要直接读 `stone_black`** —— 否则"跟随默认"这条语义会漏掉。
func effective_stone_black(default_col: Color) -> Color:
	return stone_black if has_stone_colors else default_col


func effective_stone_white(default_col: Color) -> Color:
	return stone_white if has_stone_colors else default_col
