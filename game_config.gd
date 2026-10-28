extends Node

# 菜单场景 → 对局场景 之间的全局配置（Autoload 单例）
# 菜单场景写入 mode / board_size / ai_time_ms，对局场景（game.tscn）在 _ready() 中读取。
# 两个场景通过 get_tree().change_scene_to_file() 切换，彼此独立、互不持有引用。

var mode: int = -1           # GameConfig.LOCAL / GameConfig.VS_AI（由菜单写入）
                             # ★ 2026-10-15b：菜单侧「疾风」是与「本地」「磐石」并列的独立档
                             #   （内部值 100），但在**下发边界**折叠成 `VS_AI` + 本文件下面那个
                             #   `xg_opponent` ——所以这里**永远只有三个合法值**，本文件不需要知道
                             #   「磐石/疾风」这两个显示名（它们在 `MenuModel.mode_label()`）。
var xg_opponent: bool = false  # 「疾风」档标记（2026-10-14 立项为「测试AI」，10-15 转正定名）
## 「流水」档标记（2026-10-22）：白方由渗流引擎 `LiushuiAI`（`ai_engine_liushui.gd`）接管。
## ★ 与 `xg_opponent` **逐字同构**（同样的折叠方式、同样的生命周期），刻意分成两个 bool 而不是
##   把 `xg_opponent` 升级成档位号 —— 理由见 `menu.gd` 的 `MODE_LIUSHUI` 注。
## ⚠️ 同样是**随局下发**的瞬时值（菜单开局无条件覆盖写一次、game `_ready` 读一次转成
##   `liushui_play_mode`），自己不落盘；落盘的是 `last_match.cfg` 的 `xg` 字段（0/1/2）。
var liushui_opponent: bool = false
## 「野马」档标记（2026-10-23）：白方由神经网络先验引擎 `YemaAI`（`ai_engine_yema.gd`）接管。
## ★ 与 `xg_opponent` / `liushui_opponent` **逐字同构**（同样的折叠方式、同样的生命周期）。
##   第四个 bool 而不是"把三者并成档位号"：并档要改 `last_match.cfg` 的既有语义与菜单恢复路径，
##   而这三个标记各自独立、互斥由菜单的 `_sel_mode` 单值保证 ⇒ 加 bool 是零风险的那条路。
## ⚠️ 同样是**随局下发**的瞬时值（菜单开局无条件覆盖写一次、game `_ready` 读一次转成
##   `yema_play_mode`），自己不落盘；落盘的是 `last_match.cfg` 的 `xg` 字段（0/1/2/**3**）。
var yema_opponent: bool = false
# ⚠️ 本字段是**随局下发**的瞬时值（菜单开局写一次、game `_ready` 读一次转成
#   `xg_play_mode`），**自己不落盘**；落盘的是菜单的「选没选疾风」= `last_match.cfg`
#   的 `xg` 字段（见 `save_last_match()`）。两件事别混。
var board_size: int = 1      # GameConfig.RANDOM / STANDARD / ENHANCED（由菜单写入）
var board_type: int = BOARD_PENROSE   # 棋盘类型（菜单写入）：BOARD_PENROSE 等，为未来扩展预留
var ai_time_ms: int = 200    # AI 思考时长（毫秒，由菜单写入；默认＝普通档）

# AI 难度档位（菜单写入，game.tscn 应用到 AIEngine）
const AI_EASY: int = 0       # 简单：单线程 + 150ms + 根候选全宽（预算被上百个候选摊薄，
                             #        每候选不到 1 次访问 → 着法≈纯先验，且带噪声）
const AI_NORMAL: int = 1     # 普通：多线程 + 200ms + 自适应根剪枝（实测 150ms 已收敛，见 --aibud）
const AI_HARD: int = 2       # 困难：多线程 + 500ms + 自适应根剪枝
                             #      注意：实测「想更久」并不改变着法（一致率 88~100%），
                             #      困难与普通的差别主要体现在观感；真正拉开棋力要靠改先验
var ai_level: int = AI_NORMAL
var ai_threads: int = 0      # 0 = 按 CPU 核数自动（引擎内部上限 4）
var ai_root_width: int = 0   # 0 = 自适应，取 AIEngine.auto_root_width（14）；
                             #     实测「根候选数」是搜索能否收敛的关键，详见 ai_engine._effective_root_width

const LOCAL: int = 0         # 本地双人
const VS_AI: int = 1         # 人机对战（桌面菜单显示名 = 「磐石」；「疾风」也折到本档 + `xg_opponent`）

const RANDOM: int = 0        # 随机棋盘：每局开局现场生成，格数约 200（详见 game.gd random_target_tiles）
                             #   彭罗斯 → 在密铺里随机开一扇圆形窗口；立方体 → 从中心随机生长一片蜂窝。
                             #   由 _rand_seed 决定（联机时房主下发种子，保证双端棋盘一致）。
const STANDARD: int = 1      # 标准棋盘（约 120 落子格 / 141 顶点）
const ENHANCED: int = 2      # 加强棋盘（约 360 落子格 / 401 顶点）

const BOARD_PENROSE: int = 0 # 彭罗斯密铺（非周期菱形密铺棋盘）
const BOARD_CUBE: int = 2    # 立方体棋盘：每 3 块菱形拼成一个正六边形（等距立方体视觉），六边形再排成蜂窝大盘
const BOARD_KITE: int = 3    # 筝形棋盘：每 3 块筝形**钝角相对**拼成一个等边三角形，等边三角形再密铺
const BOARD_SNOWFLAKE: int = 4   # 雪花棋盘：Ammann-Beenker 密铺（octagrid 四格网对偶）——
                                 # 45° 胖菱形 + 正方形桥；盘心 8 块菱形锐角共点成一朵雪花；圆窗裁剪
const BOARD_HAT: int = 5         # 爱因斯坦棋盘（帽子家族 / 非周期单瓦片密铺）。
                                 # 造盘：H7/H8 替换系统迭代出池，再按共享边 BFS 取 N 片（见 game.gd）。
                                 # 编号 5 沿用被它取代的「宝石盘」（同日下线），不另开新号。
                                 # ★ 2026-09-19 起它不再是「一种盘」，而是**一族三档**（见下面的 HAT_*）：
                                 #   盘的中心概念是「爱因斯坦瓦片 = 同一个 Tile(a,b) 连续族」，
                                 #   a/b 取不同值就得到帽子/海龟/幽灵，角谱与替换系统完全相同。
const HAT_HAT: int = 0           # 帽子 the hat     = Tile(1, √3)：长边 8 条 + 短边 6 条，面积 8√3
const HAT_TURTLE: int = 1        # 海龟 the turtle  = Tile(√3, 1)：把长短边对调，面积 10√3
const HAT_SPECTRE: int = 2       # 幽灵 the spectre = Tile(1, 1) ：等边 14 边形，面积 (3+√3)√3 ≈ 8.196
                                 #   （论文里的 chiral spectre 的**直线版**；我们用带镜像的替换系统，
                                 #    三档都已用精确算术验证「无缝无叠 + 无 T 型接点」，见 game.gd 注释）
## 当前种类（菜单「爱因斯坦」下那一行三瓣选择写入；联机时随快照同步）。
## ★ 它只影响**边长比例**，不影响任何拓扑 → 池/邻接/装配代码只写一份。
var hat_kind: int = HAT_HAT
# ⚠️ 编号 1 原是「经典 19×19 网格棋盘（BOARD_GRID）」，2026-09-15 下线：
#    我们的 AI（唯一位置先验 = w_center·_cent）对它有系统性劣势 —— 角/边被当成负价值，
#    而 19×19 的棋理恰恰建立在占角起手上。与其为它单做一套模型，不如砍掉、把位置让给新棋盘。
#    编号不复用（CUBE 仍为 2），以免联机快照 / 旧存档里的类型号错位。

const ONLINE: int = 2        # 联机对战（线上）

# 联机相关（由菜单写入，game.tscn 在 _ready 中读取）
# ★ 2026-09-30 §24 第 5 步：`server_ip` / `server_port` / `matchmaking_url` / `use_relay` 四个字段
#   已按用户口令「删除自建联机代码」全部移除 —— 线上只剩 Steam，不再有 IP / 端口 / 信令服务器地址。
#   回退它们请从工作区 `瓷砖围棋_临时输出/step5/备份_自建联机/` 取回（含各自 `.uid`，md5 已记）。
var online: bool = false      # 是否联机
var is_host: bool = true      # true = 房主（建大厅，执黑）；false = 加入（执白）
var connection_error: String = ""   # 联机启动失败时的错误信息，由 game.tscn 写入、menu.tscn 显示后清空
var invite_code: String = ""   # Steam 大厅房间号，由 `_on_steam_lobby_ready()` 回填，显示在 HUD 供分享

# ---- 联机座位（2026-10-21 用户口令「要能选择座位（黑白棋）」）----
# ★ 语义 = **房主视角**「我执哪一色」。加入方的颜色**不**由这里决定，而是房主在
#   `game.gd::_send_init()` 里把自己的相反色下发过去（`net_color` 字段）。
#   ⇒ 座位只有一个真源：谁能定规则，谁的颜色就在这儿；加入方读到的座位永远来自房主。
# ★ 原先硬编码「房主恒黑、加入恒白」（`_net_color = BLACK if _is_host else WHITE`），
#   邀请好友时想换边只能自己再开一个房 —— 这就是要加这一个字段的原因。
# ⚠️ 与 `GameConfig.RANDOM`（盘大小"随机"档）**不是同一个概念**，只是名字像；别互相替换。
const SEAT_BLACK := 0
const SEAT_WHITE := 1
const SEAT_RANDOM := 2
var seat_choice: int = SEAT_BLACK     # 房主座位：黑 / 白 / 随机（开局那一刻掷一次，见 game.gd）

# ---- 联机通道（2026-09-30 §21 第 3 步引入；§24 第 5 步删自建后**只剩一档**）----
# ★ 历史：这里原有 `CHAN_RELAY = 0`（自建中继 / ENet）与 `CHAN_STEAM = 1` 两档。第 5 步按用户口令
#   「删除自建联机代码」把 `CHAN_RELAY` 去掉了，**但 `CHAN_STEAM` 的数值 1 故意不改** ——
#   它只跟自己比，改数值是零收益，却会牵动菜单自检与结构守卫里的断言（本工程吃过"顺手改数值"的亏）。
# ★ `net_channel` 字段**保留**（不是残留）：它是"本局走哪条通道"的**唯一真源**，
#   `game.gd::_steam_arg()` 只读这里。第 5 步后它恒等于 `CHAN_STEAM`；留着它是为了将来若再加
#   第二条通道（例如局域网直连），照旧"菜单写一处、引擎读一处"（铁律 8）。
# ★ 唯一真源：菜单只改这里，game.gd 的 `_steam_arg()` 只读这里 —— **不要在别处再放一份**。
# ★★ 但它**只回答"走哪条通道"，不回答"是不是联机"**（`mode` 才回答那个）——
#   引擎侧判据因此是 **`mode == ONLINE and net_channel == CHAN_STEAM`**（`game.gd::_steam_arg()`，
#   结构守卫 S33 钉着）。2026-09-30 §24 追修实测：第 5 步后这里只剩一档 ⇒ 只认通道 = 恒真，
#   于是**单机局与全部游戏侧自检**都被改写成联机（P0）。⇒ 别把 `mode` 那一半当成冗余删掉。
const CHAN_STEAM: int = 1      # Steam P2P（大厅 + P2P，NAT 穿透由 Steam 自己做，不需我们运维服务器）
var net_channel: int = CHAN_STEAM
var steam_lobby: int = 0       # Steam **加入方**要输入的房间号（房主侧的房间号由回调回填进 invite_code）

# ====== 外观配色（设置页写入；菜单场景与对局场景在 _ready() 中读取）======
# 每个主题三种颜色：背景色 / 棋盘颜色 / 棋盘轮廓颜色。
# 持久化在 user://appearance.cfg（Windows 位于 %APPDATA%\Godot\app_userdata\<项目>\）。
var bg_color: Color = Color(0.945, 0.918, 0.852)      # 背景色（默认主题=宣纸：暖纸白）
var board_color: Color = Color(0.792, 0.606, 0.322)   # 棋盘颜色（宣纸=榧木金，2026-10-20 配色优化后）
var line_color: Color = Color(0.315, 0.205, 0.095, 0.60) # 棋盘轮廓颜色（宣纸=深木褐）
var tile_color_a: Color = board_color                 # 兼容保留：联机快照用，随主题取棋盘色
var tile_color_b: Color = board_color                 # 兼容保留：同上，不再用于渲染
var bg_brightness: float = 1.0                        # 背景明度乘数（0.5 ~ 1.5）
var appearance_preset: String = DEFAULT_PRESET          # 当前预设名；默认主题见 DEFAULT_PRESET
## 当前主题的专属标题色（由 apply_preset 从 PRESETS 的 accent 填入）。
## alpha=0 表示「未设」→ accent_color() 回退到按背景明暗推算的默认色。
var accent_override: Color = Color(0, 0, 0, 0)
## ═══ 第 0 步（2026-10-20）：写用户外观配置的**脏标记门** ═══
##
## 实测事故：任何一次 `menu.tscn` 启动（哪怕只是 `--headless --quit-after 90` 冒烟）
## 都会把用户 `appearance.cfg` 写成"**内存里当前那个主题**" —— 同一天复现 5+ 次，
## 每次主题都不一样（宣纸 / 藕荷 / 霓虹 / 墨绿 / 赛博 / 藏青）。
## 根因是"遍历主题的中间态 + 此时有人调了 `save_appearance()`"，而遍历点很多（自检 / 审计 / 预览）。
##
## ⇒ 判据从「这次是不是自动化运行」换成「**用户到底有没有动过设置**」：
##   `save_appearance()` 写**用户真配置**时必须 `_appearance_dirty == true`；
##   自检盘（`APPEARANCE_SELFTEST_PATH`）**不受这道门约束** —— `--apptest` / `--settest`
##   的"落盘"判据全靠它，挡了就等于把功能一起挡死。
##
## ★ 反向风险（比写脏更糟）：**漏置脏 ⇒ 用户的设置存不下来**。
##   置脏点集中在 `menu.gd` 的 6 个用户操作回调（屏幕模式 / 图模式 / 指针开关 / 指针大小 /
##   主题色块 / 恢复默认），守门人是 `--settest` 既有的三条"落盘"判据 —— 漏一处立刻红。
var _appearance_dirty: bool = false
## 被门挡下的写次数。★ 存在的意义：区分"门真的挡住了"与"本来就没写"（后者会让判据恒绿）。
var _appearance_save_blocked: int = 0
## 棋子色（**主题的一个字段**，2026-10-08 起）：由 `apply_preset()` 从 PRESETS 的
## `stone_black`/`stone_white` 填入；主题没写这两个键 ⇒ 回退到 `STONE_*_DEFAULT`
## （= `game.gd` 两个 `@export` 的初值，也就是大家熟悉的白子/黑子）。
## ★ 为什么棋子色属于"主题"而不是"全局设置"：霓虹类主题的整个世界是深底荧光，
##   黑白子放上去会与背景糊在一起 —— 棋子色与棋盘色是**一对**，必须一起设计。
## ★ 这两项**不单独落盘**：它们的真源是"当前主题"，而主题名已经落在 appearance.cfg 里。
##   ⚰️ 2026-10-13：这里原文写「用户在**调参面板**临时改的棋子色只在本次运行有效」——
##   TAB 调参面板已整块删除（用户口令「把整个 tab 菜单砍掉」），改颜色的运行期路径
##   只剩 Inspector 的 `@export`。语义不变：临时改动只在本次运行有效，重开回到主题设定。
var stone_color_black: Color = Color(0.06, 0.06, 0.08)
var stone_color_white: Color = Color(0.90, 0.90, 0.95)

# ====== 图模式（设置页「显示」组的开关）======
## 开 = **网格棋盘 + 圆形棋子**（经典围棋的观感）：瓷砖不铺面、所有瓷砖边画成完整网格，
##     棋子从「整块瓷砖染色」改成「画在格心的圆」；
## 关 = 现状（实心瓷砖面 + 整块染色棋子）。
## ★ 「保留棋盘关系」是硬约束：落子单元 / 邻接 / 盘型一律不变，换的只是**画法**。
## ★ 只是**本地显示偏好**：不进联机快照，对手看到的是他自己的设置。
## 落盘位置 = appearance.cfg 的 `appearance/graph_mode`；与主题同文件但**不属于任何预设**
## ——「恢复默认主题」不该把玩家选的显示方式一起抹掉。
var graph_mode: bool = false
# 显示模式（设置页改；启动时由 apply_window_mode() 应用）
# 0=窗口  1=全屏（独占）  2=无边框全屏（borderless，切出更流畅，推荐）
var window_mode: int = 0

const MODE_WINDOW: int = 0
const MODE_FULLSCREEN: int = 1
const MODE_BORDERLESS: int = 2

# 从全屏切回窗口时恢复的逻辑尺寸（窗口模式下的期望大小）。
# 不用「全屏前的尺寸」是因为首次启动就是全屏时没有可恢复的历史值；
# 取屏幕的 60%（约 1728×1080）比固定 1152×648 更适合大屏，且不会顶到最大化阈值。
func _windowed_size() -> Vector2i:
	var r: Rect2i = screen_usable_rect()
	var w: int = clampi(int(float(r.size.x) * 0.6), 1024, maxi(1024, r.size.x - 80))
	var h: int = clampi(int(float(r.size.y) * 0.6), 648, maxi(648, r.size.y - 80))
	return Vector2i(w, h)

## 当前屏的**可用区域**（去掉任务栏 / 程序坞 / 顶部状态条）：窗口居中要对它算。
## ★ 为什么不是 screen_get_size()（2026-09-22 用户口令「窗口居中」）：
##   Windows 上 2880×1800 的屏底部有约 48px 任务栏 → 可用区其实是 2880×1752。
##   按整屏居中会把窗口放到 y=(1800−1080)/2=360，而可用区中心是 (1752−1080)/2=336，
##   视觉上就是「窗口偏下」（实测改前 360、改后 336）。这是唯一一个「居中」确实没做到的档。
##   ★ 探针不读 = 不检查；`[shot]` 日志会把可用区与「居中偏差」一起打出来，真机可核。
func screen_usable_rect() -> Rect2i:
	var scr: int = DisplayServer.window_get_current_screen()
	var r: Rect2i = DisplayServer.screen_get_usable_rect(scr)
	if r.size.x <= 0 or r.size.y <= 0:
		# 个别驱动会返回空矩形 → 退回整屏（宁可偏 24px，不能把窗口摆到 (0,0) 之外）
		r = Rect2i(DisplayServer.screen_get_position(scr), DisplayServer.screen_get_size(scr))
	return r

## 把窗口摆到**当前屏可用区**正中（want = 期望的窗口尺寸）
func center_window(want: Vector2i) -> void:
	var r: Rect2i = screen_usable_rect()
	DisplayServer.window_set_position(r.position + (r.size - want) / 2)

## 探针：当前「窗口位置」与「可用区居中位置」的偏差（=0 即精确居中）。
## 非窗口模式（独占全屏 / 无边框）返回 (0,0) 且 `window_center_applicable()` 为假 ——
## 那两种模式是**按屏幕原点**铺满的，拿居中去判它们会得到假报警。
func window_center_applicable() -> bool:
	return DisplayServer.get_name() != "headless" \
		and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED \
		and not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)

func window_center_delta() -> Vector2i:
	if not window_center_applicable():
		return Vector2i.ZERO
	var r: Rect2i = screen_usable_rect()
	var want: Vector2i = DisplayServer.window_get_size()
	return DisplayServer.window_get_position() - (r.position + (r.size - want) / 2)

## 人读摘要（给 `[shot]` / 自检打印用）
func window_center_verdict() -> String:
	if not window_center_applicable():
		return "不适用（非窗口模式：按屏幕原点铺满）"
	var d: Vector2i = window_center_delta()
	if absi(d.x) <= 2 and absi(d.y) <= 2:
		return "居中 ✓"
	return "偏（%+d, %+d）✗" % [d.x, d.y]

# ---------------- 调试用窗口尺寸覆盖（仅本次进程，不写配置） ----------------
## `--winsize=720x1560`：强制本进程以**窗口模式**启动并设为该尺寸。
## ★ 为什么需要它（2026-09-23 用户口令「试一试，而且我希望它是竖屏的」）：
##   竖屏适配只有在**真实的竖屏逻辑画布**下才看得见。本机是 2880×1800 的横屏桌面，
##   不改窗口尺寸就永远看不到 `size.y` 被拉到 2400+ 那一档，于是「改没改好」只能靠猜。
##   设计画布是 1152×648 + `aspect=expand`，所以
##   `--winsize=720x1560` → scale=min(720/1152, 1560/648)=0.625 → 逻辑画布 **1152×2496**，
##   正是「手机竖屏」的等价物（宽被锁死、高被拉长）。
## ★ 与 `--cursorsize=` 同规矩：**必须放在 `--` 之后**（`OS.get_cmdline_user_args()`）。
## ★ 为什么要**绕过** `apply_window_mode()`：用户上一局若存的是「无边框全屏」，
##   那个分支会把窗口重新拉满屏幕 → 尺寸覆盖被吃掉，而且**静默**（看着像「参数没生效」）。
##   所以这里自己设模式 + 尺寸 + 居中，一条链走到底。
var debug_window_size: Vector2i = Vector2i.ZERO   # ZERO = 未设

