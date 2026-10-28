## 棋钟 × 音乐节拍耦合内核（2026-10-16）。
## 用户口令：「加入棋钟系统，你来设计，要与音乐对接，让音乐节拍和双方下棋频率相关」。
##
## ★★★ 设计分工（三处，各管一件事，不许互相越界）：
##   · **本文件（`GameClock`）**：时钟真源 —— 走时 / 读秒 / 加秒 / 超时；以及两条映射
##     「落子频率 → 目标 BPM」「剩余时间 → 时间压力」。**纯逻辑、无场景依赖**，
##     可直接喂固定 `delta` 复现（自检就是这么做的）。
##   · **`game.gd`**：接线 —— 每帧喂 `delta` 与"该不该走钟"，落子/停手时通知 `on_move()`，
##     把 `snapshot()` 挂在成员 `clk` 上，超时调用既有的 `_resign_game()` 判负。
##   · **`music.gd`**：调度 —— 什么时候**真的**换速（小节头）、换速时把时钟余量按新步长
##     重标定、时间压力并进节奏轴、压力过闸时每拍补一个读秒声。
##
## ★★ 为什么"平滑"在这一侧、"换速时机"在音乐侧：
##   平滑是**内容**（BPM 该走多快）；换速是**调度**（哪一拍才允许跳）。music.gd 里有一条
##   硬约束（改 `bpm` 会让 `step_seconds()` 在小节中途变、`_advance()` 的时钟与新步长
##   不同步 ⇒ 拍与拍之间漂移），那条约束的解只能是"小节头换速 + 余量重标定" ——
##   它只能实现在音乐侧。而 BPM 的曲线形状属于棋钟：不该让音乐知道"落子频率"这个概念。
##   ⇒ 两侧的接口只有两个数：`clk_bpm`（已平滑的目标 BPM）与 `clk_pressure`（0..1）。
##
## ★ 为什么音乐侧是**反射读** `clk` 而不是 game.gd 反过来推给它：
##   与 music.gd 既有的"零改动接入"哲学一致（它读 `BATTLE_FIELDS` / `SITUATION_FIELDS`
##   也是反射）。⇒ 棋钟只要把快照挂上去就自动接线，game.gd 不需要知道 BPM 曲线的存在。
##
## ★★ 三种赛制（`mode`）：
##   · 包干（SUDDEN）：一次给足，走完判负。最简单，也最容易突然死亡。
##   · 读秒（BYOYOMI，**默认**）：主时走完后进入 `byo_count` 次 × `byo_seconds` 秒，
##     每落一手重置**当前这一次**读秒（次数保留）—— 这是亚洲棋赛的通行口径。
##   · 加秒（FISCHER）：每落一手回补 `fischer_inc` 秒。`fischer_cap_at_main` 决定
##     是否封顶到 `main_seconds`（封顶 = Bronstein 式，不封顶 = 标准 Fischer）。
##
## ⚠️ 与前作"停手"的关系：停一手**同样算一手**（`on_move` 照常通知）—— 它同样消耗
##   时间、同样重置读秒。不这么做的话，"时间快没了就停一手"会成为一条免费的续命漏洞。
class_name GameClock
extends Node

# ===== 与 game.gd `enum Stone` 对齐的索引常量 =====
## ★ 与 `game.gd` 的 `enum Stone { EMPTY, BLACK, WHITE }` **各写一份**（同 `record.gd` 的
##   做法：那个文件同样不愿反向 import 对局脚本）。按本工程的纪律，各写一份就**必须配一条
##   判据** —— `--clocktest` 判据⓪ 断言 `Stone.BLACK == GameClock.BLACK`，
##   真源一旦调序，这里当场红（而不是安静地把黑白读反）。
const BLACK := 1
const WHITE := 2

const MODE_OFF := 0
const MODE_SUDDEN := 1
const MODE_BYOYOMI := 2
const MODE_FISCHER := 3