# ---------------- 竖屏设计画布（2026-09-23 用户口令「试一试，而且我希望它是竖屏的」） ----------------
## 设计画布两基座：横屏 1152×648（原版 16:9）/ 竖屏 720×1560（≈19.5:9）。
##
## ★ 先纠正一个直觉错误（我自己先想错的）：`aspect=expand` 下「竖屏画布会自己变高」，
##   所以看着像"什么都不用做"。但 expand 只补**多出来的那一维**，逻辑画布 = 1152 × (1152·h/w)
##   —— 也就是说竖屏时「1 逻辑像素」恒等于 **物理宽/1152**。
##   iPhone 15 竖屏 1179×2556（393×852pt，3 物理px = 1pt）：
##     · 基座 1152 → 1 逻辑px = 1.023 物理px = **0.34pt**
##       → Godot 默认按钮（高约 31 逻辑px）在手机上只有 **10.6pt**
##       （Apple 最小可点区域 44pt）→ 按不准，而且**不报错**，只是"感觉点不动"。
##     · 基座 720  → 1 逻辑px = 1.6375 物理px = **0.546pt** → 同一个按钮 17pt（×1.6）。
##   ★ 所以竖屏真正的旋钮**不是"画布比例"而是"画布单位大小"**，一个旋钮同时决定
##     ①UI 相对屏幕的视觉大小 ②留给横向排版的逻辑宽度。选 720 的理由见下。
##
## ★ 为什么 720：竖屏目标机 iPhone 15 的 393/852 = 0.4613，而 720/1560 = 0.4615
##   → 两者aspect几乎逐位相同，`expand` 的多余留白 ≈ 0（不会有一边白条）。
##   同时 720 还够宽：菜单棋盘行 6 个菱形各分到 120 逻辑px（标签 3~4 字放得下）。
##   想再放大 UI 就调小它，但**必须重看菜单棋盘行**（`menu.gd::ROW_WIDTH_RATIO`）有没有挤到一起。
##
## ★ 棋盘**不受影响**：`game.gd::_adapt_to_screen()` 是按视口比例缩放棋盘的
##   （`min((vs.x-80)/w, (vs.y-80)/h)`），换基座只是"换了单位"，棋盘照旧铺满宽度。
##   —— 这正是「UI 放大但不牺牲棋盘」能同时成立的原因，别再另做一个"棋盘缩放系数"。
const BASE_SIZE_LANDSCAPE: Vector2i = Vector2i(1152, 648)
const BASE_SIZE_PORTRAIT: Vector2i = Vector2i(720, 1560)

## 本次会话是否竖屏（-1=自动）。**故意只在本次进程生效**：这是形态开关，
## 不该被一次误带参数的运行永久写进用户配置。
var portrait_override: int = -1
## 画布基座的**本次进程覆盖**（`--canvassize=WxH`，须放 `--` 之后）；ZERO = 不覆盖。
## ★★ 为什么要有它（2026-09-30，Steam 商店页素材时踩出来的）：
##   截图的尺寸**不是**由 `--winsize=` 决定的 —— 那个只改**物理窗口**，渲染仍按画布基座
##   （横 1152×648），所以 `--winsize=1920x1080` 截出来的 PNG **仍然是 1152×648**。
##   而 Steam 商店页截图**最低 1280×720**、推荐 1920×1080 ⇒ 用 1152×648 会被拒或被迫放大糊掉。
##   ⇒ 想拿原生 1920×1080 的图，只能**同时**覆盖基座与窗口：`--canvassize=1920x1080 --winsize=1920x1080`。
##   ★ 只影响本次进程（同 `--winsize=` / `--portrait`），绝不写进任何配置。
##   ★ 棋盘不受影响：`game.gd::_adapt_to_screen()` 按视口比例缩放棋盘，换基座只是换单位。
var canvas_size_override: Vector2i = Vector2i.ZERO
## 最近一次实际套用的画布（"横"/"竖"）。仅供自检/`[shot]` 读取做断言 —— 探针不读 = 不检查。
var canvas_applied: String = ""

## 是否 iOS/Android 真机。★ 别用 `OS.has_feature("mobile")`：它把 web 也算进去，
## 而 web 上"没有键盘"这条同样是错的；要认就认名字。
func is_mobile_platform() -> bool:
	var n: String = OS.get_name()
	return n == "iOS" or n == "Android"

# ---------------- 手机菜单路由（2026-09-23 ~ 2026-10-17） ----------------

## 本次会话的物理窗口尺寸。`--winsize=` 优先读变量而不是问 DisplayServer ——
## 刚 `window_set_size()` 完那一帧，Windows 上回读可能还是旧值（异步），
## 于是「竖屏判据」会读到横的值，**静默**地选错画布。
func physical_window_size() -> Vector2i:
	if debug_window_size != Vector2i.ZERO:
		return debug_window_size
	return DisplayServer.window_get_size()

## 是否用竖屏画布。判据集中在**这一处**（铁律 8：一处写、一处读）。
##   · `--portrait` / `--landscape` 强制 —— 这是竖屏分支在本机（横屏桌面）唯一的 runner。
##     没有它，「竖屏逻辑」在开发机上永远跑不到，等于**没有判据**。
##   · iOS/Android 恒真：竖屏就是这次的目标形态（见 project.godot 的 orientation）。
##   · 桌面：窗口本身是竖的也算。同一套逻辑不做第二份，顺带把「竖窗」这个老坑一起覆盖
##     —— `--hatdead` 已经证明非 16:9 视口会丢格子（方窗 1152×1152 越界 21 格）。
func use_portrait_canvas() -> bool:
	if portrait_override >= 0:
		return portrait_override == 1
	if is_mobile_platform():
		return true
	var s: Vector2i = physical_window_size()
	return s.y > s.x

func design_base_size() -> Vector2i:
	# ★ 覆盖优先，且**只在这一处**判断（铁律 8：一处写、一处读）。放在 `use_portrait_canvas()`
	#   之前：`--canvassize=` 是"我要多大画布"，比"横还是竖"更具体 ⇒ 具体压过抽象。
	if canvas_size_override != Vector2i.ZERO:
		return canvas_size_override
	return BASE_SIZE_PORTRAIT if use_portrait_canvas() else BASE_SIZE_LANDSCAPE

## 把画布基座真正套到根 Window。**必须在任何场景 `_ready()` 之前调用** —— Autoload 的
## `_ready()` 正好满足；晚了的话场景会先按旧基座算一轮布局（菜单的 `_layout_setup()`
## 与对局的 `_adapt_to_screen()` 都会白跑，而且**不报错**，只是第一次排版是错的）。
func apply_design_canvas() -> void:
	var w: Window = get_window()
	if w == null:
		return
	var base: Vector2i = design_base_size()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = base
	canvas_applied = "竖" if base == BASE_SIZE_PORTRAIT else "横"

## ═══════════════════════════════════════════════════════════════════════════
## 全局 UI 主题（2026-10-13 新增，P0）
## ═══════════════════════════════════════════════════════════════════════════
## ★ 为什么落在这里：本 Autoload 的 `_ready()` 早于任何主场景 `_ready()`，
##   所以 `root.theme = …` 一行即可让**三个场景**（menu / menu_mobile / game）
##   的所有原生控件（Button / Label / LineEdit / ScrollContainer…）统一生效，
##   **不需要改任何一个 `.tscn`**（本工程三个场景都是薄壳，改它们等于改结构，
##   不在视觉重设计的范围内）。
## ★ 为什么必须在 `apply_design_canvas()` **之后**：主题的默认字号按横/竖两套
##   阶梯取值，而横竖由画布基座决定 —— 顺序反了会用错那套字号，且**不报错**。
## ★ 字体缺失时静默降级（退回引擎默认字体），理由见 `ui_theme.gd` 的说明：
##   让"字体没被编辑器导入过"不要伪装成"配色/排版坏了"。
var ui_theme_applied: bool = false

func apply_ui_theme() -> void:
	var w: Window = get_window()
	if w == null:
		return
	var th: Theme = UITheme.build(use_portrait_canvas())
	w.theme = th
	# ★ 顺带把正文字体挂到**引擎兜底字体**上（等价于项目设置 `gui/theme/custom_font`）：
	#   这是**次要保险**，只管"某个项名在整条链上都不存在"的情况（新控件类型/新项名）。
	#   ⚠️ 它**解决不了**浮层那条路（实测踩过）：默认主题里 `Label/font` 这类项名是**已存在的项**，
	#      查项名的路径根本走不到 `fallback_*` —— 挂了这个，`CanvasLayer` 里的字照样是引擎默认字体。
	#      浮层那件事由 `new_themed_layer()` 显式解决（见那里的注）。
	if ThemeDB.fallback_font != UITheme.body_font():
		ThemeDB.fallback_font = UITheme.body_font()
	ui_theme_applied = true

## 把子树里所有 `Control` 收进数组（含自己是 + 递归）—— **唯一**的"遍历控件树"实现，
## 菜单侧（`--menutest` ⑮⑯⑰）与对局侧（`--esctest` 的字体判据）共用。
## ★★ `get_children(true)` 的 `true` 不能省（2026-10-15 实测踩到）：`ScrollContainer` 的两条滚动条
##   是**内部子节点**，而默认口径**不收内部子节点** ⇒ 判据会漏掉正是要审的那几个控件
##   （症状：⑯ 报"勾选框 402 个"却一个 VScrollBar 都没有，而棋谱页右侧明明有一条滚动条）。
##   判据的遍历口径要**比生产代码宽**：宽了最多多看几个控件，窄了就是"看不见"。
func collect_controls(node: Node, out: Array[Control]) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		out.append(node as Control)
	for c in node.get_children(true):
		collect_controls(c, out)

## 建一个**能继承主题**的浮层容器（`CanvasLayer`）。
## ★★ 为什么必须有这个工厂（2026-10-15 实测）：`Control` 的字体/配色沿"主题所有者链"往上找，
##   而这条链**只走 Control 与 Window** —— 中间夹一层 `CanvasLayer` 就断（它两者都不是）。
##   本工程的浮层**全是** `CanvasLayer`（菜单的 ESC 退出确认 1 处 + 对局的 HUD / 暂停 / 认输 /
##   结果 / 复盘工具条等 8 处）⇒ 链一断，浮层里的控件就退回**引擎默认字体**：
##   界面照常显示、判据照常全绿，只有"这里的字跟别处不一样"没人管
##   （`--menutest` ⑰ 第一次跑就逮住：ESC 退出确认面板 3 个控件）。
## ★ 做法：浮层的**直接子控件**一进场景树就挂上窗口主题 —— 更深的后代靠继承就够（中间都是
##   Control）。这样"新加一个浮层、忘了补一句"这种事**不存在**：浮层由本工厂造，主题自动到位。
## ⚠️ 两条**试过但不管用**的路（都写在这里，省得下一个人再撞一次）：
##   ① `ThemeDB.project_theme = th` —— 这一版引擎**没有**这个成员（Parse Error 当场炸，
##      game_config.gd 整个加载失败，所有自检零输出）；
##   ② `ThemeDB.fallback_font = th.default_font` —— 见 `apply_ui_theme()` 里的注：
##      `Label/font` 是**已存在的项**，查项名不会走 `fallback_*`。
func new_themed_layer() -> CanvasLayer:
	var l := CanvasLayer.new()
	l.child_entered_tree.connect(_on_themed_layer_child.bind(l))
	return l

func _on_themed_layer_child(node: Node, layer: CanvasLayer) -> void:
	if node is Control:
		var w: Window = layer.get_window() if layer != null else null
		if w == null:
			w = get_window()
		var th: Theme = null if w == null else w.theme
		if th != null and (node as Control).theme != th:
			(node as Control).theme = th

## 人读摘要（给 `[shot]` / 自检打印用）
func canvas_verdict() -> String:
	var s: Vector2i = physical_window_size()
	return "画布=%s(%dx%d) 基座=%s 物理窗=%s 触屏=%s" % [
		canvas_applied, design_base_size().x, design_base_size().y,
		"竖" if use_portrait_canvas() else "横", str(s),
		"是" if is_mobile_platform() else "否"]

# ---------------- 对局棋盘边距 / 常驻 HUD（竖屏与横屏两套值，运行期可调） ----------------
## 棋盘四周留白（逻辑px）。★ 竖屏必须收紧：棋盘近方，竖屏下瓶颈**恒是宽度**
## （`_adapt_to_screen` 取 `min(横向比, 纵向比)`，纵向上永远富余），
## 所以边距省下的每一 px 都直接变成格子可点面积。
##
## ★ 2026-10-13 重设计：40/14 → 32/16，改读 `UITokens` 的阶梯。
##   理由不是"凑整"：棋盘边距属于**页面级**留白，应当用页面档 token（32 = SPACE_2XL），
##   而不是一个只有它自己在用的 40（40 不在 4/8/12/16/24/32/48 任何常用档上）。
##   竖屏 14→16 落在同一阶梯的下沿（SPACE_LG），并在 `board_margin()` 的既有关系内。
##   ⚠️ 横屏 40→32 会让棋盘**变大**（边距收窄），竖屏 14→16 让棋盘**变小** 1 档。
##   两者方向相反不是笔误：竖屏的瓶颈是宽度，多留 2px 就直接少 2px 可点面积，
##   而 16 与 12 的差距在窄视口上可忽略；取 12 会更激进，但会让棋盘边缘的瓷砖
##   贴到屏幕边，破坏"棋盘是居中一块"的观感。
var board_margin_landscape: float = UITokens.BOARD_MARGIN_LANDSCAPE   # 40 → 32
var board_margin_portrait: float = UITokens.BOARD_MARGIN_PORTRAIT      # 14 → 16

func board_margin() -> float:
	return board_margin_portrait if use_portrait_canvas() else board_margin_landscape

## 常驻 HUD（停一手/重新开始/认输/返回菜单）的尺寸。横屏沿用原值（紧凑贴右下角），
## 竖屏改成**底部整条**：手机是拇指操作，"右下角一簇小按钮"既难点到又容易误触。
## ★ 为什么必须显式拉高：Godot 默认按钮高约 31 逻辑px，在 720 基座下换算到 iPhone 15
##   竖屏只有 17pt（Apple 最小可点区 44pt）。
var hud_btn_min_h_landscape: float = 0.0     # 0 = 不设下限（保持默认紧凑高度）
## 竖屏触摸目标下限。★ 单独抽成 const 是**为了阴性对照**：判据必须拿**字面常量**当期望值，
## 不能拿 `hud_button_min_height()` —— 那个函数的返回值由 `use_portrait_canvas()` 决定，
## 而阴性对照正是要翻那个谓词：谓词一翻，期望值同时变成 0，高度那一条就被**自己关掉**了
## （空判据恒真 → 阴性对照只能靠别的副作用报警，看着绿其实没测东西）。
## 这与 ESC 面板对比度那次是同一个坑（见 `probe_dialog_contrast` 的字面常量阴性对照）。
## ★ 2026-10-13 重设计：76 → 80。76px ≈ 41.5pt，低于 Apple 最小可点区 44pt；
##   80px ≈ 43.7pt 是当前阶梯下最大可行值（HUD 是**底部整条**，再高会挤掉棋盘）。
##   ⚠️ 记为**已知例外**：判据 `judge_mobile_layout()` 的 `TOUCH_MIN_PT=44` **不下调** ——
##   下调阈值等于把判据改成自证，那比承认例外更糟。
## ★ 这个常量同时被 `game.gd` 的两处自检当作**期望下限**传进 `judge_hud_layout()`
##   （见 game.gd:919 / 8013）。所以它必须与 `hud_btn_min_h_portrait` **同步抬高** ——
##   只抬实际值不抬期望，判据会从「断言 80」退化成「断言 ≥76」，平白变弱且看不出来。
##   取值只写在 `UITokens` 这一处，这里转发（const 是编译期字面量，判据要的正是这个性质）。
const HUD_TOUCH_MIN_PORTRAIT: float = UITokens.HUD_TOUCH_MIN_PORTRAIT
var hud_btn_min_h_portrait: float = UITokens.HUD_TOUCH_MIN_PORTRAIT
var hud_btn_font_landscape: int = 0          # 0 = 用主题默认字号
## ★ 2026-10-13 重设计：24/20 → 30/28。原先 20px 在 720 基座下只有 **10.9pt**，
##   远低于 `TEXT_MIN_PT=17` —— 这是本次重设计里唯一一个**本来就违反既有判据**
##   的数字（判据只查触控高度、不查 HUD 字号，所以一直没红）。顺手修掉。
var hud_btn_font_portrait: int = UITokens.HUD_BTN_FONT_PORTRAIT
var hud_label_font_portrait: int = UITokens.HUD_LABEL_FONT_PORTRAIT
## 竖屏 HUD 离屏幕左/右/下边的留白（逻辑px）。★ 2026-10-13：14 → 16，与棋盘竖屏边距
## 归到同一档（SPACE_LG）。原先 HUD 是 14、棋盘是 14，两者恰好相同；现在棋盘也是 16，
## 于是"棋盘和 HUD 离屏幕边一样远"这条视觉关系仍然成立 —— 这条关系比某个具体数字更该保住。
var hud_margin_portrait: float = UITokens.SPACE_LG
## 横屏 HUD 距屏幕**右边 / 下边**的留白（逻辑px）—— 与棋盘横屏边距**同一档**。
## ★★ 为什么必须是**独立的一个量**（2026-10-16 用户口令「对局中按钮接近屏幕边缘，修一下」）：
##   横屏 HUD 此前是"拿**行宽预算**当偏移"用的（`position.x = vs.x - 320`），
##   而 320 实际是"这一行最多多宽"（见下面 `BTN_PAD_TIGHT` 那段四档实测）⇒
##   盒子右沿 = `vs.x - (320 − 行宽)`：行宽 305 时余 20px，套上主题样式后行宽 315
##   ⇒ **只剩 5px**（用户看到的"贴着屏幕边"）。
##   ⇒ 口径：**宽度预算 ≠ 边缘留白** —— 一个说"这行最多多宽"，一个说"离屏幕边多远"，
##     拿前者当后者就等于把两件事混成一个数。现在按"实测尺寸 + 本留白"反推。
##   ★ 取值 = `board_margin_landscape`：保住"**棋盘与 HUD 离屏幕边一样远**"这条既有视觉关系
##     （竖屏那边早就是这个口径，见 `hud_margin_portrait` 的注）⇒ 两者永远一起动。
##   ★ 常量与变量分开（与 `HUD_TOUCH_MIN_PORTRAIT` / `hud_btn_min_h_portrait` 同款）：
##     判据的**期望值**要取编译期字面量，不能取那个会被阴性对照改掉的变量。
const HUD_EDGE_MARGIN_LANDSCAPE: float = UITokens.BOARD_MARGIN_LANDSCAPE
var hud_landscape_margin: float = HUD_EDGE_MARGIN_LANDSCAPE

func hud_button_min_height() -> float:
	return hud_btn_min_h_portrait if use_portrait_canvas() else hud_btn_min_h_landscape

func hud_button_font_size() -> int:
	return hud_btn_font_portrait if use_portrait_canvas() else hud_btn_font_landscape

func hud_label_font_size(default_size: int) -> int:
	return hud_label_font_portrait if use_portrait_canvas() else default_size

## 解析 `WxH`（容忍空格、大写 X）。非法或过小一律返回 ZERO（= 当作没给）。
## 纯函数，不碰全局状态 —— headless 自检要能直接验它。
func parse_size_arg(s: String) -> Vector2i:
	var t: String = s.strip_edges().to_lower().replace(" ", "")
	var parts: PackedStringArray = t.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var w: int = int(parts[0])
	var h: int = int(parts[1])
	# 240 是下限：再小的话两个方向都退化成 0 像素，截出来的图没法看，不如当作参数写错
	if w < 240 or h < 240:
		return Vector2i.ZERO
	return Vector2i(w, h)

## 应用 `--winsize=` 覆盖：强制窗口模式（清掉 borderless）+ 设尺寸 + 居中。
func apply_debug_window_size() -> void:
	if debug_window_size == Vector2i.ZERO:
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(debug_window_size)
	center_window(debug_window_size)

const APPEARANCE_PATH: String = "user://appearance.cfg"

## 自检/截图专用的外观路径（`--apptest` 与「自动化运行改道」共用**同一份文件**）。
## ★ 为什么要有这个常量：自检必须走**真实交互路径**（否则测的不是那份代码），而真实交互路径里
##   就写着 `save_appearance()` ——「走真实路径」与「别碰用户配置」这两条规矩，只有在**写点改道**
##   这一个位置能同时满足。见 `save_appearance()` 开头那道闸。
const APPEARANCE_SELFTEST_PATH: String = "user://appearance_selftest.cfg"

# ---------------- 鼠标光标（三角刮刀，见 `美术素材清单.md` 与工作区 `瓷砖围棋_光标素材/`） ----------------
# 素材：`res://art/cursor/scraper_{32,48,64,96}.png`，同一份几何（`draw_cursor.py`）导出的四档。
# ★ 为什么放在 Autoload（而不是 game.gd / menu.gd 各给一套 @export）：
#   光标是**跨场景的全局表现**，菜单和对局必须一致；两处各写一份参数迟早分叉（本工程的老坑）。
#   Autoload 的 @export 在 Inspector 里不可编辑，所以这里用 var —— 运行期任意时刻可改，
#   改完调用 `apply_custom_mouse_cursor()` 立即生效。
const CURSOR_DIR: String = "res://art/cursor/"
const CURSOR_SIZES: Array[int] = [32, 48, 64, 96]

## 热区在图上的**归一化**位置（实测 0.0569 / 0.0458；32/48/64/96 四档换算后偏移 ≤0.5px）。
## ★ 为什么在**左上**：自定义光标与系统光标出现在同一个画面上，刀尖必须与系统箭头**同向**，
##   否则玩家会下意识按系统箭头的方向去点（用户实测反馈「光标做反了，尖尖应该向左上」）。
## ★ 为什么 x ≠ y：这个光标是**用户亲笔稿**（`D:/稿件/三角铲.drawio.svg`），刀轴不是 45°，
##   刀尖圆角的最外点在 x/y 上本来就不等距。→ 所以别再假设 `ratio.x == ratio.y`。
##   历史上那版（自己画的 S1，刀轴 45°）是对称的 0.088；两版不要互相套用。
## ★ 别"推"这个数，只有两个都想当然的公式（都错，都踩过）：
##   ① `(S-MARGIN)/S = 0.958` —— 那是**包围盒的另一角**。换朝向时忘了把对齐公式翻过来就这样，
##      热区跑到右下角。
##   ② `MARGIN/S = 0.042` —— 那是刀尖这一角的**包围盒极值**，但热区是**圆角之后**的最外点，
##      比极值再往里一点（实测 0.0569 / 0.0458）。
##   → 只能量：`draw_cursor.py --selfcheck` 会打印四档实测值。
const CURSOR_HOTSPOT_RATIO: Vector2 = Vector2(0.0569, 0.0458)

## 自检用的**木柄探针**位置（归一化，实测 = 木柄中心）。
## 为什么要有它：`--headless` 下没有光标渲染，唯一能自动验「热区压在刀尖而不是木柄上」的办法，
## 就是拿一个**已知是木柄**的点与热区做对照 —— 木色占比实测**木柄 96~100% / 刀尖 0%**。
## ★ 它跟素材绑定：改了木柄位置/比例就要重新量（`draw_cursor.py` 里能量出来）。
const CURSOR_WOOD_PROBE_RATIO: Vector2 = Vector2(0.697, 0.807)

## 热区判据的容差（像素）。判据见 `menu.gd::_cursor_self_test()` ④：
## 「热区必须是全图在**刀刃指向**上最外的那个点」。
## ★ 1.0 不是拍的，是量出来的：正确热区实测余量 −0.46…−0.08px（四档都 <0.5px），
##   而最近的错误热区（旧的 0.088 比例）余量 +2.43px，1.0 正好落在空档中间。
const CURSOR_TIP_SLACK_PX: float = 1.0

var cursor_enabled: bool = true     # 关掉即恢复系统箭头
## 32 / 48 / 64 / 96 四档（素材同源，见 `CURSOR_SIZES`）。
## ★ 2026-09-22 用户口令「放大两倍」：48 → **96**（现成的最大档，不必重画）。
##   起因：Windows 上这个位图是**按像素**交给系统的（不随 DPI 缩放），48px 在高分屏上偏小。
##   想回退：`--cursorsize=48`，或把这里的值改回 48。
var cursor_size: int = 96
## 最近一次成功应用的光标尺寸（-1 = 未应用）。仅供自检/调试读取。
var cursor_applied_size: int = -1
## 最近一次加载失败的原因（空串 = 无错），由自检读取做断言。
var cursor_last_error: String = ""


## 「指针大小」滑条的索引 ↔ 实际像素 —— 设置页与配置读回的**唯一换算**。
##
## ★★ 为什么滑条**只能走索引**、不许把它的 value 直接当像素用：
##    `cursor_texture_path()` 是按文件名拼的（`scraper_%d.png`），而素材只有 CURSOR_SIZES 这四档。
##    中间值（比如 55）`ResourceLoader.exists()` 会是 false ⇒ `apply_custom_mouse_cursor()`
##    只是 push_warning 然后**沿用系统光标** ⇒ 玩家看到的是「拖到中间，光标突然没了」
##    ——不报错、不崩溃、`exit=0`，是标准的**静默降级**。
##    所以换算必须收在这里当唯一真源，别让设置页自己拼尺码。
func cursor_size_for_index(i: int) -> int:
	return int(CURSOR_SIZES[clampi(i, 0, CURSOR_SIZES.size() - 1)])


## 反查：给定像素尺寸落在哪一档。**不在表里的值**（命令行 `--cursorsize=55` 手抖、
## 旧配置残留）落回**最接近**的一档，而不是报错 —— 光标是纯表现层，
## 「尺寸不那么精确」远比「没有光标」可接受。
func cursor_size_index(size: int = -1) -> int:
	var s: int = cursor_size if size <= 0 else size
	var idx: int = CURSOR_SIZES.find(s)
	if idx >= 0:
		return idx
	var best: int = 0
	var best_d: int = 2147483647
	for i in CURSOR_SIZES.size():
		var d: int = absi(int(CURSOR_SIZES[i]) - s)
		if d < best_d:
			best_d = d
			best = i
	return best


func cursor_texture_path(size: int = -1) -> String:
	var s: int = cursor_size if size <= 0 else size
	return "%sscraper_%d.png" % [CURSOR_DIR, s]


## 把 `tex` 的尺寸按 `CURSOR_HOTSPOT_RATIO` 换算成像素热区。**纯函数**（不碰全局状态）
## —— 自检要在 headless 下验它，而 headless 下无法真正设置光标。
func cursor_hotspot_for(tex: Texture2D) -> Vector2i:
	if tex == null:
		return Vector2i.ZERO
	var sz: Vector2 = tex.get_size()
	return Vector2i(int(round(sz.x * CURSOR_HOTSPOT_RATIO.x)),
					int(round(sz.y * CURSOR_HOTSPOT_RATIO.y)))


## 应用自定义光标。可反复调用（换尺寸 / 开关都走这里）。
## headless 下直接返回：没有窗口就没有光标，省掉一次无谓的纹理加载。
func apply_custom_mouse_cursor(size: int = -1) -> void:
	var s: int = cursor_size if size <= 0 else size
	cursor_applied_size = -1
	cursor_last_error = ""
	if not cursor_enabled:
		Input.set_custom_mouse_cursor(null)
		return
	if DisplayServer.get_name() == "headless":
		return
	var path: String = cursor_texture_path(s)
	if not ResourceLoader.exists(path):
		cursor_last_error = "找不到光标素材 %s" % path
		push_warning("[cursor] " + cursor_last_error + "，沿用系统光标")
		return
	var tex: Texture2D = load(path)
	if tex == null:
		cursor_last_error = "光标素材加载失败 %s" % path
		push_warning("[cursor] " + cursor_last_error + "，沿用系统光标")
		return
	var sz: Vector2 = tex.get_size()
	if sz.x <= 0.0 or sz.y <= 0.0 or sz.x > 256.0 or sz.y > 256.0:
		cursor_last_error = "光标尺寸 %s 非法（须为 1..256）" % sz
		push_warning("[cursor] " + cursor_last_error + "，沿用系统光标")
		return
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, cursor_hotspot_for(tex))
	cursor_applied_size = s
	print("[cursor] 自定义光标 %s（%dx%d，热区 %s）" % [
		path, int(sz.x), int(sz.y), str(cursor_hotspot_for(tex))])


## 退出前把自定义光标**主动摘掉**。
##
## 为什么需要：`Input` 会一直持有光标纹理的 RID 到进程结束，而 `RenderingServer` 先于它销毁
## → 非 headless 退出时固定刷三条 ERROR（`1 RID allocations ... TextureE were leaked` /
## `Texture with GL ID of N: leaked M bytes` / `RenderingServer::get_singleton() is null`）。
## 实测 A/B：带光标 3 条、`--nocursor` 0 条 → 是这里引入的。
## 本工程靠 grep 日志里的 ERROR 当信号，常驻假 ERROR 会侵蚀这个信号，所以必须清掉。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		if cursor_applied_size >= 0 and DisplayServer.get_name() != "headless":
			Input.set_custom_mouse_cursor(null)
			cursor_applied_size = -1

## 「上一局的选项」（棋盘 / 大小档 / 帽子种类 / 难度 / 对战方式）—— 菜单开局时落盘，
## 下次菜单 _ready() 读回，于是「下完棋回菜单」仍停在上一局的设置上（2026-09-19 用户要求）。
const LAST_MATCH_PATH: String = "user://last_match.cfg"
## 默认主题名（必须是 PRESETS 里存在的名字）。集中在这里，避免各处硬编码主题名。
## ★ 2026-10-08：主题改**单档**（不再分「·浅 / ·深」两版）⇒ 默认名由「宣纸·浅」改为「宣纸」。
const DEFAULT_PRESET: String = "宣纸"

## ═══ 精简版（GitHub 开源包）═══════════════════════════════════════════════════
## 由导出预设的 `custom_features="lite"` 打开（见 export_presets.cfg 的 "Windows Desktop (Lite)"）。
## **默认 false ⇒ 编辑器 / Steam 完整版的行为逐字不变**（这是本开关唯一的回归保证）。
##
## 精简掉三块：**棋谱（含复盘）/ 联机（Steam）/ 主题切换（只剩「经典」= DEFAULT_PRESET）**。
## ★ 只关"入口 + 落盘"，**不删实现代码**：完整版必须继续在同一份源码上开发，
##   否则开源版和 Steam 版会分叉成两个工程（历史上拆过一次，代价是两份都要维护）。
## ★ 判定必须**只读这一处**：`OS.has_feature()` 在 var 初始化期就可用（Autoload 实例化早于场景），
##   别在各 UI 里分散写 `OS.has_feature("lite")` —— 那样一改预设名就会静默半边生效。
var lite: bool = OS.has_feature("lite")

## 棋子色默认值（= `game.gd` 两个 `@export` 的初值）。主题不写 `stone_*` 键时回退到它们。
const STONE_BLACK_DEFAULT: Color = Color(0.06, 0.06, 0.08)
const STONE_WHITE_DEFAULT: Color = Color(0.90, 0.90, 0.95)

## 预设配色方案（bg=背景 / board=棋盘 / line=轮廓 / accent=标题色 / stone_black·stone_white=棋子色【可选】）。
##
## ★ 2026-10-08 改版：**每个主题只有一个配色**（不再分浅/深两档），`tier` 字段随之取消。
##   保留黄（宣纸）/ 绿（竹青）/ 粉（粉黛）；其余按四路风格重做 ——
##   现代（藏青·绛红·焦糖）· 雅致（天青·藕荷）· 霓虹（霓虹·赛博，**带荧光棋子**）· 暗色（墨绿·玄石）。
##
## ★★ 五条硬约束（`--apptest` 逐主题验收；改色前先读这里，阈值都是**量出来的**）：
##   ① 棋子 vs 棋盘       ≥ 1.35 —— 棋子得看得见
##      ★ 主题自带棋子色时**按它自己的棋子色算**，不假设黑白 —— 这正是霓虹能成立的前提。
##   ② 棋盘 vs 背景       ≥ 1.35 —— 棋盘边界不能糊进背景（实测旧版最小值 1.362）
##   ③ 标题(accent) vs 背景 ≥ 3.0  —— WCAG 正文可读线
##   ④ 两枚棋子色差       ≥ 0.60（RGB 欧氏距离）—— 敌我棋子必须分得清
##      ★ 用**色差**而不是亮度对比：荧光绿 vs 荧光粉亮度对比只有 2.0，但色相相反、
##        肉眼极易区分 ⇒ 拿亮度当"能不能分辨"会给出**反向结论**。
##   ⑤ accent 与 board 各自两两不撞车（跨主题）
##
##   ★★ ① 是本版**比旧判据更准**的地方（旧判据的盲区，值得记住）：旧版只卡
##      「棋盘明度 ∈ (0.18, 0.82)」——一个**为黑白子估的近似**。实测它放过了「竹青·浅」：
##      它的白子对棋盘只有 **1.342**（<1.35），肉眼几乎糊住，而旧判据照样判绿。
##      新判据直接量"该主题的棋子 vs 该主题的棋盘"，于是把这一档抓了出来
##      ⇒ 竹青的棋盘已相应加深（0.565,0.694,0.608 → 0.290,0.620,0.520）。
##   ★ 配色验证脚本（工作区，**不进工程根**）：`瓷砖围棋_临时输出/theme_design.py`
##     —— 它**照抄** Godot 的 `get_luminance()`（= sRGB 直接加权和，**不是** WCAG 线性亮度）
##     与上面五条阈值，外加按钮 / 浮层 / 提示点三条**派生链**。
##     改色后先跑它验收，别靠肉眼。
##     配套：`apply_palette.py`（配色表 → 回写 `.tres`）、`make_preview.py`（生成新旧对照预览页）。
##
## accent 是该主题的**专属标题色**（每个都不一样）；配色被用户改过后
## `appearance_preset` 与实际值不再匹配 ⇒ 设置页显示「自定义」。
## ═══ 主题数据已迁到 `res://themes/*.tres`（2026-10-20 第 1 步）═══
## 每个 `.tres` 是一个 `BoardTheme`（见 `board_theme.gd`）。**文件名前缀 00..11 决定显示顺序**。
## 改色 = 在检查器里打开对应 .tres 改；不要再往代码里加颜色常量。
## ★ 迁移时的逐字段对拍：12 个 .tres 与旧硬编码表 **0 差异**（生成脚本回读比对，见 2026-10-20 记忆）。
##
## ══════════ 2026-10-20 第 2 步：12 套主题**配色重做**（观感，不改语义）═══
##
## ## 起因
## 用户报「现在的主题色搭配我不是很满意」。体检发现：改动前的 12 套**全部通过**上面五条
## 硬约束与三条派生闸门 —— 也就是说问题**不在闸门上**，而在"闸门管不到的地方"。
##
## ## ★★ 头号病灶：**按钮文字的"明度死区"**（这次最值钱的一条，值得记住）
## `button_palette()` 的填充色就是**主题棋盘色**，而填充色里的字由 `readable_ink_on()` 挑：
##   · 填充明度 L ≤ 0.16 → 配近白字；
##   · 填充明度 L ≥ 0.45 → 配近黑字；
##   · **L ∈ (0.16, 0.45) 是死区**：近白字够不到 4.5（顶天 3.9），近黑字又太重
##     ⇒ 引擎只能退回**近黑**（实测字明度 0.004~0.014）⇒ 观感是"黑字压在深色底上"。
## 而**对比度闸门照样判绿**（近黑对深底仍有 4.77）—— 典型的"闸门过了、眼睛不认"。
## 改动前**6 套浅色主题的"选中按钮"全部落在死区**（选中态 = 实心 accent），
## **3 套暗色主题的"普通按钮"落在死区**（绛红 / 墨绿 / 玄石 —— 它们的棋盘 L 只有 0.39）。
##
## ## ⇒ 两条配色口径（本次全部改色都按它走）
##   ① **浅底主题的 accent 一律压到 L ≤ 0.16**：accent 同时是"标题色"（要对背景 ≥3.0
##      ⇒ 必须深）和"选中按钮实心填充"（里面的字要 ≥4.5 ⇒ 填充必须够深才能配白字）。
##      两个要求在 L>0.16 上**互斥** ⇒ 浅底主题的 accent 只能是深色，
##      换来的是"深底 + **白字**"的选中按钮。
##   ② **暗底主题的棋盘一律提到 L ≥ 0.45**（霓虹 / 赛博除外：它们的棋盘够暗 ⇒ 白字成立）：
##      棋盘色同时是按钮填充色 ⇒ 亮棋盘 ⇒ 按钮变成"亮底 + 深字"，不再是"深底 + 黑字"。
##
## ## 其余三条
##   ③ 棋盘是画面主角 ⇒ 彩度整体提高（竹青 0.19→0.41、粉黛 0.25→0.44、天青 0.29→0.46、
##      藕荷 0.29→0.40），背景退到近乎无彩（s ≤ 0.16），靠**色相**区分主题而不是靠明度。
##   ④ 粉黛按名字取义：粉 = 胭脂木棋盘，黛 = **靛蓝色标题色**（"粉黛"本是两色）。
##   ⑤ 竹青按用户反馈继续往**黄绿**回（不偏蓝），彩度一次补足。
##
## ## 改完后
## 12 套主题仍全绿（`theme_design.py` 实测：棋盘/背景最小 1.435、白子/棋盘最小 1.413、
## 标题/背景最小 4.599、按钮字 ≥4.770、面板/浮层全部达标），
## 而"选中按钮字明度"从 **0.004~0.014 变成 0.899**（近黑 → 近白），
## "暗色三主题的普通按钮字明度"从 0.042 变成 0.056~0.066（落在**亮**棋盘上）。
## 新旧对照预览页：`瓷砖围棋_临时输出/主题配色预览.html`。
##
## ★★ 竹青棋盘的沿革（改它之前必读；原来写在硬编码行旁边，随迁移搬到这里）：
##   ① 2026-10-08：为过「白子 vs 棋盘 ≥ 1.35」这条判据，棋盘从 (0.565,0.694,0.608) 加深到
##      (0.290,0.620,0.520)。加深时 **R 从 0.565 掉到 0.290**，饱和度骤增
##      ⇒ 视觉从「灰绿」变成「青」—— 中文里常被直接说成"变蓝了"。
##   ② 2026-10-20（第 1 步）：用户报「感觉竹青比以前蓝了，要改回去」⇒ 恢复旧色相 ×0.955
##      （白子/棋盘 1.400、棋盘/背景 1.421，两条判据都过）。
##      ⚠️ 不能逐位改回旧值：实测 (0.565,0.694,0.608) 的白子/棋盘 = **1.342 < 1.35**，
##        `--apptest` 当场判红（当年加深就是为了这个）。
##   ③ 2026-10-20（第 2 步，本次配色重做）：棋盘 = (0.362,0.616,0.392) ——
##      色相回到 **127°**（比 ② 再偏黄绿 13°，离"蓝"更远），彩度 0.41（② 只有 0.19），
##      白子/棋盘 **1.600**、棋盘/背景 **1.637** —— 两条判据的余量都比 ② 大。
##      ⇒ "别偏蓝"这条用户反馈与"提高彩度"这次要求，在这一档上**同时成立**。
const THEMES_DIR: String = "res://themes"

## 已加载的主题（**惰性**：第一次访问时扫目录，见 `_ensure_themes()`）。
var _themes: Array[BoardTheme] = []

## 扫描 `THEMES_DIR` 下的 `.tres`，按**文件名**排序后加载。
## ★ 排序不能省：`DirAccess.get_files()` 的顺序在不同平台/不同时刻不保证一致，
##   而它直接决定设置页色块的排列（用户可见）。
## ★ 加载失败**不静默**：不是 BoardTheme 的文件 push_error —— 否则少一个主题只会表现为
##   "设置页少一个色块"，没人会去查。
## ★★ 2026-10-21 导出 demo0.8 时抓到的**只在导出包里发作**的真 bug（编辑器里永远绿）：
##   导出时 `editor/export/convert_text_resources_to_binary`（默认开）会把每个 `.tres`
##   转成 **`.res` + 一个 `.tres.remap` 指针**，于是 `get_files()` 报出来的是
##   `00_宣纸.tres.remap` —— 只认 `.tres` 结尾的老写法**一个主题都收不到**。
##   现场：导出包 `--menutest` ⑩k 报「主题 0 个 · 样本 0 处」、`--apptest` 报
##   「预设=false」「色块按钮=false」，主题名退化成空串（`「宣纸」→「」`）——
##   而**编辑器里 33 条全绿**。同一份代码在两种运行方式下结论相反。
##   ⇒ 剥掉 `.remap` 尾巴再判断；`load()` 仍用**剥完的路径**，让 ResourceLoader 自己
##     跟着 remap 找到真正的 `.res`（那正是 remap 存在的意义，**别手工拼 `.res`**）。
##   ⚠️ 不去关那个导出选项来"绕过"：关掉它等于把这份依赖藏起来，下次谁再动导出配置
##     就会以同样的方式静默失效 —— 代码自己要能扛住两种布局。
func _ensure_themes() -> void:
	if not _themes.is_empty():
		return
	var d: DirAccess = DirAccess.open(THEMES_DIR)
	if d == null:
		push_error("主题目录打不开：%s（主题会一个都没有）" % THEMES_DIR)
		return
	var files: Array[String] = []
	for f in d.get_files():
		# 导出包里的名字是 `.tres.remap`；编辑器里是 `.tres`。两种都要认。
		var nm: String = f
		if nm.ends_with(".remap"):
			nm = nm.substr(0, nm.length() - ".remap".length())
		if nm.ends_with(".tres") and not files.has(nm):
			files.append(nm)
	if files.is_empty():
		# 空目录**必须出声**：否则"导出包里主题为 0"会一路静默到玩家看到界面才被发现。
		push_error("主题目录里一个 .tres 都没找到：%s" % THEMES_DIR)
		return
	files.sort()
	for f in files:
		var res: Resource = load("%s/%s" % [THEMES_DIR, f])
		if res is BoardTheme:
			_themes.append(res as BoardTheme)
		else:
			push_error("主题文件不是 BoardTheme：%s" % f)
	# ★ 精简版只留「经典」：**在本列表上收口**，而不是去 UI 层藏色块 ——
	#   `themes()` / `preset_names()` / `preset_name_groups()` / `find_theme()` 全部由它派生，
	#   在这里切一刀，设置页、自检、迷你棋盘预览就同时只剩一个主题（不各写一遍）。
	#   其余 `.tres` 仍留在包里（每个几 KB），只是**没有任何代码路径能选中它们**。
	if lite and _themes.size() > 1:
		var keep: Array[BoardTheme] = []
		for t in _themes:
			if t.display_name == DEFAULT_PRESET:
				keep.append(t)
		if keep.size() == 1:
			_themes = keep
		else:
			# 「经典」自己都找不到时**不许静默**：宁可报红，也不要让精简版变成"一个主题都没有"。
			push_error("精简版找不到默认主题「%s」，主题表未收窄" % DEFAULT_PRESET)

## 全部主题（只读；设置页与判据用）。
func themes() -> Array[BoardTheme]:
	_ensure_themes()
	return _themes

## 按名字取主题 —— **唯一查找入口**。
## ★ 抽它的理由：改造前有 **7 处**各写一遍 `for p in PRESETS: if p["name"] == ...`，
##   改一处漏一处就静默不一致（本工程「两处同口径」的老坑）。
## 找不到返回 `null`，由调用方决定是"回退"还是"报错"。
func find_theme(pname: String) -> BoardTheme:
	_ensure_themes()
	for t in _themes:
		if t.display_name == pname:
			return t
	return null