# ===== 运行期可调参数（与工程惯例一致：数值一律暴露，运行期可改） =====
@export_group("棋钟")
@export var clk_enabled: bool = true
@export_enum("关闭", "包干", "读秒", "加秒") var mode: int = MODE_BYOYOMI
## 每方基本用时（秒）。读秒档=主时；包干档=全部；加秒档=回补上限。
## ★ 默认 900（15 分钟）+ 3×30s 读秒：出货默认值不该让人一上手就被判负 ——
##   本作 AI 每手要思考数秒（那段时间计在 AI 自己的钟里），快棋档（600s）对慢手玩家偏紧。
@export_range(0.0, 7200.0, 5.0) var main_seconds: float = 900.0
@export_range(1, 10, 1) var byo_count: int = 3
@export_range(5.0, 120.0, 1.0) var byo_seconds: float = 30.0
@export_range(0.0, 60.0, 1.0) var fischer_inc: float = 5.0
@export var fischer_cap_at_main: bool = true
## 超时是否判负。关掉 = 只当时长显示（用来给"只想看节拍耦合"的场合留退路）。
@export var timeout_loses: bool = true

@export_group("落子频率 → 音乐节拍")
## 落子频率 → 目标 BPM。★ 这一条就是用户口令里的「让音乐节拍和双方下棋频率相关」。
@export var music_link: bool = true
## 频率窗口：用**最近这么多手**（+ 当前这一手的已耗时）估算手频。
@export_range(2, 40, 1) var rate_window: int = 8
## 频率映射的两个锚点（手/分钟）：慢于此 = 最慢档，快于此 = 最快档。
## 默认 6 手/分（10 秒一手）~ 48 手/分（1.25 秒一手）—— 覆盖"长考"到"读秒抢手"的实感区间。
@export_range(0.5, 60.0, 0.5) var rate_slow: float = 6.0
@export_range(1.0, 240.0, 1.0) var rate_fast: float = 48.0
@export_range(30.0, 120.0, 1.0) var bpm_slow: float = 54.0
@export_range(30.0, 240.0, 1.0) var bpm_fast: float = 132.0
## BPM 每秒最大变化量（**平滑放在产生端**：音乐侧只负责在小节头提交）。
## 18 BPM/s ⇒ 从最慢到最快约 4.3s，比"一手棋"长、比"一个阶段"短 —— 听得出来但不会吓一跳。
@export_range(1.0, 240.0, 1.0) var bpm_slew: float = 18.0

@export_group("剩余时间 → 时间压力")
## 剩余多少秒算"压力 0"（低于它线性升到 1）。压力进音乐节奏轴 + 触发读秒声。
@export_range(5.0, 600.0, 5.0) var pressure_ref: float = 60.0

# ===== 运行期状态 =====
## 双方剩余时间，索引 0 = 黑 / 1 = 白（`_side()` 负责换算，**外部一律用颜色**）。
var t_left: Array[float] = [0.0, 0.0]
## 剩余读秒次数 / 当前这一次读秒的剩余秒数。
var byo_left: Array[int] = [0, 0]
var byo_cur: Array[float] = [0.0, 0.0]
var move_count: Array[int] = [0, 0]
## 最近 `rate_window` 手的**落子时刻**（`elapsed` 轴，只在走钟时增长 ⇒ 复盘中自动冻结）。
var move_stamps: Array[float] = []
## 走钟累计时长。★ 它是**唯一**的时间坐标：`move_stamps` 与手频都基于它，
## 而它只在 `active` 时增长 ⇒ 菜单/复盘/暂停期间"下棋频率"不会自己变（不会静默拉低 BPM）。
var elapsed: float = 0.0
## 当前手频（手/分钟）。0 = 样本不足（少于两手）⇒ BPM 落在最慢档。
var rate: float = 0.0
var bpm_target: float = 0.0
var bpm_now: float = 0.0
var pressure: float = 0.0
## 超时方（`Stone` 色；0 = 没人超时）。
var timed_out: int = 0
var _timed_out_side: int = -1
var _turn_side: int = 0
## 复用字典：`snapshot()` 每帧被调一次，不必每帧新建。⚠️ 拿到的是**同一个引用**，
## 只读、不许存（本工程内只有 `game.gd` 把它挂到成员 `clk` 上供反射读）。
var _snap: Dictionary = {}
## 自检期间创建的临时实例（跑完统一 `free()`；本类没有 owner 的 Node 不会被自动回收）。
var _temps: Array[Node] = []


func _ready() -> void:
	reset()


## 开新局（或被 reset_game 调用）：时间、读秒、频率样本、超时标记全部归零。
func reset() -> void:
	t_left[0] = main_seconds
	t_left[1] = main_seconds
	byo_left[0] = byo_count
	byo_left[1] = byo_count
	byo_cur[0] = byo_seconds
	byo_cur[1] = byo_seconds
	move_count[0] = 0
	move_count[1] = 0
	move_stamps.clear()
	elapsed = 0.0
	rate = 0.0
	bpm_target = bpm_slow
	bpm_now = bpm_slow
	pressure = 0.0
	timed_out = 0
	_timed_out_side = -1
	_turn_side = 0
	snapshot()