func _ready() -> void:
	load_appearance()
	# 光标的**命令行覆盖**（须放在 `--` 之后）：`--nocursor` 恢复系统箭头（A/B 对照），
	# `--cursorsize=32|48|64|96` 换尺寸。以上都只影响本次进程，不写进任何配置。
	for a in OS.get_cmdline_user_args():
		if a == "--nocursor":
			cursor_enabled = false
		elif a.begins_with("--cursorsize="):
			cursor_size = int(a.substr("--cursorsize=".length()))
		elif a.begins_with("--winsize="):
			debug_window_size = parse_size_arg(a.substr("--winsize=".length()))
		elif a.begins_with("--canvassize="):
			# 商店页素材用：`--canvassize=1920x1080 --winsize=1920x1080` ⇒ 原生 1920×1080 截图。
			# 本分支必须与 `--winsize=` 同处（都在 `apply_design_canvas()` **之前**）——
			# 晚了就会先按旧基座排一轮版，而且**不报错**，只是截图里排版是错的。
			canvas_size_override = parse_size_arg(a.substr("--canvassize=".length()))
		elif a == "--portrait":
			portrait_override = 1
		elif a == "--landscape":
			portrait_override = 0
		# ⚰️ 2026-10-17 墓碑（名字不许回收）：这里原有 `--mobileui` / `--desktopui`
		#   两个 flag（写 `mobile_menu_override`）。手机版整套退役 ⇒ 一起删除。
	# 已保存的显示模式在启动时应用一次（headless 自检下没有真实窗口，跳过）
	if DisplayServer.get_name() != "headless":
		if debug_window_size != Vector2i.ZERO:
			apply_debug_window_size()
		else:
			apply_window_mode()
	# ★ 画布基座必须在**任何场景 _ready() 之前**套上（本 Autoload 的 _ready 早于主场景）。
	#   headless 下也要套：自检要用它验「竖屏分支真的选对了画布」（`--portrait`）。
	apply_design_canvas()   # ★ S30 锚点：画布基座唯一落点（必须在上面那些覆盖解析之后）
	apply_ui_theme()        # ★ 必须在画布基座之后：主题的默认字号按横/竖两套阶梯取值
	if DisplayServer.get_name() != "headless":
		# 自定义鼠标光标（三角刮刀）。Autoload 的 _ready 早于任何场景，所以菜单与对局
		# 一起生效；`Input` 的光标是全局状态，切场景不会丢，无需在 game.gd / menu.gd 重复设置。
		apply_custom_mouse_cursor()

## 预设名列表（供设置页生成按钮）
func preset_names() -> Array[String]:
	var names: Array[String] = []
	for t in themes():
		names.append(t.display_name)
	return names

## 预设名**按组**返回：`[[组0的名字...], [组1的名字...]]`，供设置页 / 手机选项层决定**排几行**。
## ★ 2026-10-08 主题改单档后**恒为一组**（旧版是 [[浅色系...], [深色系...]] 两行）。
## ★ 为什么不干脆删掉这一层、各处直接用 `preset_names()`：**三处**调用点都靠"分组"
##   决定排几行 / 几个分节 —— `menu.gd` 的设置页与 `--apptest` 判据、`menu_model.gd::theme_sections()`。
##   删掉要同时改三处；保留它则"改版"只动真源一处。
## ★ 名字跟着语义走（旧名 `preset_names_by_tier` 已无 tier 可依，留着就是名不副实）。
func preset_name_groups() -> Array:
	return [preset_names()]

## 取预设的配色（不改变当前状态）：返回 {"bg","board","line","accent","stone_black","stone_white"}
## 供设置页把主题按钮画成色块（不能靠 apply_preset 再读回——那样会污染当前配色）
## 以及菜单迷你棋盘的棋子色（霓虹主题下预览也该是荧光子，否则预览与实际不符）。
func preset_colors(pname: String) -> Dictionary:
	var t: BoardTheme = find_theme(pname)
	if t == null:
		return {}
	return {
		"bg": t.bg,
		"board": t.board,
		"line": t.line,
		"accent": t.accent,
		"stone_black": t.effective_stone_black(STONE_BLACK_DEFAULT),
		"stone_white": t.effective_stone_white(STONE_WHITE_DEFAULT),
	}

## 应用预设配色；成功返回 true
func apply_preset(pname: String) -> bool:
	var t: BoardTheme = find_theme(pname)
	if t == null:
		return false
	bg_color = t.bg
	board_color = t.board
	line_color = t.line
	accent_override = t.accent
	tile_color_a = board_color   # 兼容：联机快照 tile_colors 随棋盘色
	tile_color_b = board_color
	# ★ 棋子色是主题的一部分（`has_stone_colors=false` 的主题**跟随全局默认**，不是写死）。
	#   必须与棋盘色**同一处**设置：霓虹主题的棋盘很深，若棋子色没跟着切，
	#   那套深色棋盘配黑白子的观感就是"没做完"，而这在**只有一个主题**出问题时最易漏。
	stone_color_black = t.effective_stone_black(STONE_BLACK_DEFAULT)
	stone_color_white = t.effective_stone_white(STONE_WHITE_DEFAULT)
	appearance_preset = pname
	return true

## 判断当前配色是否仍等于某个预设（用于显示「自定义」）
func matches_preset() -> String:
	var t: BoardTheme = find_theme(appearance_preset)
	if t == null:
		return ""
	if bg_color.is_equal_approx(t.bg) \
			and board_color.is_equal_approx(t.board) \
			and line_color.is_equal_approx(t.line) \
			and accent_override.is_equal_approx(t.accent) \
			and stone_color_black.is_equal_approx(t.effective_stone_black(STONE_BLACK_DEFAULT)) \
			and stone_color_white.is_equal_approx(t.effective_stone_white(STONE_WHITE_DEFAULT)):
		return appearance_preset
	return ""

## 依据背景亮度返回可读的前景文字色（浅背景→深字，深背景→浅字）
func ink_color() -> Color:
	return ink_for_bg(bg_color * bg_brightness)

## 由**任意**背景色推可读前景色（纯函数，不改状态）。
## ★ `ink_color()` 用它；"主题选项层里那些色块按钮上的字"也用它 —— 两边各写一遍阈值的话，
##   某个主题下色块上的字会看不清（浅底配浅字），而且只在**那一个主题**下出现（静默、难查）。
func ink_for_bg(c: Color) -> Color:
	return Color(0.10, 0.10, 0.12) if c.get_luminance() > 0.45 else Color(0.88, 0.90, 0.94)

## WCAG 式对比度，**用在 Godot 的 `get_luminance()` 上**。
## ★ 这是本工程既有的口径（`luminance` 是 sRGB 直接加权和，不是 WCAG 的线性相对亮度），
##   别"顺手改正"成线性亮度 —— 那会让所有历史阈值（1.35 / 3.0）失去意义。
## ★ 收进真源的理由：`--apptest` 判据、手机菜单、以及任何"这颜色在这块底上看得清吗"的地方
##   都要用它，各写一份就是本工程「两处同口径」的老坑（只改一处 ⇒ 静默不一致）。
func contrast_of(a: Color, b: Color) -> float:
	var la: float = a.get_luminance()
	var lb: float = b.get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## 两色在 RGB 空间的欧氏距离 —— 用于"两枚棋子能不能分清"。
## ★ 为什么不用对比度：荧光绿 vs 荧光粉的**亮度**对比只有 2.0，但色相相反、肉眼极易区分 ⇒
##   拿亮度当"能否分辨"会给出**反向结论**（把最容易分辨的一对判成最危险的）。
func rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## 强调色（标题 / 分组名 / 提示）：
## 优先用当前主题的**专属标题色**（PRESETS 的 accent，每个主题各不相同）；
## 未设（自定义配色/无 accent 字段）时按背景明暗回退：浅背景深金、深背景浅金，保证可读。
func accent_color() -> Color:
	if accent_override.a > 0.0:
		return accent_override
	var lum: float = bg_color.get_luminance() * bg_brightness
	return Color(0.55, 0.40, 0.10) if lum > 0.45 else Color(0.96, 0.88, 0.62)

# ---------------- 弹出面板（ESC 暂停 / ESC 退出确认）配色与样式 ----------------
# ★ 踩过的坑（2026-09-22 用户口令「ESC 界面的文字颜色提亮」）：
#   accent_color() / ink_color() 都是**对着棋盘背景**推导的（一个按 bg_color 的亮度回退深浅）。
#   而这两个 ESC 面板是引擎默认主题的 PanelContainer —— **深色半透明**，是压在棋盘上的另一张面。
#   浅色主题下两者恰好都偏深：accent = 深棕 (0.55,0.40,0.10)、ink = 近黑 (0.10,0.10,0.12)。
#   真机截图实测：正文对面板底的对比度只有 **1.06** —— 等于没有字（标题 2.88 也偏弱）。
#   所以「对背景对比度已断言达标」这句话对**棋盘**成立、对**面板**不成立。修法有两条缺一不可：
#     ① 给面板一个**不透明（0.94）的固定底色** → 底色确定，对比度才是个能断言的量
#        （半透明面板的底色随背后的棋盘漂移，任何常量断言都是假的）；
#     ② 文字色**从主题色出发按亮度阶梯提亮到实测达标**（色相保住 → 仍是「主题专属色」）。
#   ★ 判据与 menu.gd 里「棋盘 vs 背景 ≥1.35」是同一把尺子（WCAG）：(亮+0.05)/(暗+0.05)。
#   ★ 两套 ESC 面板（game.gd / menu.gd）是互不相干的代码 —— 历史上同样的毛病修过两遍，
#     所以配色/样式/探针**一律放这里**，两处只调用，不各自写一份。
## ★ **不透明**是刻意的（alpha = 1.0），不是随手写的：
##   面板半透明时，实际渲染底色 = 自己的底 × alpha + 「已变暗 45% 的棋盘」× (1-alpha)
##   → 底色随背后棋盘漂移 → 任何常量对比度断言都是**假的**（实测 0.94 时标称 0.110、
##   真机渲染 0.1252，标题对比度从 4.55 掉到 4.15）。要断言得准，底色就必须是确定的。
##   观感上 0.94 与 1.0 几乎无差（背后本来就压着 45% 的黑遮罩），换来的是判据成真。
## ⚠️ 以下四个常量自 2026-10-15 起**已退役**：面板底色不再钉死成这套固定深蓝灰，
##   改由 `overlay_surface()` 从主题推导（下面是完整的推导链与理由）。
##   保留它们是为了给 `--apptest` 留一条**历史阴性对照**（"旧的固定深灰按钮 vs 旧面板底
##   只有 1.254 < 1.35"——那条断言至今有效，是阈值不许被偷改的证据）。
const DIALOG_BG: Color = Color(0.10, 0.11, 0.14, 1.0)
## 正文/标题文字对底色的最低对比度（WCAG AA 正文档）
const DIALOG_TEXT_MIN_CONTRAST: float = 4.5
const DIALOG_BTN_BG: Color = Color(0.14, 0.15, 0.19)

# ══════════ 浮层面板底色：从"固定深色"改成"主题推导的确定色"（2026-10-15）══════════
#
# ## 用户口令
# 「统一配色与字体应用，esc界面还没有用上主题色、设置按钮等大多数按钮也没有用上主题色」
#
# ## 与上面那段 2026-09-22 坑注释的关系：**不冲突，是把它的结论推进一步**
#
# 那段结论有两条：① 面板底色必须**确定**（不透明），否则对比度是个假量；
# ② 面板上的文字必须**对着面板底色另行拟合**。
# 两条都对，且至今不变。但它当时把"确定"实现成了**一套与主题无关的固定深蓝灰**，
# 于是修好了可读性、又制造了新的不一致：面板成了整个界面里**唯一不属于本主题**的一块。
# 在「宣纸」这种暖色主题上，棋盘是暖金、面板是冷蓝灰——两个世界；换个主题，面板纹丝不动。
# ⇒ 本次把底色从"固定常量"改成"**从主题推导出来的确定值**"：仍然是确定的（照样可断言），
#   但属于本主题。坑注释里那条铁律（能断言的前提是底色确定）**没有被动过**。
#
# ## 推导链（三步，每步都有闸；逐主题扫描的判据在 --apptest）
#   ① 起点 = 主题**棋盘色**（`board_color`）—— 与按钮同门，色调天然一致；
#   ② 推离**面板背后那张面**，直到对比度 ≥ `PANEL_SCRIM_MIN`；
#   ③ 面板上的标题 / 正文 / 按钮，全部对着**面板底色**重新拟合（4.5 / 1.35）。
#      这一步一步都不能省：底色一换，原来"对棋盘达标"的色就不再达标（2026-09-22 的病根）。
#
# ## ★ 阈值为什么是 2.0（不是按钮档的 1.35，也不是 3.0）
#   · 1.35 **不够**：面板是整块大面积，"糊"在棋盘上比小按钮明显得多；
#   · 3.0 会让**深色主题翻车**：深色底在 45% 遮罩后 L≈0.025，要 3.0 面板必须
#     L≥0.31 ⇒ "深色主题弹出一块浅色面板 + 深色文字"，极性整个反过来；
#   · 2.0 是"足够分离"与"14 套主题都保持深色面板 + 亮字"之间的边界：
#     浅色主题（底色 L≈0.5）压暗到 L≈0.22；深色主题（L≈0.025）**提亮**到 L≈0.10
#     —— 注意是提亮，但落点仍在深色区间，所以亮字照旧成立（见下面的方向口径）。
#   ⇒ `--apptest` 把 14 个主题的落点与最差读数全打出来；哪天有主题越界，当场红。
const PANEL_SCRIM_MIN: float = 2.0

## 面板底色的**去饱和**比例（向"同明度的灰"靠）。
## ★ 为什么需要它：面板是一大块纯色，满饱和度的深棕/荧光绿铺满半屏会"闷"且抢戏；
##   向同明度灰靠一点，既压住面积感，又保住主题色相（`Color(l,l,l)` 的明度恒等于 l，
##   所以这一步**不改明度**，上面算好的对比度全部不变）。
const PANEL_DESAT: float = 0.18

## 拟合时的**余量**（乘在阈值上）。
##
## ★★ 为什么必须有：拟合若精确落在阈值上，判据那句 `值 < 阈值 ⇒ 红` 就被**浮点末位**决定 ——
##    实测踩到过：打印的是 `4.500`（三位的四舍五入）而实际值 `4.4999998`，判据**判红**，
##    红点指向"文字对比度不达标"，而真因是"拟合贴着边界做、边界又被浮点抖动"。
##    这种红极难查（读数看着完全达标）。
## ⇒ 口径：**判据阈值不放松**（仍然是 4.5 / 2.0），但**做出来的东西比要求高 FIT_MARGIN 倍**。
##    余量只影响拟合目标，不影响任何断言；把边界从"末位决定"变成"有可见余量"。
const FIT_MARGIN: float = 1.06

## 把 `c` 换到目标明度 `lp` 上：**保住色相**（按比例缩放 / 朝白插值），明度精确落在 `lp`。
## `desat` > 0 时再向"同明度的灰"靠一点（面板用；见 `PANEL_DESAT`）。
## ★ 不用"一级级 darkened/lightened 逼近"：那种写法**未必够得着**，跑满级数会返回一个
##   不达标色，而"没达标"与"方向选错"在返回值上长得一模一样。第一版就是这么把宣纸推成
##   白面板、把正文推成与面板同明度（L 0.215 vs 0.220，对比度 1.02 = 隐形）的。
##   解等式 + 一次到位：落点可预测、可断言。
func _tint_to_luminance(c: Color, lp: float, desat: float = 0.0) -> Color:
	var out := Color(c.r, c.g, c.b, 1.0)
	var lb: float = out.get_luminance()
	if lb <= 0.002:
		out = Color(lp, lp, lp, 1.0)          # 基底本来就近黑：只能取灰
	elif lp <= lb:
		out = out * (lp / lb)                  # 压暗：按比例缩放 ⇒ 明度线性落到 lp
	else:
		out = out.lerp(Color(1, 1, 1, 1), (lp - lb) / maxf(0.002, 1.0 - lb))
	if desat > 0.0:
		var lg: float = out.get_luminance()
		out = out.lerp(Color(lg, lg, lg, 1.0), desat)
	out.a = 1.0
	return out

## 页面底色 = 背景色 × 明度档。**"控件所在表面"的唯一真源。**
## ★★ 为什么必须收成一处（2026-10-15）：这个乘积原先在三个地方各写了一遍
##   （menu.gd 的 `_draw()` 画背景、game.gd 的 `draw_rect()` 画背景、以及"按钮要从表面上
##   浮出来"的调色板入参）。三份里只要有一份不跟着 `bg_brightness` 走，就会在**调过背景明度**
##   的机器上出现"按钮与背景同色 ⇒ 看不见"——而那台机器不是开发机 ⇒ **默认明度 1.0 下
##   三者恒等，这类错在本地永远复现不出来**（本工程在字体那件事上刚付过一次同款的账）。
## ★★ `a = 1.0` 不能省（2026-10-15 实测踩到）：`Color * float` 连 **alpha 一起乘**
##   ⇒ 明度 0.6 时这个乘积的 alpha 也是 0.6。菜单 `_draw()` 早就手工补了一句 `bg.a = 1.0`
##   （当年的现场补丁），但对局场景那句 `draw_rect(background_color)` 没有 ——
##   更糟的是我把它当"表面色"传给按钮/输入框样式当盒底之后：**盒子会变成半透明**
##   （明度 1.0 下 a=1 ⇒ 本地永远看不出来，正是这一类"只在非默认档出现"的静默坏法）。
##   ⇒ 在这里一次性定为不透明：**"页面底色"这个量天生就是不透明的**（它是要被填出来的那张面）。
func page_surface() -> Color:
	var c: Color = bg_color * bg_brightness
	c.a = 1.0
	return c

## 面板背后那张面的**实际**底色。
## ★ 为什么不是 `bg_color * bg_brightness`：面板压在棋盘上，而两处面板（game.gd / menu.gd）
##   在弹面板时都会先盖一层 `Color(0,0,0,0.45)` 的遮罩 ⇒ 眼睛看到的底是**遮罩之后**的。
##   拿没遮罩的底去算对比度，等于把"面板与背景的分离感"高估 —— 判据必须量眼睛看到的那个量。
##   `darkened(0.45)` = 各分量 ×0.55，与 `(1-0.45)` 的黑遮罩同口径。
func panel_backdrop() -> Color:
	return page_surface().darkened(0.45)

## 浮层面板的**确定**底色（alpha 恒 1.0，理由见上）。
##
## ## ★★ 为什么不是"拿棋盘色直接推、够分离就原样用"（第一版就是这么写的，被判定站逮住）
## 棋盘色本身可能是**浅色**（藏青那套的棋盘色就是浅蓝白）：它对着遮罩后的底**天然就够 2.0**，
## 于是"够分离就早返回"直接吐出一块 **L=0.509 的浅色面板** —— 深色主题弹出一块浅面板，
## 面板上的字怎么拟合都不好看（白字 1.88 / 黑字得推翻整个极性）。
## ⇒ 口径改成：**面板恒落在深色区间**（≤ `PANEL_LUM_MAX`），深浅只由"能不能分离"决定，
##   不由棋盘色自己的明暗决定。这样 14 套主题的面板**观感是同一族**（深色 + 亮字），
##   而"属于哪个主题"由色相承担。
##
## ## ★★ 上限 0.16 是怎么定出来的（不是拍的）
## 面板要装得下**亮字**（`dialog_text_color()` 是柔和近白，L≈0.913）：
##   contrast = (0.913+0.05)/(Lp+0.05) ≥ 4.5 ⇒ **Lp ≤ 0.164**
## 同时面板对背景要分离 ≥2.0。两条件一起看：
##   · 亮底主题（遮罩后 L≈0.5）：压暗到 0.16 时分离 = 0.55/0.21 = **2.62** ✓（远超 2.0）；
##     而"刚好 2.0"的落点其实是 0.2245 —— 那正是**死区**：亮字在那儿只有 **3.57**（提亮到纯白也就
##     3.89），暗字又要求面板 ≥0.175…… 实测报出来的「正文 1.018」就是被推到了这块死区里。
##   ⇒ 上限必须**低于** 0.164，取 **0.16**（留一点浮点余量），两个条件同时成立。
##   · 暗底主题（遮罩后 L≈0.085）：压暗侧"刚好 2.0"的落点 = 0.0175，远低于上限 ⇒ 上限不触发，
##     面板接近黑、亮字对比度 14+ ⇒ 也是对的（那种主题下"面板浮起来"靠的是 1px 主题色描边，
##     不靠明度差 —— 极暗底上想靠明度区分，要么面板近黑、要么面板翻亮，后者会毁掉深色主题）。
const PANEL_LUM_MAX: float = 0.16