# ===== 走时 =====
## 推进一步。`turn_color` = 现在轮到谁（`Stone.BLACK` / `WEIGHT`）；
## `active` = 该不该走钟（真对局中、未终局、不在复盘中、非联机 —— 判据在 `game.gd`，
## 因为"什么算在对局中"只有那边知道）。
##
## ★ 三条独立的时间线，各自只在一个地方增长：
##   · `t_left/byo_cur` —— 当前行棋方在走；
##   · `elapsed` —— 只要有对局在走就增长（手频的**分母**，与"轮到谁"无关）；
##   · `bpm_now` —— 每帧朝目标平滑（`bpm_slew` 限速）。
func tick(delta: float, turn_color: int, active: bool) -> void:
	if not clk_enabled or mode == MODE_OFF or not active:
		return
	var d := maxf(delta, 0.0)
	var side := _side(turn_color)
	if side >= 0:
		_turn_side = side
	elapsed += d
	if side >= 0 and timed_out == 0:
		_consume(side, d)
	_update_rate()
	_update_bpm(d)
	_update_pressure()


## 从行棋方的钟里扣掉 `dt` 秒。三种赛制各自的分支都在这里（**唯一**扣时点）。
func _consume(side: int, dt: float) -> void:
	if mode == MODE_BYOYOMI:
		if t_left[side] > 0.0:
			# ★ 主时只吃它自己那一份，**余下的 dt 要结转给读秒**。
			#   第一版写成"扣完主时就 return"，于是"主时剩 1s 而这一帧推了 56s"会把
			#   55 秒整段吞掉（读秒纹丝不动）= 一次大卡顿就等于白送时间，且不报错。
			var used: float = minf(t_left[side], dt)
			t_left[side] -= used
			dt -= used
			if dt <= 0.0:
				return                  # 主时还没走完，不进读秒
		# ★ 用 while 而不是 if：一次 tick 的 `dt` 理论上可能长于一次读秒
		#   （卡顿、自检里喂大 `dt`）—— `if` 会只扣一次而把多出来的时间吞掉，
		#   表现为"读秒次数比预期多"，且不报错。
		byo_cur[side] -= dt
		while byo_cur[side] <= 0.0:
			byo_left[side] -= 1
			if byo_left[side] <= 0:
				byo_left[side] = 0
				byo_cur[side] = 0.0
				_do_timeout(side)
				return
			byo_cur[side] += byo_seconds
		return
	# 包干 / 加秒：都只看主时
	t_left[side] = maxf(t_left[side] - dt, 0.0)
	if t_left[side] <= 0.0:
		_do_timeout(side)


func _do_timeout(side: int) -> void:
	if timed_out != 0 or not timeout_loses:
		return
	timed_out = BLACK if side == 0 else WHITE
	_timed_out_side = side


## 一手落定（**含停一手**；见文件头那条注释）。
## 三件事：记账频率样本 / 加秒 / 重置当前这一次读秒。
func on_move(color: int) -> void:
	var side := _side(color)
	if side < 0 or not clk_enabled or mode == MODE_OFF:
		return
	move_count[side] += 1
	move_stamps.append(elapsed)
	while move_stamps.size() > rate_window:
		move_stamps.pop_front()
	if mode == MODE_FISCHER and fischer_inc > 0.0:
		t_left[side] += fischer_inc
		if fischer_cap_at_main:
			t_left[side] = minf(t_left[side], main_seconds)
	if mode == MODE_BYOYOMI and t_left[side] <= 0.0 and byo_left[side] > 0:
		byo_cur[side] = byo_seconds
	_update_rate()


# ===== 两条映射（纯函数：判据直接拿字面期望值对账，不靠"读表证明表"）=====
## 手频 → BPM。★ 单调不减，且两端**精确**落在锚点上（`rate<=rate_slow` ⇒ `bpm_slow`）。
## 分段外的输入被夹住而不是外推 —— 外推会让"极慢"变成 0 BPM（音乐停摆，且没人报错）。
static func bpm_for_rate(r: float, r_slow: float, r_fast: float,
		b_slow: float, b_fast: float) -> float:
	var span := maxf(r_fast - r_slow, 0.001)
	var t := clampf((r - r_slow) / span, 0.0, 1.0)
	return lerpf(b_slow, b_fast, t)


## 剩余时间 → 压力 0..1（`ref_sec` 秒时 0，归零时 1）。
static func pressure_of(left_sec: float, ref_sec: float) -> float:
	if ref_sec <= 0.0:
		return 0.0
	return clampf(1.0 - left_sec / ref_sec, 0.0, 1.0)


## 某一方的**有效剩余**：读秒中 = 当前这一次读秒的剩余（正是"压力"要看的量）。
func effective_left(side: int) -> float:
	if side < 0 or side > 1:
		return 0.0
	if mode == MODE_BYOYOMI and t_left[side] <= 0.0:
		return maxf(byo_cur[side], 0.0)
	return maxf(t_left[side], 0.0)


func _update_rate() -> void:
	# 样本不足（不足两手）⇒ 手频无意义，保持 0（= 最慢档）。
	# ★ 不是洁癖：只落过一手时"跨度"恒为 0，算出来是无穷大 ⇒ 一开局就顶到最快档。
	if move_stamps.size() < 2:
		rate = 0.0
		return
	var span := elapsed - float(move_stamps[0])
	if span <= 0.0001:
		rate = 0.0
		return
	# ★ 分子用**间隔数**（`size - 1`）而不是手数：`span` 覆盖的是 size-1 个间隔。
	#   用 size 会让整体偏高 (n/(n-1)) 倍 —— 在 8 手窗口上是 +14%，听不出来但口径不对。
	# ★ 分母用"到当前这一刻"的跨度（而不是"到最后一手"）：长考期间跨度持续增长
	#   ⇒ 手频**自然衰减**，音乐跟着慢下来。这正是用户要的"节拍跟随下棋频率"：
	#   "想得久"与"下得慢"在听感上本该是同一件事。
	rate = 60.0 * float(move_stamps.size() - 1) / span


func _update_bpm(dt: float) -> void:
	if not music_link:
		bpm_target = 0.0
		return
	bpm_target = bpm_for_rate(rate, rate_slow, rate_fast, bpm_slow, bpm_fast)
	bpm_now = move_toward(bpm_now, bpm_target, maxf(bpm_slew, 0.0) * maxf(dt, 0.0))


func _update_pressure() -> void:
	pressure = pressure_of(minf(effective_left(0), effective_left(1)), pressure_ref)


func _side(color: int) -> int:
	if color == BLACK:
		return 0
	if color == WHITE:
		return 1
	return -1


# ===== 对外快照（音乐反射读它；HUD 也读它）=====
## ⚠️ 返回**复用**的同一个字典（每帧调一次，不新建）。调用方只读、不许缓存这份引用。
## 字段名与用法：
##   `clk_bpm`      → 音乐要用的目标 BPM（已平滑）
##   `clk_pressure` → 0..1，音乐并进节奏轴 + 触发读秒声
##   `hud`          → HUD 那一行文字（本文件是它的**唯一**拼装处，UI 不自己拼）
func snapshot() -> Dictionary:
	_snap["enabled"] = clk_enabled and mode != MODE_OFF
	_snap["mode"] = mode
	_snap["black"] = effective_left(0)
	_snap["white"] = effective_left(1)
	_snap["black_main"] = t_left[0]
	_snap["white_main"] = t_left[1]
	_snap["byo_left_black"] = byo_left[0]
	_snap["byo_left_white"] = byo_left[1]
	_snap["byo_cur_black"] = byo_cur[0]
	_snap["byo_cur_white"] = byo_cur[1]
	_snap["rate"] = rate
	_snap["clk_bpm"] = bpm_now if music_link else 0.0
	_snap["clk_pressure"] = pressure
	_snap["timed_out"] = timed_out
	_snap["hud"] = hud_text()
	return _snap


## HUD 那一行。`▶` 标出轮到的哪一方（棋钟最基本的信息是"谁的钟在走"）。
## ★ 只在**轮到的那一方**前面加标记，不给另一方补空格 —— 补空格是为了对齐，
##   而这一行在竖屏是居中的（对齐带来的空白反而像是排版出错）。
func hud_text() -> String:
	if not clk_enabled or mode == MODE_OFF:
		return ""
	var parts: Array[String] = []
	for side in 2:
		var who := "黑" if side == 0 else "白"
		var mark := "▶" if side == _turn_side else ""
		parts.append("%s%s %s" % [mark, who, _side_time_text(side)])
	return " · ".join(parts)