func overlay_surface() -> Color:
	var host: Color = panel_backdrop()
	var lh: float = host.get_luminance()
	# ★★ 这里两个阈值**分工不同，不能混用**（混用会撞上"上限"与"分离度"的冲突带，实测踩到）：
	#   · **方向可行性**用真实阈值 `PANEL_SCRIM_MIN`：它决定"压暗这条路走不走得通"；
	#   · **落点目标**用带余量的 `thr_fit`：它只决定"压到多暗/提多亮"。
	#   混用（可行性也用余量）会把 lh≈0.054 那一段主题误判成"压暗走不通"⇒ 改走提亮侧
	#   ⇒ 面板被抬到 L=0.171，**越过 `PANEL_LUM_MAX`**（实测：绛红 0.171 vs 上限 0.16 判红）。
	var thr_fit: float = PANEL_SCRIM_MIN * FIT_MARGIN
	var lp: float
	if (lh + 0.05) / 0.05 >= PANEL_SCRIM_MIN:
		# 压暗侧：能压到纯黑就够分离 ⇒ 面板恒为深色（14 套主题观感统一的那条路）
		lp = (lh + 0.05) / thr_fit - 0.05
	else:
		# 提亮侧：棋盘底本身极暗（压到黑也够不着分离）⇒ 只能提亮，落点仍取"刚好达标"
		lp = thr_fit * (lh + 0.05) - 0.05
	lp = clampf(lp, 0.0, PANEL_LUM_MAX)                # 恒不越过"深色面板"上限
	return _tint_to_luminance(board_color, lp, PANEL_DESAT)

## 对比度（WCAG 口径，与棋盘/背景断言同一把尺子）
func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = a.get_luminance()
	var lb: float = b.get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## 面板标题色 = 当前主题强调色**拟合到对面板底色达标**（色相保住 ⇒ 仍是主题专属色）。
## ★ 2026-10-15 改用 `_fit_ink_on()`（**双向**）而不是 `_fit_contrast()`（只提亮）：
##   提亮型是"面板恒为深色"这个前提下的写法。现在面板底色由主题推出来，
##   前提不再由常量保证 ⇒ 拟合必须**跟着底色走**，否则又是一个"只在一半主题上成立"的实现。
##   （面板落点仍以深色为主，所以浅色主题下这一行的结果与改动前**逐字相同**：
##     深棕 accent 对深色面板偏暗 → 往亮推 → 得到那支被提亮的暖金。）
func dialog_title_color() -> Color:
	return _fit_ink_on(accent_color(), overlay_surface(), DIALOG_TEXT_MIN_CONTRAST)

## 面板正文色 = 柔和近白拟合到达标（深色面板下几乎不需要动）。
func dialog_text_color() -> Color:
	return _fit_ink_on(Color(0.90, 0.92, 0.96), overlay_surface(), DIALOG_TEXT_MIN_CONTRAST)

## 面板按钮的文字色 = **按钮自己那个填充色**上的 ink。
## ★★ 口径：直接取 `button_palette()["ink"]`，**不能**再写"近白提亮到达标"——
##   按钮填充色现在是主题棋盘色（浅色主题下是浅褐），近白字压上去只有 ~1.5，
##   而 `_fit_contrast()` **只会提亮**，提到底也还是白 ⇒ 恒不达标（判据必红）。
##   调色板里的 ink 是按"能暗能亮"的 `_fit_ink_on()` 推出来的，这里必须是它。
func dialog_button_font_color() -> Color:
	return button_palette(overlay_surface())["ink"]

## 按钮内边距（横, 竖）——**两档，不是两个魔法数**。
## ★ 为什么必须分档（2026-10-15 实测）：把页面档套到"一行摆好几个按钮"的地方会**撑宽整行**，
##   而对局 HUD 那一行的**宽度预算是硬的**（它要跟"距屏幕右边 32px"一起塞进右半屏）⇒
##   横屏 1152 的画布上，末位那个「返回菜单」会被推出右沿。那不是配色问题，是**布局被配色
##   改动带塌了**。
##   ⚠️ 2026-10-16 起"宽度预算"不再是那个已删的常量 `hud_landscape_right = 320`：行宽现在由
##     `_refit_hud()` 用 `get_combined_minimum_size()` **实测**，边距是另一个量
##     （`hud_landscape_margin`）。**"这一行有多宽"约束没变，变的是它从哪来。**
##   ⇒ 口径：**表单/面板里的按钮用页面档**（有空间，圆润好看），
##     **一行里的按钮（HUD / 复盘工具条）用紧凑档**（横向空间是硬约束，只换颜色不动尺寸）。
##   ★ 紧凑档取 8/8 = 引擎默认主题当时的实测内边距 ⇒ 这些按钮的**盒子大小与改动前逐位相同**，
##     于是既有几何判据（`--portraittest` ⑤/`--browsetest` ⑪a/⑪b）量到的仍是原值。
const BTN_PAD_PAGE: Vector2 = Vector2(16.0, 9.0)
const BTN_PAD_COMPACT: Vector2 = Vector2(8.0, 8.0)
## 紧档 = **引擎默认主题当时的实测内边距**（4/4）＋我们的 1px 描边。
## ★ 它是为对局 HUD 准备的：那一行的**总宽**必须压在"右半屏能放下的量"之内 ——
##   四档内边距实测（`--portraittest`，2026-10-15）：
##     无样式（引擎默认）= 305px ✓｜紧档 = 315px ✓｜紧凑档 = 345px ✗｜页面档 = 435px ✗
##   （当日的口径是"塞进 `hud_landscape_right = 320`"；那个常量已于 2026-10-16 删除，
##     见上方墓碑 —— **行宽 315 这个既成事实不变**，所以这条实测记录仍然有效。）
##   ⇒ 只有"紧档及以下"能塞进 320。用 4/4 而不是"干脆不套样式"：颜色/描边/五个状态都要，
##     缺的只是那点内边距 —— 而内边距是**布局量**，不是配色量。
const BTN_PAD_TIGHT: Vector2 = Vector2(4.0, 4.0)

## 浮层面板/按钮的圆角半径（**唯一真源**）。
## ★ 判据拿它当"这支 stylebox 到底是不是我们建的"的**签名**：引擎默认主题的按钮圆角是 3，
##   所以"只套了字色、盒子还留在引擎默认主题上"这种半吊子接线能被当场认出来
##   （只看颜色的话，两者可能碰巧接近 ⇒ 判据漏判）。
const DIALOG_CORNER: float = 8.0

func _dialog_box(bg: Color, border: Color, mx: float, my: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(DIALOG_CORNER))
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb

## 给弹出面板套底色/圆角/描边/内边距。描边用**提亮后的标题色**（浅色主题下原 accent 是
## 深棕，描在深色面板上等于没有），保证任何主题下面板边界都看得见。
## ★ 2026-10-15：底色与描边都改成**主题推导**（`overlay_surface()`），不再用固定深蓝灰。
func style_dialog_panel(panel: PanelContainer) -> void:
	var tc: Color = dialog_title_color()
	panel.add_theme_stylebox_override("panel",
		_dialog_box(overlay_surface(), Color(tc.r, tc.g, tc.b, 0.55), 24.0, 18.0))