func _side_time_text(side: int) -> String:
	if timed_out != 0 and side == _timed_out_side:
		return "超时"
	if mode == MODE_BYOYOMI and t_left[side] <= 0.0:
		if byo_left[side] <= 0:
			return "0"
		return "%s×%d" % [format_sec(byo_cur[side]), byo_left[side]]
	return format_sec(t_left[side])


## 时长口径：≥1 分钟走 `m:ss`；≥10 秒走整秒；<10 秒给一位小数。
## ★ 10 秒以下给小数不是花哨：读秒的最后几秒是**心跳**，整数秒会把"还剩 0.4 秒"显示成 "1s"。
static func format_sec(s: float) -> String:
	var v := maxf(s, 0.0)
	if v >= 60.0:
		return "%d:%02d" % [int(v) / 60, int(v) % 60]
	if v >= 10.0:
		return "%ds" % int(ceil(v))
	return "%.1fs" % v


# ===== 自检（纯逻辑，无场景依赖；由 game.gd 的 `--clocktest` 触发并统一打印）=====
## 返回 [bool, 人读摘要]。**全部判据都在这个文件内部**，因为它们量的都是纯逻辑：
## 走时/读秒/加秒/超时是确定性的，手频与压力映射是纯函数。
## ★ 唯一的例外是判据⓪（与 `game.gd` 的 `enum Stone` 对账）—— 那一条在 `game.gd` 侧，
##   因为本文件**不许** import 对局脚本（反向依赖），只能由那一侧来断言。
func run_selftest() -> Array:
	var checks: Array = []
	var detail: Array[String] = []

	# ① 走时：包干 10s，喂 3 × 1s ⇒ 剩 7s（逐位）
	var c1: GameClock = _mk(MODE_SUDDEN, 10.0, 0, 0.0)
	for i in 3:
		c1.tick(1.0, BLACK, true)
	checks.append(["① 包干走时｜10s 走 3s 须剩 7.0s · 字面期望",
		is_equal_approx(c1.t_left[0], 7.0) and is_equal_approx(c1.t_left[1], 10.0)])
	detail.append("黑 %.3f / 白 %.3f" % [c1.t_left[0], c1.t_left[1]])

	# ② 暂停不走钟：`active=false` 时时间与频率**都不许动**（菜单/复盘/联机档靠它）
	var before: float = c1.t_left[0]
	var e_before: float = c1.elapsed
	for i in 5:
		c1.tick(1.0, BLACK, false)
	checks.append(["② 闸 active=false｜时间与 elapsed 均不动",
		is_equal_approx(c1.t_left[0], before) and is_equal_approx(c1.elapsed, e_before)])
	detail.append("停 5 帧后 %.3f · 须 %.3f" % [c1.t_left[0], before])

	# ③ 读秒：主时 2s + 3 次 × 5s。走 2.5s ⇒ 主时归零、进读秒（当前这次已耗 0.5s）
	var c3: GameClock = _mk(MODE_BYOYOMI, 2.0, 3, 5.0)
	c3.tick(2.5, BLACK, true)
	var ok3a: bool = c3.t_left[0] <= 0.0 and c3.byo_left[0] == 3 \
		and is_equal_approx(c3.byo_cur[0], 5.0 - 0.5)
	# 再走 4.5s ⇒ 第一次读秒耗尽 ⇒ 次数 3→2 且当前读秒回到 5.0
	c3.tick(4.5, BLACK, true)
	var ok3b: bool = c3.byo_left[0] == 2 and is_equal_approx(c3.byo_cur[0], 5.0)
	checks.append(["③ 读秒进入与扣次｜主时归零后按 5s 一次扣 · 次数 3→2 · 结转不吞时间",
		ok3a and ok3b and c3.timed_out == 0])
	detail.append("剩次 %d · 当前 %.3f · 超时 %d" % [c3.byo_left[0], c3.byo_cur[0], c3.timed_out])

	# ④ 读秒耗尽 ⇒ 超时，且超时方 = 走钟的那一方
	c3.tick(20.0, BLACK, true)      # 一把走掉 3 次读秒还多
	checks.append(["④ 读秒耗尽｜timed_out = 走钟方黑 · 次数夹到 0 不许为负",
		c3.timed_out == BLACK and c3.byo_left[0] == 0])
	detail.append("timed_out=%d · 剩余次数 %d" % [c3.timed_out, c3.byo_left[0]])

	# ⑤ 超时后时停：再喂 10s 不许把已判负方的数字继续往下改（否则 HUD 会抖）
	var after_to: float = c3.byo_cur[0]
	c3.tick(10.0, BLACK, true)
	checks.append(["⑤ 超时后时停｜已停止扣时 · 读数不再变化",
		is_equal_approx(c3.byo_cur[0], after_to) and c3.timed_out == BLACK])
	detail.append("超时后再走 10s：%.3f · 须 %.3f" % [c3.byo_cur[0], after_to])

	# ⑥ 加秒：Fischer 每手回补，且**封顶**到基本用时（不封的话可以无限攒钟）
	var c6: GameClock = _mk(MODE_FISCHER, 100.0, 0, 0.0)
	c6.fischer_inc = 5.0
	c6.fischer_cap_at_main = true
	c6.tick(10.0, BLACK, true)      # 90
	c6.on_move(BLACK)               # 95
	c6.tick(10.0, WHITE, true)      # 白 90（黑的 95 不动）
	c6.on_move(WHITE)
	var ok6: bool = is_equal_approx(c6.t_left[0], 95.0) and is_equal_approx(c6.t_left[1], 95.0)
	c6.on_move(WHITE)
	c6.on_move(WHITE)               # 连加两次仍须 ≤ 100
	checks.append(["⑥ 加秒｜落子回补 inc · 且封顶到 main_seconds",
		ok6 and c6.t_left[1] <= 100.0001])
	detail.append("黑 %.2f / 白 %.2f · 上限 100" % [c6.t_left[0], c6.t_left[1]])

	# ⑦ 手频 → BPM：造 5 手、每手间隔 1s ⇒ rate = 60 手/分 ⇒ 落在最快档
	var c7: GameClock = _mk(MODE_SUDDEN, 600.0, 0, 0.0)
	for i in 5:
		c7.tick(1.0, BLACK, true)
		c7.on_move(BLACK)
	var r7: float = c7.rate
	checks.append(["⑦ 手频口径｜5 手各隔 1s ⇒ rate = 60 手/分 · 字面期望",
		absf(r7 - 60.0) < 1.0])
	detail.append("rate=%.2f · BPM 目标 %.1f" % [r7, c7.bpm_target])

	# ⑧ 频率 → BPM 的单调性：扫 6 档，只改「落子有多快」这一个自变量
	var seq: Array[float] = []
	seq.append(GameClock.bpm_for_rate(0.0, 6.0, 48.0, 54.0, 132.0))
	seq.append(GameClock.bpm_for_rate(6.0, 6.0, 48.0, 54.0, 132.0))
	seq.append(GameClock.bpm_for_rate(18.0, 6.0, 48.0, 54.0, 132.0))
	seq.append(GameClock.bpm_for_rate(30.0, 6.0, 48.0, 54.0, 132.0))
	seq.append(GameClock.bpm_for_rate(48.0, 6.0, 48.0, 54.0, 132.0))
	seq.append(GameClock.bpm_for_rate(999.0, 6.0, 48.0, 54.0, 132.0))   # 超界须夹住
	var mono: bool = true
	for i in range(1, seq.size()):
		if seq[i] < seq[i - 1] - 1e-9:
			mono = false
	checks.append(["⑧ 频率→BPM｜单调不减 · 两端精确落在锚点 · 超界夹住不外推",
		mono and is_equal_approx(seq[0], 54.0) and is_equal_approx(seq[1], 54.0)
		and is_equal_approx(seq[4], 132.0) and is_equal_approx(seq[5], 132.0)])
	detail.append("BPM 序列 %s" % str(seq))

	# ⑨ 剩余时间 → 压力：三档单调 + 两端字面值
	var p0: float = GameClock.pressure_of(60.0, 60.0)
	var p1: float = GameClock.pressure_of(30.0, 60.0)
	var p2: float = GameClock.pressure_of(0.0, 60.0)
	var p3: float = GameClock.pressure_of(120.0, 60.0)     # 富余 ⇒ 夹到 0
	checks.append(["⑨ 剩余→压力｜60s=0.00 · 30s=0.50 · 0s=1.00 · 富余夹到 0",
		is_equal_approx(p0, 0.0) and absf(p1 - 0.5) < 1e-6
		and is_equal_approx(p2, 1.0) and is_equal_approx(p3, 0.0)])
	detail.append("[%.2f, %.2f, %.2f, %.2f]" % [p0, p1, p2, p3])

	# ⑩ 读秒中压力看的是**当前这一次读秒**：主时 1s + 一次喂 56s ⇒ 读秒只走掉 55s
	var c10: GameClock = _mk(MODE_BYOYOMI, 1.0, 3, 60.0)
	c10.tick(56.0, BLACK, true)
	var eff: float = c10.effective_left(0)
	checks.append(["⑩ 读秒中的有效剩余 = 当前这次读秒 · 而不是主时的 0",
		absf(eff - 5.0) < 0.001 and bool(c10.snapshot()["enabled"])])
	detail.append("有效剩余 %.2fs · 压力 %.3f" % [eff, c10.pressure])

	# ⑪ 快照契约：音乐要读的两个键必须在、类型是 float 且在合法区间
	var s11: Dictionary = c7.snapshot()
	var ok11: bool = s11.has("clk_bpm") and s11.has("clk_pressure") \
		and (s11["clk_bpm"] is float) and (s11["clk_pressure"] is float) \
		and float(s11["clk_bpm"]) >= 0.0 and float(s11["clk_bpm"]) <= 240.0 \
		and float(s11["clk_pressure"]) >= 0.0 and float(s11["clk_pressure"]) <= 1.0
	checks.append(["⑪ 快照契约｜clk_bpm / clk_pressure 存在 · 是 float · 在合法区间", ok11])
	detail.append("clk_bpm=%.2f · clk_pressure=%.3f" % [
		float(s11["clk_bpm"]), float(s11["clk_pressure"])])

	# ⑫ HUD 文案：读秒态必须显示"次数×秒"，而不是一个会误导的倒计时
	var c12: GameClock = _mk(MODE_BYOYOMI, 1.0, 3, 30.0)
	c12.tick(2.0, BLACK, true)
	c12.on_move(BLACK)
	var txt: String = c12.hud_text()
	checks.append(["⑫ HUD 文案｜含 ▶ 标记 与 30s×3 式读数 · 黑已进读秒",
		txt.contains("▶") and txt.contains("×") and txt.contains("30s×3")])
	detail.append("「%s」" % txt)

	# 汇总（★ 行形状与工程仪器对齐：失败标记 ` ✗` 必须落在**第一个全角括号之前**——
	#   仪器口径是 `split("（")[0].endswith("✗")`，明细一律塞进全角括号里）
	var passed := 0
	for c in checks:
		if bool(c[1]):
			passed += 1
	var all_ok: bool = passed == checks.size()
	print("[clocktest] ===== 棋钟内核 · 纯逻辑 =====")
	for i in checks.size():
		print("[clocktest] %s%s（%s）" % [str(checks[i][0]),
			"" if bool(checks[i][1]) else " ✗", detail[i]])
	print("[clocktest] 判据 %d/%d 通过%s（模式=%d 主时=%.0fs 读秒=%d×%.0fs 频率锚点 %.0f~%.0f 手/分 → BPM %.0f~%.0f）" % [
		passed, checks.size(), "" if all_ok else " ✗", mode, main_seconds, byo_count,
		byo_seconds, rate_slow, rate_fast, bpm_slow, bpm_fast])
	for t in _temps:
		if is_instance_valid(t):
			t.free()
	_temps.clear()
	return [all_ok, "判据 %d/%d" % [passed, checks.size()]]


## 自检用的临时实例工厂。★ 为什么是**另起一个实例**而不是改 self 的参数再改回来：
##   改回来这一步一旦漏掉（或中途 return），跑完自检的**真棋钟**就带着测试参数上桌了 ——
##   那正是本工程"自检污染生产状态"那一族。新实例还顺手把每一条判据隔离开。
## ⚠️ 这些实例没进场景树（`_ready` 不会跑），所以**必须显式 `reset()`**，
##   而且用完要 `free()`（`run_selftest` 结尾统一收）。
func _mk(m: int, main_s: float, byo_n: int, byo_s: float) -> GameClock:
	var c := GameClock.new()
	c.mode = m
	c.main_seconds = main_s
	c.byo_count = maxi(byo_n, 1)
	c.byo_seconds = maxf(byo_s, 0.1)
	c.clk_enabled = true
	c.music_link = true
	c.timeout_loses = true
	c.reset()
	_temps.append(c)
	return c