## 给弹出面板里的按钮套扁平样式（不依赖引擎默认主题 —— 默认主题随版本/后续加 gui/theme 会变）。
##
## ★★ 2026-10-15 重写：原来是**一套与主题无关的固定深灰**（`DIALOG_BTN_*` 四个常量），
##    与"界面其余部分都已经主题化"直接冲突（用户口令：「esc界面还没有用上主题色」）。
##    现在颜色全部取自 `button_palette(overlay_surface())` —— 与主菜单/设置页/大厅**同一个真源**。
##    规格仍是**紧凑档**（内边距 14/8，比页面按钮的 16/9 小一档）：弹窗里的按钮一行并排三个，
##    用页面档会把面板撑宽。两档共用同一份**状态矩阵**（下面五个态一个都不少）。
##    ⇒ 颜色统一、规格分档，这正是设计文档 §6.2 的口径（合并规格 ≠ 合并尺寸）。
func style_dialog_button(btn: Button) -> void:
	var p: Dictionary = button_palette(overlay_surface())
	btn.set_meta(BTN_META_HOST, overlay_surface())
	btn.set_meta(BTN_META_STATE, BTN_STATE_NORMAL)
	btn.add_theme_stylebox_override("normal", _dialog_box(p["fill"], p["border"], 14.0, 8.0))
	btn.add_theme_stylebox_override("hover", _dialog_box(p["fill_hover"], p["border_sel"], 14.0, 8.0))
	btn.add_theme_stylebox_override("pressed", _dialog_box(p["fill_press"], p["border_sel"], 14.0, 8.0))
	# ★ `disabled` 是本次**补上**的：旧版只有四个态，禁用态一直落在引擎默认主题上
	#   （面板上出现过"一块灰盒子"，与旁边的主题色按钮不像一家人）。
	btn.add_theme_stylebox_override("disabled",
		_dialog_box(p["disabled_fill"], Color(p["disabled_ink"].r, p["disabled_ink"].g,
			p["disabled_ink"].b, 0.45), 14.0, 8.0))
	# focus 框**不能**再用不透明底：会盖住 hover/pressed 的底色（焦点态与鼠标态叠一起）。
	# 这里只给全透明底 + 亮描边，效果是「多一圈亮边」。
	btn.add_theme_stylebox_override("focus",
		_dialog_box(Color(0, 0, 0, 0), Color(p["ink_sel"].r, p["ink_sel"].g, p["ink_sel"].b, 0.9),
			14.0, 8.0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(k, p["ink"])
	btn.add_theme_color_override("font_disabled_color", p["disabled_ink"])

## ══ 主题色按钮（2026-10-08 第三轮）════════════════════════════════════════════
## 用户口令：「主菜单以及其他的所有按钮我都想改一下，抛弃现在的落子按钮，改用**主题色相关的普通按钮**」。
## ★★ **唯一真源**：主菜单（自绘）/ 设置页 / 棋谱库 / 联机大厅 / 弹窗 / 手机菜单**全部**从这里取色。
##    各处自己拼一次深浅 = 本工程的「两处同口径」老坑（改一处 ⇒ 另一处静默不一致）。
##
## 派生规则（每条都有对比度闸兜底，不是审美说了算）：
##   ① 未选 fill = 主题**棋盘色** —— 用户拍板「未选 board 底」；按钮与菜单背景密铺同门，
##      但按钮是**规整圆角矩形 + 实心**，不再是被落子黑砖染色的瓷砖；
##   ② 未选字 = 该 fill 上的 ink（`ink_for_bg` 选方向，再逐级提到达标）；
##   ③ 选中 fill = 主题**标题色 accent**（用户拍板「选中实心 accent」），字 = accent 上的 ink；
##   ④ ★ 按钮 fill 对**所在表面**（面板底 / 页面底）必须 ≥ 1.35 ——
##      深色主题的棋盘色本身就是深色（霓虹 0.10 明度），直接铺在深底上**按钮会消失**；
##      这条闸把这个坑钉在派生层，而不是等某个页面出问题再各自打补丁；
##   ⑤ 禁用 = 去饱和 + 向表面靠拢（一眼看出不可点），且**静态不呼吸**（旧砖族的呼吸描边已退役）。
const BTN_SURFACE_MIN_CONTRAST: float = 1.35
const BTN_TEXT_MIN_CONTRAST: float = 4.5

## 控件**按下/按下态**对所在表面的最低对比度（比静止态低一档）。
## ★ 为什么允许更低：按下是**瞬时**态，而且按下的语感就是"陷向表面"（`fill_press` = fill 往表面
##   方向走一小步）。若按下态也要求 1.35，那就等于要求"按下时也得浮起来"——与按钮的 press 语义
##   打架，最后只能靠把 fill 抬高来糊过去（那又会让静止态过重）。
## ★ 但它**必须有闸**：`fill_press` 是往表面方向走的量，走过头就是"按下瞬间看不见了"。
const BTN_PRESS_MIN_CONTRAST: float = 1.15

## 控件**禁用态**对所在表面的最低对比度（三档里最低的一档）。
## ★ 禁用态的**设计意图就是贴着表面**（`disabled_fill` = fill 向表面插值 0.62，"灰下去"而不是
##   "换个颜色"）⇒ 拿 1.35 去要求它，等于要求"禁用的控件比正常还显眼"，方向反了。
## ★ 但它也得有闸：这条闸只拦**彻底看不见**那一档（对比 = 1.0 就是"与表面同色 = 控件没了"）。
## ★ 与"按下态"同样的做法：由本常量**反向约束派生**（见 `native_body_roles()` 里对禁用档的
##   `_fit_away_from`）⇒ 实测值必然 ≥ 阈值且有 `FIT_MARGIN` 余量，判据不会卡在浮点末位上。
const BTN_DISABLED_MIN_CONTRAST: float = 1.10

## 禁用态**文字/勾/手柄**对其填充的最低对比度（比正文的 4.5 低很多）。
## ★ 禁用态本来就"糊"，4.5 是给"要读的内容"定的档；禁用控件上的字只要"看得出有字"即可。
const BTN_DISABLED_TEXT_MIN_CONTRAST: float = 2.2

## 禁用态的**两支色**（填充 + 其上的墨色）—— **唯一真源**，按钮与原生控件本体共用。
## ★★ 为什么填充也要过一遍 `_fit_away_from`（2026-10-15）：`fill.lerp(host, 0.62)` 是"向表面插值
##   62%"，在浅色主题上它与表面的对比只有 **1.13** ⇒ 拿它去画勾选框的方块，方块**几乎看不见**
##   （勾选框的方块没有描边兜底，而按钮的禁用态至少还有轮廓）。闸门取 `BTN_DISABLED_MIN_CONTRAST`
##   （比静止态的 1.35 低一档 —— 禁用态本来就该更贴向表面，方向不能反）。
## ★ 墨色**必须从拟合后的填充**再拟合一次：填充变了、原来的墨色可能就不达标了（极性还可能翻）。
func disabled_pair_of(fill: Color, host_bg: Color) -> Array[Color]:
	var df: Color = _fit_away_from(fill.lerp(host_bg, 0.62), host_bg, BTN_DISABLED_MIN_CONTRAST)
	return [df, _fit_ink_on(ink_for_bg(df), df, BTN_DISABLED_TEXT_MIN_CONTRAST)]

## 上一步落子提示圆点对**所在棋子**的最低对比度。
## ★★ 为什么这条必须单独成闸：旧实现是**硬编码反色**（黑子画白点 / 白子画黑点），
##    实测在「霓虹」1.23 /「赛博」1.22（**< 1.35，肉眼几乎看不见**）—— 那两套的"黑方"是
##    荧光绿 / 琥珀，本身比白点还亮 ⇒ 反色规律对"高亮棋子"整个失效。
##    阈值取 3.0（正文档级）而不是 1.35：圆点直径只有棋子半径的 0.3，边界清晰度要求更高。
const DOT_MIN_CONTRAST: float = 3.0

## 把 `ink` 顺着**它自己相对底色那一侧**逐级推到对比度达标（底色亮 → 往暗推，反之往亮推）。
## ★ 与 `_fit_contrast()` 的分工：那个只会「提亮」（面板文字用，底色恒为深色面板）；
##   这个要能**双向**走 —— 按钮底色可能比字还亮（深色主题的 accent 实心按钮）。
## 把 `ink` 推到对于 `bg` 对比度 ≥ `thr`。**方向由"哪一侧够得着"决定**，落点**解等式**一步到位。
##
## ## 为什么不是"一级级 darken/lighten 逼近"（2026-10-15 实测踩到）
## 旧实现是"按 ink 落在 bg 哪一侧定方向 + 每级 0.07 + 最多 20 级"。它有两个洞：
##   ① **够不着**：近白 ink 压在 L=0.22 的中明度底上，往亮推极限只有 3.89 < 4.5；
##   ② **20 级走不完全程**：从 L=0.913 压到"暗字的达标点 L≈0.01"需要约 63 级，
##      20 级只走到 **0.208** —— 恰好落在面板明度 0.220 旁边 ⇒ 实测对比度 **1.018**
##      （正文隐形）。这正是 `--apptest` 新增的浮层判据逮到的那个数。
## ⇒ 现在：先解出两侧各自的"刚好达标"明度，取够得着的一侧，用 `_tint_to_luminance()` 一次到位。
##   （"刚好达标"= 最小改动 ⇒ 尽量保住 ink 自己的色相。）
##
## ★ `max_steps` 参数已删：全部调用点都没显式传过它（核对过 10 处），
##   留着一个拧不动的旋钮等于给后人一个假的调节点（§33）。
func _fit_ink_on(ink: Color, bg: Color, thr: float) -> Color:
	var out := Color(ink.r, ink.g, ink.b, 1.0)
	if contrast_ratio(out, bg) >= thr:
		return out
	var lh: float = bg.get_luminance()
	# 两侧各自"刚好达标"的目标明度（由 contrast 等式解出）。
	# ★ 阈值乘 `FIT_MARGIN` 再解 —— 落点比要求高一档，判据不会卡在浮点末位上（见 FIT_MARGIN 的注）；
	#   早返回那句仍然按**真实阈值**判：本来就达标的 ink 不做无谓改动（少动 = 少变色）。
	var thr_fit: float = thr * FIT_MARGIN
	#   提亮侧：(L + 0.05)/(Lb + 0.05) ≥ thr  ⇒  L ≥ thr·(Lb + 0.05) − 0.05
	#   压暗侧：(Lb + 0.05)/(L + 0.05) ≥ thr  ⇒  L ≤ (Lb + 0.05)/thr − 0.05
	# ★ 踩过的坑（第一版）：提亮侧写成了 `1.05/thr − 0.05`，那是**纯白 ink**（L=1.0）的极限值，
	#   不是"当前这支 ink"的目标。当 ink 本身比那个值更暗（例：宣纸的深棕 accent L=0.41、
	#   而纯白极限是 0.183）时，这句会把 ink **往暗里推**到 0.183 ⇒ 实测对比度 1.111（标题发灰）。
	#   ⇒ 目标必须由 bg 解出，与"ink 现在多亮"无关。
	var up_target: float = thr_fit * (lh + 0.05) - 0.05      # 提亮侧：明度提到这个值即达标
	var dn_target: float = (lh + 0.05) / thr_fit - 0.05       # 压暗侧：明度压到这个值即达标
	var dark_ok: bool = dn_target >= 0.0
	var light_ok: bool = up_target <= 1.0
	var go_dark: bool = out.get_luminance() <= lh
	# 默认沿"ink 本来所在的那一侧"（改动最小、色相最保真）；那一侧够不着才换侧。
	if go_dark and not dark_ok and light_ok:
		go_dark = false
	elif (not go_dark) and not light_ok and dark_ok:
		go_dark = true
	if go_dark:
		return _tint_to_luminance(out, clampf(dn_target, 0.0, lh))
	return _tint_to_luminance(out, clampf(up_target, lh, 1.0))

## 把 `c` 推离 `host` 直到两者对比度 ≥ thr（**方向 = 远离 host**，不是一律提亮）。
## 用于「按钮 fill 必须从它所在的表面上浮出来」这一条。
func _fit_away_from(c: Color, host: Color, thr: float, max_steps: int = 20) -> Color:
	var out := Color(c.r, c.g, c.b, 1.0)
	var i := 0
	while contrast_ratio(out, host) < thr and i < max_steps:
		# 比 host 亮就继续提亮，比 host 暗就继续压暗（远离 = 对比度单调增）
		out = out.lightened(0.06) if out.get_luminance() >= host.get_luminance() else out.darkened(0.06)
		i += 1
	return out

## 「在这块面上写字，该用什么色」的**唯一真源**（按钮正文 / 按钮选中态 / 输入框正文都用它）。
## ★★ 为什么不能只信 `ink_for_bg()` 的 0.45 分界（2026-10-08 实测踩中，写在这里免得第二处再踩）：
##   白/黑的最优分界是 **L≈0.179**（解 `1.05/(L+0.05) = (L+0.05)/0.05`），而 `ink_for_bg()`
##   用的是 0.45 ⇒ 落在 [0.18, 0.45) 的中亮度面一律被判"该配亮字"：白字压上去只有
##   **2.335（墨绿）**，而同一块面配黑字是 **9.0** —— `--apptest` 的「字」项当场咬住。
##   口径：**先主题色**（保持同门），推不到 `BTN_TEXT_MIN_CONTRAST` 才退到白/黑里更优的一侧。
## ★ 2026-10-15 收成函数：原来这段 6 行在 `button_palette()` 里写了**两遍**（正文 / 选中态），
##   输入框要再用一次就是第三遍 —— 本工程"两处同口径各写一份"的老坑（只改一处 ⇒ 静默不一致）。
func readable_ink_on(surface: Color) -> Color:
	var ink: Color = _fit_ink_on(ink_for_bg(surface), surface, BTN_TEXT_MIN_CONTRAST)
	if contrast_of(ink, surface) >= BTN_TEXT_MIN_CONTRAST:
		return ink
	var iw: Color = _fit_ink_on(Color(1, 1, 1), surface, BTN_TEXT_MIN_CONTRAST)
	var ib: Color = _fit_ink_on(Color(0, 0, 0), surface, BTN_TEXT_MIN_CONTRAST)
	return iw if contrast_of(iw, surface) >= contrast_of(ib, surface) else ib

## 套样式时写回控件的元数据键（**判据只认这两个键，不许自己猜调用点传了什么表面**）。
const BTN_META_HOST: StringName = &"_theme_host"
const BTN_META_STATE: StringName = &"_theme_state"
const BTN_STATE_NORMAL: String = "normal"
const BTN_STATE_SELECTED: String = "selected"

## 输入框**占位符**的对比度下限（对盒底）。比正文的 4.5 低一档是**刻意的**：
## 占位符是提示不是内容，做到 4.5 需要把它提到接近正文的浓度 ⇒ "还没输入的字"与"已经输入的字"
## 长得一样（那才是真的用坏）。2.5 是"看得见、但一眼知道是提示"的那一档。
const INPUT_PLACEHOLDER_MIN_CONTRAST: float = 2.5

## 输入框**盒底**的口径（真源；`probe_line_edit_theme()` 也读它）。
## ★★ 「凹进去」= 比页面底**更暗**，与按钮的"凸出来"正好相反（这是输入区该有的语感）。
##   第一版写成"页面底 向 **墨色** 插值 12%" —— 那是**朝文字色靠**：一边写字、一边把字背后的底
##   涂成字色。实测（`--menutest` ⑮ 明度 0.6 档）盒底 L 从 0.544 被拉到 0.491，而墨色只有 L 0.101，
##   正文对比度 **3.57 < 4.50** 当场判红。方向改对（远离文字色、往下压）后 0.6 档 4.91、1.0 档 5.63。
## ★ 深浅只用一个乘数（`darkened(0.12)` 与 `lerp(黑, 0.12)` 逐通道恒等）：浅主题下是"纸上略深的一块"、
##   深主题下是"更暗的一块"，两个方向都读作输入区。
func input_box_fill(host_bg: Color) -> Color:
	return host_bg.darkened(0.12)

## 输入框**正文**墨色 —— 由**盒底**决定，不由页面底决定（两个面不是一回事）。
## ★★ 必须在盒底上**重挑一次**：墨色本是对**页面底**可读的那一支（浅主题近黑、深主题近白），
##   而盒底只比页面底深 12% ⇒ 同一支墨色直接拿来用就不够了（实测 3.57）。口径与按钮完全一致
##   （`readable_ink_on()`）⇒ "输入框里的字"与"按钮上的字"是同一把尺子挑出来的。
func input_box_ink(fill: Color) -> Color:
	return readable_ink_on(fill)

## 输入框**占位符**墨色 = 同一支墨色向盒底**淡出**，再拟到"看得见"的那一档
## （`INPUT_PLACEHOLDER_MIN_CONTRAST`，比正文低一档 ⇒ 一眼看得出是提示、不是已输入的内容）。
## ★★ **不透明（a=1.0）是刻意的**：第一版写成 `Color(ink, 0.55)`（靠 alpha 变淡），而判据量的是
##   `get_luminance()`（**不含 alpha**）⇒ 占位符与正文印出**同一个读数**（实测两条都是 3.57）
##   ＝ 这一条根本没有独立牙齿，"占位符看不清"永远抓不到。两条路：判据先按 alpha 复合成
##   "眼睛看到的色"再量，或把"淡"烘进颜色本身。取后者 —— 判据量的量与眼睛看到的是**同一个量**
##   （本工程在 ESC 面板上刚为"半透明让断言变假"付过一次账）。
func input_box_placeholder_ink(fill: Color, ink: Color) -> Color:
	return _fit_ink_on(fill.lerp(ink, 0.55), fill, INPUT_PLACEHOLDER_MIN_CONTRAST)

## 输入框（`LineEdit`）的**主题化样式**（真源，各页面不许各写一遍）。
## ★★ 为什么必须连**底色**一起主题化（2026-10-15 目检实测）：先只改字色的话，字色是按
##   "对页面底可读"算出来的（宣纸下是近黑），而 `LineEdit` 的盒子还是**引擎默认的深灰**
##   ⇒ 近黑的字压在深灰盒上（实测底色 (111,108,99)）＝ 字与盒一起变糊。字色与盒色是**一对**，
##   只改一半就是把可见性问题从"盒不跟主题"换成"字看不清"。
## ★ 描边不给满墨：1px 的近黑/纯白框会把输入框画成铁盒子；但也不能不拟 ——
##   页面档盒底对页面本身只差 1.10，边界全靠这根线说清楚 ⇒ 从"半淡的墨色"拟合到对盒底 ≥1.6。
func style_theme_line_edit(le: LineEdit, host_bg: Color) -> void:
	var fill: Color = input_box_fill(host_bg)
	var ink: Color = input_box_ink(fill)
	var border: Color = _fit_ink_on(fill.lerp(ink, 0.45), fill, 1.6)
	var focus: Color = _fit_ink_on(accent_color(), fill, BTN_SURFACE_MIN_CONTRAST)
	le.add_theme_stylebox_override("normal", _dialog_box(fill, border, 10.0, 6.0))
	le.add_theme_stylebox_override("focus", _dialog_box(fill, focus, 10.0, 6.0))
	le.add_theme_stylebox_override("read_only", _dialog_box(fill, border, 10.0, 6.0))
	le.add_theme_color_override("font_color", ink)
	le.add_theme_color_override("font_placeholder_color", input_box_placeholder_ink(fill, ink))
	le.add_theme_color_override("caret_color", accent_color())
	le.add_theme_color_override("selection_color", Color(accent_color().r, accent_color().g,
		accent_color().b, 0.35))
	# 记下表面：与按钮共用 `BTN_META_HOST` 这个键（一个"表面"键，判据只认它）
	le.set_meta(BTN_META_HOST, host_bg)

## 同上的**读回**（判据用）：读控件上真实生效的盒底/字/占位符，并用记下的表面算出期望值。
## ★ 期望值全部由**上面那批真源函数**算出（铁律 §70：判据不许重实现被测逻辑）——
##   判据只管"控件上的读数 == 真源给的读数"这件事本身。
func probe_line_edit_theme(le: LineEdit) -> Dictionary:
	var out: Dictionary = {
		"has_normal": false, "fill": Color(0, 0, 0, 0), "ink": Color(0, 0, 0, 0),
		"ph": Color(0, 0, 0, 0), "corner": -1.0, "host": page_surface(), "styled": false,
		"fill_expect": Color(0, 0, 0, 0), "ink_expect": Color(0, 0, 0, 0),
		"ph_expect": Color(0, 0, 0, 0),
	}
	var nb: StyleBoxFlat = le.get_theme_stylebox("normal") as StyleBoxFlat
	if nb != null:
		out["has_normal"] = true
		out["fill"] = nb.bg_color
		out["corner"] = float(nb.corner_radius_top_left)
	out["ink"] = le.get_theme_color("font_color")
	out["ph"] = le.get_theme_color("font_placeholder_color")
	out["styled"] = le.has_meta(BTN_META_HOST)
	if out["styled"]:
		out["host"] = le.get_meta(BTN_META_HOST)
	var fe: Color = input_box_fill(out["host"])
	out["fill_expect"] = fe
	var ie: Color = input_box_ink(fe)
	out["ink_expect"] = ie
	out["ph_expect"] = input_box_placeholder_ink(fe, ie)
	return out

## 选一支"对 a 与 b **都**看得清"的墨色（取候选里**较劣那一侧**对比度最大的那支）。
## ★ 唯一的用户是**滑杆手柄**：手柄**骑在**轨道与进度条的**交界处**，底盘是哪一支取决于它当前
##   在哪，"两种底都看得清"正是这个位置的真实要求。判据照同一条要求断。
## ★★ 勾选框的勾**不用**这条（2026-10-15 目检导出图标时纠正）：`checked` 那张图里勾是画在
##   **方块上**的（方块 = 面积大那档，实测 127/16 像素）⇒ 勾应当取"压在方块上的墨色"，
##   也就是调色板里那支 `ink_sel`（= `readable_ink_on(fill_sel)`）—— 与按钮选中态同一对色。
##   一开始按"勾在空心环里、底下是页面"去做，结果勾被选成近黑、压在深棕方块上只有 2.3。
func best_two_way_ink(a: Color, b: Color) -> Color:
	var cands: Array[Color] = [Color(1, 1, 1), Color(0, 0, 0), readable_ink_on(a), readable_ink_on(b)]
	var best: Color = cands[0]
	var best_min: float = -1.0
	for c in cands:
		var m: float = minf(contrast_of(c, a), contrast_of(c, b))
		if m > best_min:
			best_min = m
			best = c
	return best

# ================= 原生控件**本体**：勾选框 / 开关 / 滑杆 / 滚动条 =================
# ★★ 为什么这几族要单独做（2026-10-15）：按钮与输入框的样式都是我们自己套上去的，而这四族的
#   **本体**（方块的色与勾、开关的胶囊与手柄、滑杆的轨道与手柄、滚动条的槽与滑块）全部来自
#   **引擎默认主题的图标与样式盒** —— 它们既不在 `_draw()` 里，也不在任何我们写的样式函数里。
#   所以"统一配色"做完按钮之后，它们仍然是引擎灰：棋谱页 402 个方块、设置页两根滑杆一条
#   滚动条，一屏里最扎眼的就是它们（用户口令：「设置按钮等大多数按钮也没有用上主题色」）。
#
# ★★ 手法：**只重新上色，不重画形状**。
#   · 引擎图标 = 一到两档色 + alpha，**形状信息全在 alpha 里** ⇒ 按亮度把像素聚成档、把档映射到
#     我们的调色板、再把每档的 alpha 峰值归一到 1.0（边缘渐变按比例保留 = 抗锯齿不丢）。
#   · **哪一档该用哪支主题色是从图里量出来的**（面积大的那档 = 盒/轨道，另一档 = 勾/手柄），
#     不依赖"我记得 CheckBox 的 checked 是白环黑勾"这类记忆 ⇒ 将来 Godot 重画图标也不会错。
#   · 样式盒同理：`duplicate()` 一份引擎的、**只改颜色**（内边距/圆角/扩张边距一个字节不动）。
#   ⇒ 形状风险为 0（不可能把 ✓ 画歪），几何风险也为 0（尺寸/内边距/行高全继承）。
#
# ★★ 一族一个身份、一套判定：`native_body_roles()` 是**唯一**的"名字 → 颜色"真源，
#   套样式、探针、判据三边都读它（铁律 §18/§70：连续族参数化，别把同一张表写三遍）。

## 角色表的键前缀：`sb:` 样式盒 / `ic:` 图标（两族名字空间可能重名，必须分开）。
const NATIVE_SB_PREFIX: String = "sb:"
const NATIVE_IC_PREFIX: String = "ic:"

## 某类控件**本体**的角色表（真源）：键 → [主色, 副色]。
## · `sb:<样式盒名>` → [底色, 描边色]；· `ic:<图标名>` → [主档色(面积大的那档), 副档色]。
## 只有引擎默认主题里**真存在**的名字会被列出（名字一律从 `ThemeDB` 枚举，不硬编码契约名 §78）。
func native_body_roles(cls: String, host_bg: Color) -> Dictionary:
	var def: Theme = ThemeDB.get_default_theme()
	var p: Dictionary = button_palette(host_bg)
	# 轨道/槽 = 与输入框同一个"凹"口径，**再拟合到对表面可辨**。
	# ★ 为什么输入框的盒底不需要这一步、这里需要：输入框有 1px 主题描边兜底（边界由线说清），
	#   而滑杆的轨道与滚动条的槽在引擎里**描边宽度是 0**（探针实测 `bw=0`）—— 只靠底色说话，
	#   12% 的"略暗"在浅色主题上只有 1.13，轨道等于看不见。
	var groove: Color = _fit_away_from(input_box_fill(host_bg), host_bg, BTN_SURFACE_MIN_CONTRAST)
	var prog: Color = p["fill_sel"]                  # 已做过"远离表面"拟合的实心主题色
	var is_check: bool = cls == "CheckBox" or cls == "CheckButton"
	var is_slider: bool = cls.ends_with("Slider")
	var out: Dictionary = {}
	for n in def.get_stylebox_list(cls):
		var sb: StyleBox = def.get_stylebox(n, cls)
		if sb is StyleBoxEmpty:
			continue     # 空盒（勾选框/开关的 normal/pressed/hover/…）：本体在图标里，这里没有可染的
		var nm: String = String(n)
		var bg: Color = Color(0, 0, 0, 0)            # 默认透明 ⇒ 只在描边环（焦点环）上出现
		var bd: Color = _fit_ink_on(accent_color(), groove, BTN_SURFACE_MIN_CONTRAST)
		if is_slider:
			if nm.begins_with("grabber_area_highlight"):
				bg = prog.lightened(0.10)
			elif nm.begins_with("grabber_area"):
				bg = prog
			elif nm.begins_with("slider"):
				bg = groove
		elif cls.ends_with("ScrollBar"):
			if nm.begins_with("scroll_focus"):
				pass                                  # 焦点环：透明底 + accent 描边
			elif nm.begins_with("scroll"):
				bg = groove
			elif nm == "grabber_pressed":
				bg = p["fill_press"]
			elif nm.begins_with("grabber_highlight"):
				bg = p["fill_hover"]
			elif nm.begins_with("grabber"):
				bg = p["fill"]
		out[NATIVE_SB_PREFIX + nm] = [bg, bd]
	for n2 in def.get_icon_list(cls):
		var src: Texture2D = def.get_icon(n2, cls)
		if src == null or src.get_width() <= 0 or src.get_height() <= 0:
			continue     # 引擎没给这张（滚动条的 increment/decrement 就是 0×0 ⇒ 引擎根本不画）
		var nm2: String = String(n2)
		var main: Color
		var alt: Color
		if is_check:
			# 状态由**图标名**分词得到（名字来自 `get_icon_list()`，不是我们硬写的）
			var on: bool = nm2.contains("checked") and not nm2.contains("unchecked")
			# ★★ 勾/手柄取**调色板里那一对**（未选 `fill`/`ink`、选中 `fill_sel`/`ink_sel`、禁用一双灰）
			#   —— 与按钮**完全同一个语言**（§7）。为什么不是"对两种底都兼顾"的黑/白（第一版）：
			#   目检导出图标实测，`checked` 那张图里**勾是画在方块上的**（方块 127 像素 / 勾 16 像素）
			#   ⇒ 勾底下就是方块本色，取 `ink_sel`（近白压深棕 = 4.5+），而"兼顾"那支会选成近黑，
			#   压在深棕方块上只有 2.3 —— 糊在方块里。
			if nm2.contains("disabled"):
				main = p["disabled_fill"]
				alt = p["disabled_ink"]
			else:
				main = p["fill_sel"] if on else p["fill"]
				alt = p["ink_sel"] if on else p["ink"]
		elif is_slider:
			if nm2.contains("disabled"):
				main = p["disabled_ink"]
			elif nm2.contains("highlight"):
				main = best_two_way_ink(groove, prog.lightened(0.10))
			else:
				main = best_two_way_ink(groove, prog)
			alt = main
		else:
			main = p["fill"]
			alt = p["fill"]
		out[NATIVE_IC_PREFIX + nm2] = [main, alt]
	return out

## 把引擎的样式盒**复制一份只改颜色**（几何不动）。
## ★ `duplicate()` 不能省：引擎默认主题里的样式盒是**共享资源**，就地改色等于把 `ThemeDB` 的
##   默认主题改了 ⇒ 全工程（含自检、含将来任何新界面）一起变，而且**看不出是谁改的**。
func _recolor_stylebox(src: StyleBox, bg: Color, border: Color) -> StyleBox:
	var sb: StyleBox = src.duplicate()
	if sb is StyleBoxFlat:
		var f: StyleBoxFlat = sb
		f.bg_color = bg
		f.border_color = border
	return sb

## 把一张图标里的不透明像素按亮度聚成**不超过两档**，并把"面积大的那档"定为 rank 0。
## 返回 {ok, w, h, cols(每像素原色,只含不透明), rank(每像素档号,与 cols 同序), tones[{color,count,a_max}]}
## 说明：用一维 2-means（初值取最暗/最亮），12 次迭代 —— 图标只有 16×16 量级，代价可忽略；
## 单色图标（明暗差 < 0.04）直接判一档，不会把抗锯齿的边缘像素误聚成第二档。
func _icon_clusters(tex: Texture2D) -> Dictionary:
	var out: Dictionary = {"ok": false}
	if tex == null:
		return out
	var img: Image = tex.get_image()
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		return out
	var w: int = img.get_width()
	var h: int = img.get_height()
	var cols: PackedColorArray = PackedColorArray()
	var lum: PackedFloat32Array = PackedFloat32Array()
	var al: PackedFloat32Array = PackedFloat32Array()
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.02:
				continue
			cols.append(c)
			lum.append(c.get_luminance())
			al.append(c.a)
	var n: int = lum.size()
	if n == 0:
		return out
	var lo: float = lum[0]
	var hi: float = lum[0]
	for i in n:
		lo = minf(lo, lum[i])
		hi = maxf(hi, lum[i])
	var single: bool = (hi - lo) < 0.04
	var c0: float = lo
	var c1: float = hi
	var grp: PackedByteArray = PackedByteArray()
	grp.resize(n)
	for _it in 12:
		var num0: int = 0
		var num1: int = 0
		var sum0: float = 0.0
		var sum1: float = 0.0
		for i in n:
			if single or absf(lum[i] - c0) <= absf(lum[i] - c1):
				grp[i] = 0
				sum0 += lum[i]
				num0 += 1
			else:
				grp[i] = 1
				sum1 += lum[i]
				num1 += 1
		if num0 > 0:
			c0 = sum0 / float(num0)
		if num1 > 0:
			c1 = sum1 / float(num1)
	var cnt: Array[int] = [0, 0]
	for i in n:
		cnt[int(grp[i])] += 1
	var flip: bool = (not single) and cnt[1] > cnt[0]
	var rank: PackedByteArray = PackedByteArray()
	rank.resize(n)
	for i in n:
		rank[i] = (1 - int(grp[i])) if flip else int(grp[i])
	var tones: Array = []
	for k in (1 if single else 2):
		var num: int = 0
		var r: float = 0.0
		var g: float = 0.0
		var b: float = 0.0
		var amax: float = 0.0
		for i in n:
			if int(rank[i]) != k:
				continue
			var c2: Color = cols[i]
			num += 1
			r += c2.r
			g += c2.g
			b += c2.b
			amax = maxf(amax, al[i])
		if num > 0:
			tones.append({
				"color": Color(r / float(num), g / float(num), b / float(num)),
				"count": num, "a_max": amax,
			})
	out["ok"] = true
	out["w"] = w
	out["h"] = h
	out["cols"] = cols
	out["rank"] = rank
	out["tones"] = tones
	return out

## 读回一张图标里**真有的**色档（判据用；也是 `_recolor_icon()` 的分档依据）。
## 返回 [{color, count}]，按面积降序 ⇒ `[0]` 就是"盒/轨道"那一档。
func icon_tones(tex: Texture2D) -> Array:
	var cl: Dictionary = _icon_clusters(tex)
	if not bool(cl["ok"]):
		return []
	var out: Array = []
	for t in (cl["tones"] as Array):
		out.append({"color": t["color"], "count": t["count"]})
	return out

## 按角色表把图标**重新上色**（形状一个像素不动）。档数不足时副色用不上（单色图标全用主色）。
func _recolor_icon(tex: Texture2D, main: Color, alt: Color) -> ImageTexture:
	var cl: Dictionary = _icon_clusters(tex)
	if not bool(cl["ok"]):
		return null
	var img: Image = tex.get_image().duplicate()
	var w: int = int(cl["w"])
	var h: int = int(cl["h"])
	var rank: PackedByteArray = cl["rank"]
	var tones: Array = cl["tones"]
	var cols: Array[Color] = [main, alt]
	var k: int = 0
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rk: int = int(rank[k])
			k += 1
			# alpha 峰值归一到 1.0：底色不再"半透明 ⇒ 实际颜色随背后漂移"（那种色任何常量断言都是假的），
			# 而边缘的渐变按同一比例缩小 = 抗锯齿一个不少。
			var amax: float = maxf(float(tones[rk]["a_max"]), 0.001)
			var a: float = minf(1.0, c.a / amax)
			var col: Color = cols[rk]
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

## 给一个控件的**本体**套主题（勾选框 / 开关 / 滑杆 / 滚动条共用这一个入口）。
## 幂等：源一律取 `ThemeDB` 的默认主题（不是取控件上"现在生效的那个"），所以重复调用
## 不会"把我们的产物再染一遍"（铁律 §73）。
func style_theme_native_body(ctrl: Control, host_bg: Color) -> void:
	var cls: String = ctrl.get_class()
	var def: Theme = ThemeDB.get_default_theme()
	var roles: Dictionary = native_body_roles(cls, host_bg)
	for k in roles.keys():
		var key: String = String(k)
		var pair: Array = roles[k]
		if key.begins_with(NATIVE_SB_PREFIX):
			var sn: StringName = StringName(key.substr(NATIVE_SB_PREFIX.length()))
			var src: StyleBox = def.get_stylebox(sn, cls)
			if src != null:
				ctrl.add_theme_stylebox_override(sn, _recolor_stylebox(src, pair[0], pair[1]))
		elif key.begins_with(NATIVE_IC_PREFIX):
			var icn: StringName = StringName(key.substr(NATIVE_IC_PREFIX.length()))
			var tex: ImageTexture = _recolor_icon(def.get_icon(icn, cls), pair[0], pair[1])
			if tex != null:
				ctrl.add_theme_icon_override(icn, tex)
	# 与按钮/输入框共用同一个"表面"键：判据只认它（一个键，一处写）
	ctrl.set_meta(BTN_META_HOST, host_bg)

## 本体样式的**读回**（判据用）：控件上真在生效的样式盒底色 / 图标色档，以及真源给的期望值。
## ★ 实测与期望分两条路取：实测读**控件**（`get_theme_*`），期望读**真源函数**
##   ⇒ "套上了"与"套对了"是两件事，这条判据两件都管（铁律 §47/§64）。
func probe_native_body(ctrl: Control) -> Dictionary:
	var cls: String = ctrl.get_class()
	var out: Dictionary = {
		"cls": cls, "styled": ctrl.has_meta(BTN_META_HOST), "host": page_surface(),
		"sb": {}, "ic": {},
	}
	if out["styled"]:
		out["host"] = ctrl.get_meta(BTN_META_HOST)
	var roles: Dictionary = native_body_roles(cls, out["host"])
	out["roles"] = roles
	for k in roles.keys():
		var key: String = String(k)
		if key.begins_with(NATIVE_SB_PREFIX):
			var sn: StringName = StringName(key.substr(NATIVE_SB_PREFIX.length()))
			var sb: StyleBox = ctrl.get_theme_stylebox(sn)
			out["sb"][key] = (sb.bg_color if sb is StyleBoxFlat else Color(0, 0, 0, 0))
		elif key.begins_with(NATIVE_IC_PREFIX):
			var icn: StringName = StringName(key.substr(NATIVE_IC_PREFIX.length()))
			out["ic"][key] = (icon_tones(ctrl.get_theme_icon(icn))
				if ctrl.has_theme_icon_override(icn) else [])
	return out

## 主题色按钮的完整调色板（**所有按钮的唯一取色入口**）。`host_bg` = 按钮所在表面的底色。
## 返回：fill / ink / border / fill_hover / fill_press / fill_sel / ink_sel / border_sel
##       / disabled_fill / disabled_ink。
func button_palette(host_bg: Color) -> Dictionary:
	var fill: Color = _fit_away_from(board_color, host_bg, BTN_SURFACE_MIN_CONTRAST)
	# ★★ 字色口径见 `readable_ink_on()`（唯一真源）—— "为什么不能只信 ink_for_bg 的 0.45 分界"
	#   那段实测记录跟着函数一起搬走了，别在这里再抄一遍（抄一份 = 将来只改一处）。
	var ink: Color = readable_ink_on(fill)
	# hover / press 在 fill 两侧各走一小步：**远离表面**的方向由 fill 相对表面的明暗决定
	# （`up=true` ⇒ fill 比表面亮 ⇒ 远离=提亮）。hover 更醒目、press 往表面里凹。
	var up: bool = fill.get_luminance() >= host_bg.get_luminance()
	var fill_hover: Color = fill.lightened(0.09) if up else fill.darkened(0.09)
	var fill_press: Color = fill.darkened(0.10) if up else fill.lightened(0.10)
	# ★ 选中态：实心 accent。accent 本身可能对表面太近（浅色主题的深棕 accent 在浅底上其实够，
	#   但深色主题的荧光 accent 在深底上只有 ~1.0）⇒ 同样过一遍"远离表面"。
	var fill_sel: Color = _fit_away_from(accent_color(), host_bg, BTN_SURFACE_MIN_CONTRAST)
	# 选中态同一口径（实测最差是「天青」3.344，同样败在方向而不是阈值上）
	var ink_sel: Color = readable_ink_on(fill_sel)
	# 未选按钮的描边：用**提亮后的 accent**（原 accent 在深色 fill 上常常看不见）
	var border: Color = _fit_ink_on(accent_color(), fill, 1.25)
	# 禁用：去饱和 + 向表面靠拢（"灰下去"而不是"换个颜色"，避免与主题色混淆）。
	# ★ 这两支色收进 `disabled_pair_of()`（原生控件本体的禁用态也读它 —— 一处派生，两处用）。
	var dp: Array[Color] = disabled_pair_of(fill, host_bg)
	var disabled_fill: Color = dp[0]
	var disabled_ink: Color = dp[1]
	return {
		"fill": fill, "ink": ink, "border": border,
		"fill_hover": fill_hover, "fill_press": fill_press,
		"fill_sel": fill_sel, "ink_sel": ink_sel, "border_sel": ink_sel,
		"disabled_fill": disabled_fill, "disabled_ink": disabled_ink,
	}

## 把主题色按钮样式套到**原生 Button** 上（设置页 / 棋谱库 / 联机大厅 / 弹窗 / 手机菜单）。
## ★ 读回校验请用 `probe_button_theme()`（读控件真实生效值），**不要**直接算调色板 ——
##   常量对了不代表控件上真套上了（漏调一次就退回引擎默认主题，断言照样绿）。
##
## ★★ 2026-10-15：套样式时把**入参表面**与**状态**写回控件元数据（`BTN_META_*`）。
##   为什么非写不可：判据只能读到"控件上的颜色"，而"这颜色是**对着哪张面**算出来的"在控件上
##   看不出来 —— 于是"传错表面"（例如该传 `page_surface()` 却传了 `bg_color`，在
##   `bg_brightness≠1` 的机器上按钮与背景同色）这一类错**没有任何判据能咬住**。
##   把它记下来，判据就能同时断三件事：套上了 / 颜色对 / **表面选对了**。
## ★ `pad` 见 `BTN_PAD_*` 的注：默认页面档；"一行里多个按钮"的地方传紧凑档，
##   免得主题化把整行撑宽（那是布局事故，不是配色改动）。
func style_theme_button(btn: Button, host_bg: Color,
		pad: Vector2 = BTN_PAD_PAGE) -> void:
	var p: Dictionary = button_palette(host_bg)
	btn.set_meta(BTN_META_HOST, host_bg)
	btn.set_meta(BTN_META_STATE, BTN_STATE_NORMAL)
	btn.add_theme_stylebox_override("normal", _dialog_box(p["fill"], p["border"], pad.x, pad.y))
	btn.add_theme_stylebox_override("hover", _dialog_box(p["fill_hover"], p["border_sel"], pad.x, pad.y))
	btn.add_theme_stylebox_override("pressed", _dialog_box(p["fill_press"], p["border_sel"], pad.x, pad.y))
	btn.add_theme_stylebox_override("disabled",
		_dialog_box(p["disabled_fill"], Color(p["disabled_ink"].r, p["disabled_ink"].g,
			p["disabled_ink"].b, 0.45), pad.x, pad.y))
	# focus 框不能再用不透明底（会盖住 hover/pressed 的底色，焦点态与鼠标态会叠在一起）
	btn.add_theme_stylebox_override("focus",
		_dialog_box(Color(0, 0, 0, 0), Color(p["ink_sel"].r, p["ink_sel"].g, p["ink_sel"].b, 0.9),
			pad.x, pad.y))
	# ★★ `font_hover_pressed_color` 必须一起覆盖（2026-10-15）：它只在"toggle 按钮被按下**且**
	#   鼠标停在上面"时生效 —— 漏了它不报错、静态截图也看不出来（截图时鼠标不在按钮上），
	#   症状是**按住切换块的那一刻字色闪回默认主题的白**。菜单里那两档切换块
	#   （`_refresh_duel_tabs()`）当年为这一条单独记过账；这次收进真源，不再靠调用点自觉。
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color"]:
		btn.add_theme_color_override(k, p["ink"])
	btn.add_theme_color_override("font_disabled_color", p["disabled_ink"])

## 选中态（实心 accent）—— 与上面的"未选"分开套，因为原生 Button 用 `toggle_mode` 表达选中。
func style_theme_button_selected(btn: Button, host_bg: Color,
		pad: Vector2 = BTN_PAD_PAGE) -> void:
	var p: Dictionary = button_palette(host_bg)
	btn.set_meta(BTN_META_HOST, host_bg)
	btn.set_meta(BTN_META_STATE, BTN_STATE_SELECTED)
	btn.add_theme_stylebox_override("normal", _dialog_box(p["fill_sel"], p["border_sel"], pad.x, pad.y))
	btn.add_theme_stylebox_override("hover", _dialog_box(p["fill_sel"], p["border_sel"], pad.x, pad.y))
	btn.add_theme_stylebox_override("pressed", _dialog_box(p["fill_sel"], p["border_sel"], pad.x, pad.y))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color"]:
		btn.add_theme_color_override(k, p["ink_sel"])

## 读回校验：**读控件上真实生效的值**，**不要**直接重算调色板。
## ★★ 为什么必须读控件：调色板算对了不代表样式**套上了** —— 漏调一次 `style_theme_button()`
##   就退回引擎默认主题，而"拿 `button_palette()` 再算一遍"的断言照样绿
##   （本工程这条纪律在 `_hover_side_color()` 与 `--settest` 上都记过账）。
## ★ 返回键：`has_normal`（有没有真的套上 normal stylebox —— 没套 = 走引擎默认主题）、
##   `fill` / `ink`（控件上真实生效的底色与字色）、`corner`（圆角半径，用来断"是圆角矩形"）、
##   `host` / `state`（套样式时记下的表面与状态）、
##   `fill_expect` / `ink_expect`（按**记下来的那个表面**应当成为的底色与字色，供判据比对
##   控件上读到的 `fill` / `ink` —— 这一步同时咬住"表面传错"与"字色读错键"两族错）。
func probe_button_theme(btn: Button) -> Dictionary:
	var out: Dictionary = {
		"has_normal": false, "fill": Color(0, 0, 0, 0), "ink": Color(0, 0, 0, 0),
		"corner": -1.0, "host": page_surface(), "state": "",
		"fill_expect": Color(0, 0, 0, 0), "ink_expect": Color(0, 0, 0, 0),
	}
	var nb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if nb != null:
		out["has_normal"] = true
		out["fill"] = nb.bg_color
		out["corner"] = float(nb.corner_radius_top_left)
	out["ink"] = btn.get_theme_color("font_color")
	if btn.has_meta(BTN_META_HOST):
		out["host"] = btn.get_meta(BTN_META_HOST)
	if btn.has_meta(BTN_META_STATE):
		out["state"] = String(btn.get_meta(BTN_META_STATE))
	var pb: Dictionary = button_palette(out["host"])
	if out["state"] == BTN_STATE_SELECTED:
		out["fill_expect"] = pb["fill_sel"]
		out["ink_expect"] = pb["ink_sel"]
	else:
		out["fill_expect"] = pb["fill"]
		out["ink_expect"] = pb["ink"]
	return out

## 上一步落子的提示圆点色。
## ★★ 用户口令（2026-10-08 第三轮）：「包括上步落子的提示圆点等，配色要仔细一些」。
##    旧实现 `Color.WHITE if 黑子 else Color.BLACK` 是**硬编码反色**，实测在
##    霓虹 1.23 / 赛博 1.22 上不可见（见 `DOT_MIN_CONTRAST` 的注）。
##    新规则：**优先用主题 accent**（与整体配色同门）；accent 对这颗棋子不达标时，
##    改取「近白 / 近黑」里对比更大的那个，再逐级推到 ≥ DOT_MIN_CONTRAST。
##    ⇒ 传统浅色主题的结果**与改动前逐字相同**（accent 不达标 → 白点），
##      只有"高亮棋子"那两套会正确地翻成深色点（观感变化被限制在真正坏掉的地方）。
func last_move_dot_color(stone: Color) -> Color:
	var acc: Color = accent_color()
	if contrast_ratio(acc, stone) >= DOT_MIN_CONTRAST:
		return acc
	var white := Color(1.0, 1.0, 1.0)
	var black := Color(0.0, 0.0, 0.0)
	var pick: Color = white if contrast_ratio(white, stone) >= contrast_ratio(black, stone) else black
	return _fit_ink_on(pick, stone, DOT_MIN_CONTRAST)

func _find_node_named(root: Node, want: String, want_type: String) -> Node:
	if root == null:
		return null
	for c in root.get_children():
		if String(c.name) == want and c.is_class(want_type):
			return c
		var r: Node = _find_node_named(c, want, want_type)
		if r != null:
			return r
	return null

## 探针（自检用）：读回弹出面板上**真实生效**的文字/底色对比度。
## ★ 为什么必须读控件、不能直接算常量：常量对了**不代表控件上真套上了** ——
##   漏调 style_dialog_* 就退回引擎默认主题，常量断言照样绿、字照样看不清（静默失效）。
##   ★ 阴性对照一并返回：把"出问题的那两个旧配色"用同一判据算一遍，必须**不达标**，
##     否则说明这条判据根本抓不到这个 bug（=没牙齿）。
## 返回 {} 表示面板结构不完整（缺 PanelContainer / DialogTitle / DialogHint），调用方据此判失败。
func probe_dialog_contrast(layer: Node) -> Dictionary:
	var panel: PanelContainer = _find_node_named(layer, "DialogPanel", "PanelContainer") as PanelContainer
	var title: Label = _find_node_named(layer, "DialogTitle", "Label") as Label
	var hint: Label = _find_node_named(layer, "DialogHint", "Label") as Label
	if panel == null or title == null or hint == null:
		return {}
	var pbg: Color = DIALOG_BG
	var sb: StyleBox = panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		pbg = (sb as StyleBoxFlat).bg_color
	var out := {
		"title": contrast_ratio(title.get_theme_color("font_color"), pbg),
		"text": contrast_ratio(hint.get_theme_color("font_color"), pbg),
		"button": -1.0,
		"neg_text": contrast_ratio(Color(0.10, 0.10, 0.12), pbg),   # 旧「ink」浅色主题取值
		"neg_title": contrast_ratio(Color(0.55, 0.40, 0.10), pbg),  # 旧「accent」浅色主题取值
		"thr": DIALOG_TEXT_MIN_CONTRAST,
	}
	var btns: Array[Button] = []
	collect_buttons_deep(layer, btns)
	if btns.size() > 0:
		var b: Button = btns[0]
		var bbg: Color = DIALOG_BTN_BG
		var bsb: StyleBox = b.get_theme_stylebox("normal")
		if bsb is StyleBoxFlat:
			bbg = (bsb as StyleBoxFlat).bg_color
		out["button"] = contrast_ratio(b.get_theme_color("font_color"), bbg)
	return out

## 递归收集一棵子树里的**所有** Button（按控件树顺序，不去重、不按名字索引）。
## ★ 2026-10-15 由 `_collect_buttons_deep` 改名放开（去掉下划线）：`menu.gd` 的
##   `_themed_button_audit()` 也要用它。**改名而不是在那边再写一份** ——
##   "递归收按钮"这种遍历各写一份，迟早有一份忘了收 `Button` 的子类（`CheckBox`/`OptionButton`）
##   ⇒ 两个调用点量到的按钮集合不一样，却都自称"全部按钮"（铁律 §70）。
## ★ 用 `is Button` 而不是 `get_class() == "Button"`：子类要一起收进来。
## ★★ 2026-10-15 修：**根节点自己如果是 Button 也要收**。原实现只遍历子节点 ⇒
##   `collect_buttons_deep(some_button, out)` 收到一个**空数组**（而调用方以为自己拿到了
##   "这棵子树里所有按钮"）。第一个踩到的是 `--menutest` ⑮ 的**阴性对照**：
##   它拿一个裸 Button 当子树去审计，期望"未套样式必须被逮住" —— 空数组让这条对照
##   恒假绿（`themed == 0` 与 `bad 为空` 同时成立），看起来像"审计没有牙"。
func collect_buttons_deep(node: Node, out: Array[Button]) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Button:
		out.append(node as Button)
	for c in node.get_children():
		collect_buttons_deep(c, out)

## 自检判据（两套 ESC 面板共用）：三项对比度全部达标 + 阴性对照必须不达标
## 返回 [bool 通过, String 人读摘要]
func judge_dialog_contrast(layer: Node) -> Array:
	var d: Dictionary = probe_dialog_contrast(layer)
	if d.is_empty():
		return [false, "面板结构不完整（缺 DialogPanel/DialogTitle/DialogHint）"]
	var thr: float = float(d["thr"])
	var ok_pos: bool = float(d["title"]) >= thr and float(d["text"]) >= thr \
		and float(d["button"]) >= thr
	# 阴性对照：旧配色里**至少正文这一项**必须被判不达标，判据才算有牙齿
	var ok_neg: bool = float(d["neg_text"]) < thr
	var msg := "标题=%.2f 正文=%.2f 按钮=%.2f（判据 ≥%.1f）%s | 阴性对照 旧正文=%.2f 旧标题=%.2f %s" % [
		d["title"], d["text"], d["button"], thr, "达标 ✓" if ok_pos else "不达标 ✗",
		d["neg_text"], d["neg_title"], "会报警 ✓" if ok_neg else "不报警 ✗（判据没牙齿）"]
	return [ok_pos and ok_neg, msg]

## 立方体棋盘三面由瓷砖主色派生（保持「同一立方体三面明暗」的错觉）
## ⚰️ 2026-10-17 墓碑（名字不许回收）：这里原有 `cube_light()` / `cube_dark()`。
##   它们的唯一读者 `cube_face_light` / `cube_face_dark` 两个 @export 已于同日删除
##   （game.gd 的 `_draw()` 立方体只用 `cube_face_mid`，墓碑见其赋值处）。
##   全工程引用清点（1042 个函数逐名扫描、全量语料、哨兵校验）确认零读者
##   ⇒ 供给函数一并删除；只保留仍在用的 `cube_mid()`。
func cube_mid() -> Color:
	return tile_color_a

# ---------- 显示模式 ----------
## 把 window_mode 真正应用到窗口（设置页切换时与游戏启动时各调一次）
func apply_window_mode() -> void:
	match window_mode:
		MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		MODE_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# 无边框全屏：窗口拉到整个屏幕可用区域（多显示器下只覆盖当前屏），去掉标题栏。
			# 相比独占全屏，切出桌面时不会重排窗口，老显卡/多屏下更稳。
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var scr: int = DisplayServer.window_get_current_screen()
			DisplayServer.window_set_position(DisplayServer.screen_get_position(scr))
			DisplayServer.window_set_size(DisplayServer.screen_get_size(scr))
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# 从全屏切回窗口时，Godot **不会**自动恢复原尺寸（实测仍是 2880×1800，
			# 且该尺寸会被 Windows 判为最大化 → window_get_mode() 返回 MAXIMIZED）。
			# 所以要主动给一个逻辑尺寸并居中，否则用户拿到的是"铺满屏幕的窗口"。
			# 居中按**可用区**（去掉任务栏）算 —— 见 center_window() 的说明。
			var want: Vector2i = _windowed_size()
			DisplayServer.window_set_size(want)
			center_window(want)


func window_mode_name(m: int = -1) -> String:
	match (m if m >= 0 else window_mode):
		MODE_FULLSCREEN: return "全屏"
		MODE_BORDERLESS: return "无边框全屏"
		_: return "窗口"

# ---------- 持久化 ----------
## 旧配置主题名迁移（**只写「旧名 → 现名」的显式映射**，不做"拼后缀"的推算）。
##
## 本工程的主题名经历过三代：
##   ① 最早：无后缀（「宣纸 / 石墨 / 黛蓝 / 竹青 / 胡桃木 / 粉黛 / 紫水晶」）
##   ② 2026-09：每系拆浅/深两版（「宣纸·浅」「宣纸·深」…），「胡桃木」整系被「朱砂」取代
##   ③ 2026-10-08（本版）：**改回单档**，黄/绿/粉保留、其余按四路风格重做
## ⇒ 老用户配置里可能是**任意一代**的名字，都必须**平移到观感最近的新主题**，
##   而不是掉回默认 —— 观感突变会让用户以为"配置坏了"（本工程踩过一次：
##   `_migrate_preset_name` 缺失 ⇒ 存了竹青、新开程序却是宣纸色）。
##
## ★ 为什么用映射表而不是 if/else 推算：第三代名字里**没有可推算的成分**
##   （「黛蓝」与「藏青」没有任何字符串关系）⇒ 任何推算都只能是猜。显式表可枚举、可判据。
const PRESET_RENAMES: Dictionary = {
	# ② 浅/深两版 → 同色系的单档版（三个保留色系）
	"宣纸·浅": "宣纸", "宣纸·深": "宣纸",
	"竹青·浅": "竹青", "竹青·深": "竹青",
	"粉黛·浅": "粉黛", "粉黛·深": "粉黛",
	# ② 被换掉的四个色系 → 观感最近的新主题（灰→玄石 / 蓝→藏青 / 红→绛红 / 紫→藕荷）
	"石墨·浅": "玄石", "石墨·深": "玄石",
	"黛蓝·浅": "藏青", "黛蓝·深": "藏青",
	"朱砂·浅": "绛红", "朱砂·深": "绛红",
	"紫水晶·浅": "藕荷", "紫水晶·深": "藕荷",
	# ① 无后缀的更早旧名
	"石墨": "玄石", "黛蓝": "藏青", "竹青": "竹青", "宣纸": "宣纸", "粉黛": "粉黛",
	"朱砂": "绛红", "紫水晶": "藕荷",
	# ①「胡桃木」当年被平移到朱砂；现在朱砂也退役了 ⇒ 跟着平移到同为**木色暖调**的焦糖
	"胡桃木": "焦糖", "胡桃木·浅": "焦糖", "胡桃木·深": "焦糖",
}

func _migrate_preset_name(old: String) -> String:
	if old == "":
		return DEFAULT_PRESET
	if find_theme(old) != null:
		return old                           # 已是当前名（**必须先查**，免得被映射表误伤）
	if PRESET_RENAMES.has(old):
		return String(PRESET_RENAMES[old])
	return DEFAULT_PRESET                     # 认不出的名字 → 回到默认主题

# ====== 「本次运行是不是自动化运行」的**唯一真源** ======
#
# ★★ 为什么必须收在 Autoload 这一份（2026-09-29 实测）：这条判据原来是**两份各自列举 flag 的副本**
#    （`menu.gd::_is_automated_run()` 与 `menu_mobile.gd::_is_automated_run()`），而且**列的不是同一批**：
#      桌面侧认 `--*test*` / `--screenshot` / `--shotpage=` / `--select=`；
#      手机侧只认 `--mtest` / `--screenshot` / `--sheet(=)`。
#    ⇒ `--portraittest` / `--mob…` 这类**新 flag 在手机侧被判成"玩家在操作"**，那条路径上任何写盘
#      都会真写用户配置。本工程「两处同口径、只改一处」的老坑就是这一类（ESC 面板修过两遍）。
#    并集判定：任一侧原来认的 flag 现在都认（只会**更宽**，方向是安全的 —— 判据只用来**少写盘**）。
func is_automated_run() -> bool:
	for a in _cmdline():
		if a.begins_with("--") and (a.contains("test") or a == "--screenshot"
				or a.begins_with("--shotpage=") or a.begins_with("--select=")
				or a.begins_with("--sheet=") or a == "--sheet"):
			return true
	return false


## ★★ 2026-10-13：**外观配置**要不要改道自检盘 —— 比 `is_automated_run()` 多认一类 flag。
##
## 为什么不能直接用 `is_automated_run()`：它的口径是「参数名里含 `test`」（外加几个显式项），
## 而 `--apprt`（外观·对局往返）**名字里没有 test** ⇒ 判不到 ⇒ 它写的是**用户的真配置**。
## 实测后果（2026-10-13）：游戏侧那次 `--apprt` 被 90s 超时**强杀**（① 已落盘、② 的还原
## 还没跑到）⇒ 用户主题被永久留在「竹青」—— 用户原本是「霓虹」，由两条独立证据锁定：
## `user://debug_menu.png` 底角像素 (9,11,19)（= 霓虹 bg 0.035/0.045/0.075）与
## `--mtest` ⑧ 打印的 `行值=霓虹`。
##
## ★ 为什么只补 `--apprt`、**不去放宽 `is_automated_run()`**：
##   那个函数还被 records（棋谱目录）/ last_match / music 共用 —— 一放宽，**带 flag 的
##   正常运行**（例如开发者用 `--board=penrose` 玩一局）的棋谱就会被塞进自检盘，而外观
##   会去读自检盘那份 ⇒ 显示成别的主题。误伤面远大于收益。
##   ⇒ 只在**真正需要的那一个用途**（外观读写）上补判；名单就一条，与 `regress.sh` 里
##     那行 `MENU_TESTS="$MENU_TESTS apprt modeltest"` 一一对应。
##   ⚠️ 将来若又有**名字不含 test 的自检**要动外观，**必须在这里登记** ——
##     否则它会重复这次的事故（工作区 `orphan_registry.tsv` 是同类登记的另一个抄本）。
const APPEARANCE_SELFTEST_FLAGS: PackedStringArray = ["--apprt"]


func _appearance_redirect(path: String) -> String:
	## 返回**实际**要用的外观配置路径：用户路径 + 满足条件 ⇒ 自检盘。
	## ★ `load_appearance()` 与 `save_appearance()` **共用这一个函数** —— 只有一份口径。
	if path != APPEARANCE_PATH:
		return path                          # 显式给了自检路径（`--apptest` 那种）就用它
	if is_automated_run():
		return APPEARANCE_SELFTEST_PATH
	for a in _cmdline():
		if a in APPEARANCE_SELFTEST_FLAGS:
			return APPEARANCE_SELFTEST_PATH
	return path



## 命令行全集（引擎参数 + `--` 之后的用户参数）。与 `menu.gd::_argv()` 同一口径。
## ⚠️ 注意 `--headless` **不算**自动化：`godot --headless res://menu.tscn --quit`
##    走的正是"正常运行"这条路径 —— 冒烟因此顺带覆盖了「带恢复启动菜单」那一个分支。
func _cmdline() -> PackedStringArray:
	var out := OS.get_cmdline_args()
	out.append_array(OS.get_cmdline_user_args())
	return out

## ★ `path` 参数只为**自检**留缝（`--lastmatchtest` 同款做法）：自检必须走**独立路径**，
##   否则它会把测试时用的默认主题写进用户的真配置 —— 2026-09-27 用户报「配色变回默认」，
##   实测就是 `--apptest` 结尾那次 `save_appearance()` 干的（跑一次回归，主题就被冲成宣纸·浅）。
## 用**当前预设的 accent** 补上 `accent_override`（`accent_override` 是"标题色"的唯一真源）。
##
## ★ 为什么要有这个函数（2026-10-20 配色重做时实测发现）：
##   `accent_color()` 只认 `accent_override`；而 `accent_override.a == 0` 的含义是"未设"
##   ⇒ 回退到**硬编码兜底** `Color(0.55, 0.40, 0.10)`。那条兜底色有三个问题：
##     ① 它**不是任何主题的 accent**（与 .tres 里的 12 套标题色都不同）；
##     ② 它落在 `readable_ink_on()` 的**明度死区**（L 0.16~0.45）里 ⇒ 引擎给它配**近黑字**
##        ⇒「实心深底 + 黑字」＝糊 —— 正是本轮要修的那个病灶；
##     ③ 于是"首次运行（没有 appearance.cfg）"时，背景/棋盘取自 .tres 的宣纸、标题色却取自
##        另一个硬编码常量 ⇒ **同一套配色里混了两套色**。
##   口径：**accent 的真源是 `themes/*.tres`**；只有"预设名找不到"（用户自定义配色）才回退兜底。
func _accent_from_preset() -> void:
	if accent_override.a > 0.0:
		return
	var ta: BoardTheme = find_theme(appearance_preset)
	if ta != null and ta.accent.a > 0.0:
		accent_override = ta.accent


func load_appearance(path: String = APPEARANCE_PATH) -> void:
	# ★ 2026-10-13：读、写**共用同一份改道口径**（`_appearance_redirect()`）。
	#   只改 `save` 不改 `load` 会**破坏** `--apprt`：① 写进自检盘，而对局/回菜单时
	#   `load_appearance()` 又去读**用户**那份（旧主题）⇒ `[apprt] ②` 假红。
	path = _appearance_redirect(path)
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		_accent_from_preset()      # 首次运行（无配置文件）⇒ accent 也取预设的，别落硬编码兜底
		return
	bg_color = _read_color(cf, "bg_color", bg_color)
	board_color = _read_color(cf, "board_color", board_color)
	line_color = _read_color(cf, "line_color", line_color)
	bg_brightness = float(cf.get_value("appearance", "bg_brightness", bg_brightness))
	graph_mode = bool(cf.get_value("appearance", "graph_mode", graph_mode))
	appearance_preset = String(cf.get_value("appearance", "preset", appearance_preset))
	appearance_preset = _migrate_preset_name(appearance_preset)
	accent_override = _read_color(cf, "accent_color", accent_override)
	_accent_from_preset()                        # 旧配置没这项 → 用当前预设的 accent 补上
	window_mode = clampi(int(cf.get_value("display", "window_mode", window_mode)), MODE_WINDOW, MODE_BORDERLESS)
	# 鼠标指针。★ 读回的尺寸必须**先落回现存档位**（`cursor_size_index()` 会把没有素材的怪值
	# 拽到最接近的一档）：少这一步，旧配置/手改过的配置文件会让 `apply_custom_mouse_cursor()`
	# 找不到素材 → push_warning 后**沿用系统光标**（不报错，只是"我的光标怎么没了"）。
	cursor_enabled = bool(cf.get_value("cursor", "enabled", cursor_enabled))
	cursor_size = cursor_size_for_index(cursor_size_index(int(cf.get_value("cursor", "size", cursor_size))))
	# 瓷砖色（对局 `tile_colors` / 立方体三面的真源）**不落盘**，所以读回时必须跟着棋盘色重算，
	# 规矩与 `apply_preset()` 里那两行一致 —— 少了这两行，"存了竹青·浅、新开程序"时它仍是
	# 声明时的初值（宣纸·浅棋盘色）= 又一个「配色回默认」，而且只在没人点过主题时才出现（静默）。
	tile_color_a = board_color
	tile_color_b = board_color
	# ★ 棋子色同理，真源也是"当前主题"（主题名已经落盘在 appearance.cfg 里）⇒ 用预设补齐。
	#   少了这几行，"存了霓虹、新开程序"会退回黑白子 —— 而霓虹的棋盘是深底，
	#   黑白子放上去几乎看不见，症状是"我的主题坏了"，且**只在霓虹类主题上出现**（静默、难查）。
	#   找不到匹配（= 用户自定义配色）时**不动**，保持默认黑白。
	# ★ 精简版只有一个主题：旧存档（或完整版留下的 appearance.cfg）里存着别的主题名时
	#   **强制回到「经典」**。不归位的后果：`find_theme()` 返回 null ⇒ 颜色停在声明初值，
	#   而设置页显示"当前预设=霓虹"却只有一个宣纸色块（只有玩家看得见的错位态）。
	if lite and appearance_preset != DEFAULT_PRESET:
		apply_preset(DEFAULT_PRESET)
	var ts: BoardTheme = find_theme(appearance_preset)
	if ts != null:
		stone_color_black = ts.effective_stone_black(STONE_BLACK_DEFAULT)
		stone_color_white = ts.effective_stone_white(STONE_WHITE_DEFAULT)
	# ★ 第 0 步：**刚读进来的状态不算用户改过** —— 不清这一句，一次启动就会把"读到的值"
	#   当脏写回去，脏标记门退化成"每次启动必写一次"。
	_appearance_dirty = false

## 标记「**用户**改过外观」—— 写用户真配置的**唯一开关**（脏标记门，见 `_appearance_dirty`）。
##
## ★ 谁必须调：`menu.gd` 里**由用户操作触发**的 6 个回调，必须在 `save_appearance()` 之前调本函数。
## ★ 谁不许调：自检 / 审计 / 遍历主题的路径。它们要么走 selftest 盘（门本来就不拦），
##   要么根本不该写盘 —— 顺手调一下就会把"遍历中间态"合法化，门的价值归零。
func mark_appearance_dirty() -> void:
	_appearance_dirty = true


func save_appearance(path: String = APPEARANCE_PATH) -> void:
	# ★★ 自动化运行**一律不许写用户的 `user://` 配置** —— 闸放在**写点的唯一入口**，不散在各调用处。
	#    为什么必须放在这一层：自检**必须走真实交互路径**（否则测的不是那份代码），而真实路径里就写着
	#    `save_appearance()`。把闸写在各调用处 = 迟早漏一处（本工程「两处同口径」的老坑）。
	#
	#    实测踩点（2026-09-29 探针：逐个 flag 隔离跑 + 比对用户文件 md5）：
	#      `--settest` 里点「无边框全屏」按钮 → `menu.gd::_on_display_mode_pressed()` 直接写
	#      **用户真配置**（先写 MODE_BORDERLESS=2），随后 `menu.gd` 收尾再写回原值 ⇒ 净内容碰巧
	#      相同、md5 没变，所以**没出症状**；但只要中途退出/异常，用户的窗口模式就被留在
	#      **无边框全屏**上（下次开游戏直接全屏，玩家会以为程序坏了）。
	#    ★ 判据在 `--settest`：「自检盘上必须留下那次写」+「用户文件逐字节未变」（两条缺一不可 ——
	#      只看后者的话，"压根没写"也能满足它，那就是恒真的空判据）。
	# ★ 2026-10-13：改走 `_appearance_redirect()`（与 `load_appearance()` 同一口径）
	#   —— 它比 `is_automated_run()` 多认 `--apprt`：那个 flag 名字里没有 "test"，
	#   旧口径漏判 ⇒ 真写过用户的 appearance.cfg（详见该函数的注释）。
	var eff: String = _appearance_redirect(path)
	# ★★ 第 0 步**脏标记门**（2026-10-20）：写**用户真配置**必须由"用户改过"触发。
	#   与上面那道改道闸是两个层次，缺一不可：
	#     · 改道闸回答"自动化运行写到哪儿"；
	#     · 本门回答"**这次到底该不该写用户文件**" —— 事故正是"遍历主题的中间态被写进去"，
	#       而它可能发生在任何一次 menu 启动里（连 `--headless --quit-after 90` 都能复现）。
	#   ★ 只拦用户路径：自检盘照写，否则 `--apptest` / `--settest` 的落盘判据全废。
	#   ★ 被挡时累加计数（不是静默 return）—— 让判据能区分"挡住了"和"本来没写"。
	if eff == APPEARANCE_PATH and not _appearance_dirty:
		_appearance_save_blocked += 1
		print("[gate] 挡住第 %d 次写用户配置（preset=%s path=%s）" % [
			_appearance_save_blocked, appearance_preset, path])
		return
	var cf := ConfigFile.new()
	cf.set_value("appearance", "bg_color", bg_color)
	cf.set_value("appearance", "board_color", board_color)
	cf.set_value("appearance", "line_color", line_color)
	cf.set_value("appearance", "bg_brightness", bg_brightness)
	cf.set_value("appearance", "graph_mode", graph_mode)
	cf.set_value("appearance", "preset", appearance_preset)
	cf.set_value("appearance", "accent_color", accent_override)
	cf.set_value("display", "window_mode", window_mode)
	cf.set_value("cursor", "enabled", cursor_enabled)
	cf.set_value("cursor", "size", cursor_size)
	var err: int = cf.save(eff)
	if err != OK:
		push_warning("外观配置保存失败：%d" % err)

# ====== 「上一局的选项」持久化（user://last_match.cfg）======
#
# 用途：菜单开局时把当前选择记下来，下次打开菜单（含"下完棋返回菜单"）自动恢复。
# 存的是**菜单自己的选择状态**，不是这里 board_size / mode 那种派生值 —— 理由见下面注释。
#
# ⚠️ 为什么不能直接存 `board_size`：棋盘走帽子家族（BOARD_HAT）时，菜单会把 `board_size`
#    强制成 RANDOM，而"非帽子盘用的大小档"另有其值（_sel_size）并存着；存派生字段就会丢信息，
#    切回彭罗斯时大小档莫名变随机。所以五个字段都存菜单的选择状态。
#
# ⚠️ 为什么**不存联机方式**（邀请好友 / 随机匹配）：恢复「线上·邀请好友」会让菜单一打开就建房
#    （`_ensure_invite_room` → `_auto_create_room`，甚至拉起信令服务器），恢复「随机匹配」
#    会直接进排队队列 —— 都不是"回到菜单"该发生的事。详见 menu.gd `_apply_last_match()`。
#
# path 参数只为**自检**留缝：`--lastmatchtest` 用独立路径跑文件往返，不碰用户的真配置。
func save_last_match(board: int, size: int, hat_kind: int, diff: int, mode: int,
		xg: int = 0, path: String = LAST_MATCH_PATH) -> void:
	# ★★ 与 `save_appearance()` 同一道闸、同一套理由（见那里的长注释）：自动化运行不写用户的
	#    `user://` 配置。放这一层的意义是**兜底**：现有两个调用点（menu.gd / menu_mobile.gd）
	#    各自都记得套 `if not _is_automated_run():`，但"两处都记得"不是不变量 —— 本工程的老坑。
	#    ★ 这里**不改道**（不像 appearance 那样转到自检盘）：没有哪条自检需要"经真路径写 last_match"，
	#      改道只会凭空多出一个没人清理的垃圾文件。直接挡掉，并把"被挡了"说出来（别静默）。
	if path == LAST_MATCH_PATH and is_automated_run():
		push_warning("[自动化运行] 已拦截写用户配置 %s（自检/截图不落盘）" % LAST_MATCH_PATH)
		return
	var cf := ConfigFile.new()
	cf.set_value("last_match", "board", board)
	cf.set_value("last_match", "size", size)
	cf.set_value("last_match", "hat_kind", hat_kind)
	cf.set_value("last_match", "diff", diff)
	cf.set_value("last_match", "mode", mode)
	# ★ 2026-10-15（「测试AI」转正为「疾风」）：多存一位"是否用骨架引擎那档"。
	#   它**不进 `load_last_match()` 的必需字段检查** —— 理由是"新增"与"写坏"的区别：
	#   `board/size/hat_kind/diff/mode` 缺一个说明**记录写坏了**（整份作废）；
	#   而 `xg` 缺只说明**这份记录是上一版写的**（默认 0 即可，别作废用户的选项）。
	cf.set_value("last_match", "xg", xg)
	var err: int = cf.save(path)
	if err != OK:
		push_warning("上局选项保存失败：%d" % err)

## 读回上一局选项。
## 返回空字典 = 首次运行（没有文件）或文件损坏/缺 section —— 调用方按默认值处理，
## 绝不要在这里"猜"默认值（默认值归 menu.gd，两处都写就会分叉）。
func load_last_match(path: String = LAST_MATCH_PATH) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {}
	if not cf.has_section("last_match"):
		return {}
	var out := {}
	for key in ["board", "size", "hat_kind", "diff", "mode"]:
		if not cf.has_section_key("last_match", key):
			return {}                                    # 缺字段 = 记录不完整，整份作废
		out[key] = int(cf.get_value("last_match", key, 0))
	# ★ 2026-10-15：`xg`（疾风档）是**新增的可选字段**，故意**不进**上面那道必需检查：
	#   旧记录没有它 ⇒ 默认 0（= 当时还没有疾风档），语义正确、不作废整份记录。
	#   ⚠️ 别为"整齐"把它塞进那道检查：那会让**每个升级到本版的用户**丢掉一次上一局选项
	#      （棋盘/大小全回默认），而收益只是少一个默认分支。
	out["xg"] = int(cf.get_value("last_match", "xg", 0))
	# ★ 精简版没有联机：旧存档（或完整版留下的 last_match.cfg）里存着 `mode=ONLINE` 时
	#   **降级成人机**。不降级的话 `game.gd _ready()` 会走 `mode == ONLINE` 分支去建 peer，
	#   而玩家既没有 Steam 也没有对手 ⇒ 表现是"开局卡住"，且**不报任何错**。
	if lite and out["mode"] == ONLINE:
		out["mode"] = VS_AI
	return out

## 从 ConfigFile 读取 Color，兼容手写 #RRGGBB / #RRGGBBAA 字符串
func _read_color(cf: ConfigFile, key: String, fallback: Color) -> Color:
	var v: Variant = cf.get_value("appearance", key, fallback)
	if v is Color:
		return v
	if v is String:
		var s := (v as String).strip_edges()
		if s.begins_with("#"):
			return Color.html(s)
	return fallback

# ====== 棋谱复盘交接（菜单「棋谱」面板 → 对局场景）======
#
# ★ 为什么必须经由 Autoload：菜单与对局是**两个独立场景**（`change_scene_to_file()`），
#   彼此不持有引用（见文件头那句"彼此独立、互不持有引用"）⇒ "点的是哪一条谱"只能
#   在场景切换前寄存在单例里。
# ★ 为什么是"取走 + 清空"一个函数，而不是"读一次 + 自己清"：
#   清空的活交给读取方的话，`game.gd` 那条分支将来任何一次提前 `return` / 新加 `if`
#   都会**忘了清**，症状是"回菜单再进对局，莫名其妙又进了上次那条谱的复盘"——
#   静默、且只在"点过一次谱"之后才出现（本工程"两处都记得不是不变量"的老坑）。
#   ⇒ `take_pending_replay()` 让"读到"与"清掉"是同一次调用：清不掉在结构上不可能。
#   （铁律 8：状态一处写一处读。）
# ★ 与 last_match / appearance 不同，这个值**不落盘**：它是"这一瞬间的意图"，
#   跟窗口一起消失才是对的 —— 落盘的话，下次冷启动会自己钻进复盘。
var pending_replay_id: String = ""

## 唯一的**写**入口（菜单侧「点条目进复盘」调用）。
func request_replay(id: String) -> void:
	# ★ 精简版没有棋谱：**在写入口拦**。拦在这里的好处是 `take_pending_replay()` 永不为非空，
	#   于是 `game.gd` 那两段交接（建盘前切盘 / 建盘后进复盘）在结构上都不可能被触发，
	#   不需要在对局侧再加一份判断（少一处"两处都记得"的坑）。
	if lite:
		return
	pending_replay_id = id

## 唯一的**读**入口：取走并立刻清空（读一次就没了，连读两次第二次必得空串）。
func take_pending_replay() -> String:
	var id: String = pending_replay_id
	pending_replay_id = ""
	return id


# ====== 联机战绩（user://record.cfg）======
#
# 用途：记录**联机对战**（mode == ONLINE）的胜负，供「联机大厅」显示胜率 ——
#   房主把自己的战绩写进 lobby data，陌生人浏览大厅时读到并显示。
#   ★ **只记联机**：人机 / 本地不计入，否则"挑陌生对手"看到的胜率会被打 AI 的战绩污染，
#     失去参考意义。记点唯一真源：game.gd 终局结算处调 `GameConfig.add_record_result(won)`。
#
# ★ 与 appearance / last_match 同一套纪律（见 `save_appearance()` 的长注释）：
#   写点唯一入口 + 自动化运行不写用户配置（改道到自检盘）；
#   path 参数只为自检留缝（`--recordtest` 走独立路径）。
const RECORD_PATH: String = "user://record.cfg"
const RECORD_SELFTEST_PATH: String = "user://record_selftest.cfg"

var record_wins: int = 0
var record_losses: int = 0

func record_total() -> int:
	return record_wins + record_losses

## 胜率 [0,1]；**无战绩返回 -1**（不是 0）—— 大厅 UI 要能区分"从没打过"与"全输"。
func win_rate() -> float:
	var t := record_total()
	return float(record_wins) / float(t) if t > 0 else -1.0

## 人类可读串（lobby data 与 UI 共用）："75%（3胜4负）"；无战绩 "—"。
func record_str() -> String:
	var t := record_total()
	if t <= 0:
		return "—"
	return "%d%%（%d胜%d负）" % [int(round(win_rate() * 100.0)), record_wins, record_losses]

## 终局记一场：won = 我是否赢了。★ 调用方（game.gd）负责只在联机时调。
func add_record_result(won: bool) -> void:
	if won:
		record_wins += 1
	else:
		record_losses += 1
	save_record()

func save_record(path: String = RECORD_PATH) -> void:
	# ★ 与 save_appearance() 同一道闸、同一套理由：自动化运行不写用户的 user:// 配置。
	#   这里**改道**（像 appearance 那样转到自检盘）：`--recordtest` 要"经真路径写一次"再验证
	#   "写在了自检盘、用户文件没动"（两条缺一不可，只看"用户文件没动"是恒真的空判据）。
	var eff := path
	if eff == RECORD_PATH and is_automated_run():
		eff = RECORD_SELFTEST_PATH
	var cf := ConfigFile.new()
	cf.set_value("record", "wins", record_wins)
	cf.set_value("record", "losses", record_losses)
	var err: int = cf.save(eff)
	if err != OK:
		push_warning("战绩保存失败：%d" % err)

func load_record(path: String = RECORD_PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	record_wins = clampi(int(cf.get_value("record", "wins", 0)), 0, 999999)
	record_losses = clampi(int(cf.get_value("record", "losses", 0)), 0, 999999)
