class_name LiushuiAI
extends RefCounted

## ============================================================================
## 「流水」—— 基于**渗流模型**的围棋引擎（独立研究原型，2026-10-21）
## ============================================================================
##
## 【与 ai_engine.gd 的关系】完全独立，**不读也不改**其任何状态。接口形状刻意对齐
## （`setup` / `choose_move` / `export_board` / `clear_board` / `scramble`），
## 因此将来接入只需在 `game.gd` 换一个类名，不必改调用约定。
##
## 【核心思想】围棋的势/地本质是**渗流问题**：把棋盘看成一张图，己方子是"源头"、
## 对方子是"吸收壁"、空点是"未定位点"。问：一个随机游走者从空点出发，先碰到谁？
## 这个概率（= 离散**调和测度**/吸收概率，位点渗流的正统量）就是该点的归属势 φ。
##
##   φ 满足 Laplace 方程：φ[i] = mean(φ[邻居])，边界条件 φ(己方子)=1、φ(对方子)=0
##
## 迭代次数 K 就是随机游走能走多远 ⇒ **K 是渗流的"观测尺度"**：
##   · K 小（8）  → 只看局部连通，等于"贴着谁就是谁的"
##   · K 大（64） → 看全局连通，等于"哪边围得住才算谁的"
## 三档视野的**分歧**正是围棋里"未定区"的定义 ⇒ 本引擎最核心的新特征。
##
## 【与 Bouzy 5/21 / GNU Go influence 的区别】
##   · 5/21 是形态学 dilate/erode，**不可调**、且需要先知道死活；
##   · 本引擎是**求解** Laplace（有唯一解、可收敛判定），迭代次数是连续旋钮；
##   · 死活**不单独判**（那会开第二套死活口径）：块的存活度直接读邻居空点的 φ，
##     即"它连到己方确定区的渗流概率"—— 这就是渗流模型给围棋带来的真东西。
##
## 【为什么不用随机采样】K×N 次采样的成本在 200ms 预算下必爆（≈16 万步/手）。
## 求解一次 Laplace 是 O(K·E)，N≈150 时约 4 万步/手，且**确定性可复现**。

const EMPTY := 0
const BLACK := 1
const WHITE := 2

# ---------------------------------------------------------------------------
# 渗流尺度：三档随机游走视野（迭代次数 = 随机游走步数上限）
# ---------------------------------------------------------------------------
@export_group("渗流尺度")
## 近场：决定"贴着的子属于谁"。8 步≈局部一两格。
@export var iters_near: int = 8
## 中场：本引擎实际用于着法评估的尺度。
@export var iters_mid: int = 24
## 远场：决定"整块区域归谁"。64 步已超过 Penrose 150 点盘的图直径。
@export var iters_far: int = 64
## "未定"带宽：|φ-0.5| 小于它算未定区（势力边界）。
@export var frontier_band: float = 0.08
## "确定"门槛：|φ-0.5| 大于它算已定归属（跨越它 = 本手落定了一块地）。
@export var crit_band: float = 0.42

# ---------------------------------------------------------------------------
# 局部精算：落子后只在半径 R 内重解 Laplace（远处影响按指数衰减，可截断）
# ---------------------------------------------------------------------------
@export_group("局部精算")
@export var local_radius: int = 6
@export var local_iters: int = 18
## 级 1 廉价筛选保留的候选数（级 2 才做局部势场重解）。
@export var prefilter_width: int = 30

# ---------------------------------------------------------------------------
# 着法价值权重（全部运行期可调）
# ---------------------------------------------------------------------------
@export_group("着法权重")
## 势场总增益（每点势变化的加权和）—— 主项。
@export var w_terr: float = 1.0
## 跨越临界：本手让多少个"未定点"变成"已定归属点"。
@export var w_crit: float = 6.0
## 靠近分水岭：|φ-0.5| 最小的地带才是值得落子的地方（围棋的"走在势力边界"）。
@export var w_frontier: float = 2.0
@export var w_capture: float = 14.0
@export var w_atari: float = 7.0
## 救弱块：被标记为"薄"的己方块，其邻居空点势的均值提升量。
@export var w_save: float = 9.0
## 自送吃扣分：落子后本组只剩 1 气、且这一手没提到子。
## ★★ 2026-10-22 实测：从 −18 扫到 **−90**，`--liudrill` ③ **一位不动**。
##   起初以为"扣得不够狠"，查下去是**③ 的判据口径错了** —— 它把盘上本来就有的
##   1 气**孤子**被提也算成"送吃"，而出题条件那边又把单子排除在外，两处自相矛盾。
##   口径改成"落子点所在组的气数"之后：③ = **11/11 = 100%**（三个种子全同）
##   ⇒ 这个引擎**本来就不送吃**，本旋钮在这批题上没有可改进的空间。
##   **别再为了 ③ 去扫它**（§33 死参数 = 旋钮拧不动，再拧只是浪费一轮）。
@export var w_self_atari: float = -18.0
@export var w_libs: float = 1.6
@export var w_center: float = 1.2
## 己方"薄块"的气数门槛（≤ 它才算需要照顾）。
@export var weak_libs: int = 3

## 【尺度分歧】近场与远场对同一空点的归属判定不一致 ⇒ 该点处在"尺度敏感区"
## （小尺度看归黑、大尺度看归白）。围棋里这正是打入/侵消的落点 —— 渗流模型独有的特征。
@export var w_scale: float = 4.0

## 【自填眼位】四邻全是己方子的点（单点眼）且势场已明确归属己方 ⇒ 落进去是自毁一手。
## 流水**不做死活判定**（那会开第二套死活口径），改用"确定性"兜底：
## φ 已很高 = 这块地已经确定归己方，再下一手纯属浪费。
@export var w_fill_eye: float = -30.0
@export var fill_eye_phi: float = 0.85

## 【自保】落子之后，**全盘**己方"只剩 1 气"的组里有多少颗子；按颗数乘本权重扣分。
##
## ★ 2026-10-22 新增，**默认 0.0 = 完全关闭**（关态下评分与旧版逐位相同，见
##   `--liushuitest` 的锚点判据）—— 这样 A/B 只有"这一个轴"在动（§47）。
## ★★ 为什么要这一项（实测数据，见战报）：流水对两强 0:10，终局 0~40 分，
##   提子 **流水 212 : 对方 1242**（10 局）⇒ 平均每局落 123 子、**被提 124 子**，
##   放上去的几乎全被提回来 —— "成片被提、死了再填"。
##   旧评估里**只有"新落这颗子所在那块"的气数**（`w_libs`）和渗流势的"救薄块"（`w_save`），
##   而 `w_save` 量的是**势场均值提升**（几何量），不是"会被提"（死活量）。
##   ⇒ 它在别处下一手时，边上自己一块只剩 1 气，评估函数**完全无感**。
## ★ 口径纪律：这里只用「气数」这一个量（`_libs()`），**不做死活判定**
##   （本引擎的立身之本是"不引入第二套死活真源"，见上面 `w_fill_eye` 的同一条注释）。
##   气数 1 = 下一手可被提，这是纯规则事实，不需要活形判断。
@export var w_danger: float = 0.0

## 【自救-局部版】这一手把"落子前只剩 1 气"的己方块救到 ≥2 气 ⇒ 按**救活的子数**加分。
##
## ★★ 为什么必须有这一项（2026-10-22 第二轮，`--liudrill` v2 判据实测）：
##   判据把题面修好后，"该救没救"是 **17/21**（自救 4/21 = 19%）。看评分结构就明白：
##     · 提子 = `w_capture(14) × 提掉的颗数`   ⇒ 提 1 子 = **+14**
##     · 救块 = `w_save(9) × saved`，而 `saved` 是**势场差分的均值**（量级 1e-2）
##       ⇒ 救活一块 = **+0.0X**
##   两者根本不在同一量纲上，所以旧评分在结构上**永远选提子**，与"权衡"无关。
##   这一项把救活也换成"颗数"，于是"救 5 子 vs 提 1 子"才第一次可以比大小。
## ★ 与 `w_danger` 的分工（别混）：
##   `w_danger` = **全局事后扣分**（下完这一手，全盘己方还有几颗子处在 1 气）——
##     它会连带罚那些"与我这一手无关的薄块"，因此一拧大就同时压死捕获（实测 86%→53%）。
##   本项 = **局部事前奖励**（只认"我这一手真的把它救活了"）—— 不碰别处。
## ★ 口径：只用「气数」（`_libs()`），不做死活判定（同 `w_danger` / `w_fill_eye` 的纪律）。
##
## ★★ 2026-10-22 真局 A/B **否决**（`--liudiag=n20`，流水 vs 疾风，同种子同色配对）：
##   训练场上它美得不像话 —— 自救 23%→62%、捕获 92%→90%（三个种子一致、单调），
##   但真局三项结构量**同向恶化**：
##     μΔ目差 **−57.4**（t=−2.9）｜μΔ被提 **+24.0**（t=2.9）｜μΔ大块没救 +5.95｜胜负 6/14
##     （base: 提 275/被提 747 → w14: 提 237/被提 1227，**少提 38、多被提 480**）
##   机制：本项把"1 气 → 2 气"就算救活，而 **2 气在真局里仍是一手可提的死棋**
##   ⇒ 这个奖励买到的是「延命」而不是「做活」；流水于是更爱贴着自己的薄块递子，
##   正好加重它"死了再填"的老毛病。
##   ⇒ **训练场②的"自救率"是 Goodhart 陷阱**：它奖励"把危险推后一手"，与胜负不同向。
##     这一条也顺便解释了 `w_danger` 当年"自救到 50% 就顶住、捕获崩到 53%"的同族现象。
##   默认保持 0.0。留着它当反例可以，别指望它涨棋。
@export var w_rescue: float = 0.0

## 【战术必入根】为真时，把两类点**强制**塞进"进入对手应手精算"的那一批（不受分数截断）：
##   ① 己方"恰 1 气"块的唯一气点（救急 / 连出）
##   ② 对方"恰 1 气"块的气点（提子）
##
## ★ 2026-10-22 新增，**默认 false = 完全关闭**（关态与旧版逐位相同）。
## ★★ 为什么必须有（`--liudrill` 实测）：只把 `w_danger` 拧大，自救只从 11% 升到 50% 就顶住，
##   而捕获从 86% 掉到 53% —— 因为"救点"根本没进根候选，权重再大也没东西可加。
##   关掉这个开关跑同一批题，两个数就是上面那一对；装上它之后两者才可能同时高。
## ★ 这正是围棋引擎的常规做法（候选生成里 atari-escape / capture 永远不靠静态分筛），
##   本引擎先前只靠 `_cheap()` 的静态分 ⇒ 救点被"远离分水岭"那一项扣掉。
## ★ 2026-10-22 实测后**默认改为 true**（这一项是白拿的）：
##   `--liudrill=n60` 同一批 60 个局面，只翻这个开关：
##     捕获 42/49（86%）→ **46/49（94%）**；自救 2/18、不送吃 6/11 **两项一位不动**。
##   机制：救点/提点本来就该"无条件被看到"，它们被静态分筛掉纯属漏（不是权衡）。
##   代价：每手多算几个候选（实测 `--liudrill` 耗时 2.6s → 2.8s / 60 个局面，可忽略）。
## ⚠ 关掉它（`k=tactical_roots=false`）仍可复现旧行为，做 A/B 时有用。
@export var tactical_roots: bool = true

# ---------------------------------------------------------------------------
# 搜索
# ---------------------------------------------------------------------------
@export_group("搜索")
## 根候选数（进入对手应手精算的手数）。
@export var root_width: int = 10
## 对手应手只考虑它自己最好的前几个点。
@export var reply_width: int = 8
## 对手应手的折扣（0 = 完全无视对手，1 = 满额扣减）。
@export var reply_lambda: float = 1.0
@export var komi: float = 0.0
## 软预算：精算循环超时即停，已算的手仍然有效。
@export var time_budget_ms: int = 200

## 【接口兼容】AIEngine 的同名字段在 `game.gd` 里被赋值。流水**不用随机 playout**，
## 因此这里把它映射成**精算候选数上限**（与 `prefilter_width` 取小）—— 仍是真旋钮。
@export var max_playouts: int = 300
## 【接口兼容】线程数。流水是**确定性单线程**引擎（解 Laplace 无随机性），
## 赋值无效；保留只为让 `game.gd` 的赋值语句不报错。
@export var threads: int = 1

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var adj: Array = []
var n: int = 0
var ai_color: int = BLACK
var rng := RandomNumberGenerator.new()

var _as := PackedInt32Array()          # CSR 行偏移
var _af := PackedInt32Array()          # CSR 列
var _deg := PackedInt32Array()
var _b := PackedInt32Array()
var _ko: int = -1
var _turn: int = BLACK
var _centrality := PackedFloat32Array()

# 组搜索缓冲（时间戳法，避免每手 clear）
var _gbuf := PackedInt32Array()
var _gst := PackedInt32Array()
var _gid: int = 0
var _q := PackedInt32Array()

# 局部 BFS 缓冲
var _sq := PackedInt32Array()
var _sd := PackedInt32Array()
var _seen := PackedInt32Array()
var _seen_id: int = 0

# 局部势场工作区（预分配，只重置 S 内的点）
var _work := PackedFloat32Array()

# 分水岭距离图
var _fd := PackedInt32Array()

# 薄块标记
var _weak := PackedInt32Array()
var _weak_n: int = 0

# 自保（`w_danger`）用的**独立**已访问标记。
# ★ 必须是独立的一对：`_libs()` 内部自己就 `_seen_id += 1`（它要用 `_seen` 数气），
#   所以循环里"算一次气"就会把我自己刚打的上层标记**整批作废** ⇒ 同一个块会被重复数，
#   danger 虚高且随扫描顺序漂（静默，不报错）。⇒ 换个数组，两套标记互不干扰。
var _dseen := PackedInt32Array()
var _dseen_id: int = 0

# 自救-局部版（`w_rescue`）：`_play()` 落子**之前**测得的"v 四邻里只剩 1 气的己方块"总子数。
# `_play()` 写、`_value_after_placed()` 读，中间隔着 `_eval_move()` 的两行 ⇒ 一条隐式约定，
# 所以两边都写了注释。关态（`w_rescue == 0`）它恒为 0。
var _pre_rescue: int = 0

# 回滚栈
var _undo := Array()

# 诊断
var last_ms: int = 0
var last_evals: int = 0
var last_scores: Array = []
var last_reply: int = -1


# ===========================================================================
# 生命周期
# ===========================================================================
func setup(adjacency: Array, ai: int, seed: int = 0) -> void:
	adj = adjacency
	n = adjacency.size()
	ai_color = ai
	if seed == 0:
		seed = int(Time.get_ticks_usec())
	rng.seed = seed

	var total := 0
	for i in n:
		total += adjacency[i].size()
	_as.resize(n + 1)
	_af.resize(total)
	_deg.resize(n)
	var w := 0
	for i in n:
		_as[i] = w
		var row: Array = adjacency[i]
		_deg[i] = row.size()
		for v in row:
			_af[w] = int(v)
			w += 1
	_as[n] = w

	_b.resize(n)
	_gbuf.resize(n)
	_gst.resize(n)
	_q.resize(n)
	_sq.resize(n)
	_sd.resize(n)
	_seen.resize(n)
	_dseen.resize(n)
	_work.resize(n)
	_fd.resize(n)
	_weak.resize(n)
	_centrality.resize(n)

	_compute_centrality()
	reset_state()


func reset_state() -> void:
	_b.fill(EMPTY)
	_gst.fill(0)
	_seen.fill(0)
	_dseen.fill(0)
	_gid = 0
	_seen_id = 0
	_dseen_id = 0
	_ko = -1
	_turn = ai_color
	_undo.clear()
	last_ms = 0
	last_evals = 0
	last_scores = []
	last_reply = -1


func clear_board() -> void:
	_b.fill(EMPTY)
	_ko = -1
	_turn = ai_color


## 中心性：从低度点（盘边）多源 BFS，距离越大越靠中腹。
func _compute_centrality() -> void:
	for i in n:
		_fd[i] = -1
	var head := 0
	var tail := 0
	for i in n:
		if _deg[i] < 4:
			_fd[i] = 0
			_q[tail] = i
			tail += 1
	if tail == 0:            # 全 4-正则（无边界）：任取一点作源，退化为单源距离
		_fd[0] = 0
		_q[0] = 0
		tail = 1
	var maxd := 1
	while head < tail:
		var cur := _q[head]
		head += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _fd[nb] < 0:
				_fd[nb] = _fd[cur] + 1
				if _fd[nb] > maxd:
					maxd = _fd[nb]
				_q[tail] = nb
				tail += 1
	var inv := 1.0 / float(maxd)
	for i in n:
		_centrality[i] = float(maxi(_fd[i], 0)) * inv


# ===========================================================================
# 渗流势场：求解 Laplace 方程（Gauss-Seidel）
# ===========================================================================
## 返回 **color 视角** 的归属势：φ=1 表示该点几乎必然归 color，φ=0 表示几乎必然归对方。
## 初值 0.5 = 完全未定。正反向交替扫描以消除图上的扫描方向各向异性。
func _field(color: int, iters: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(n)
	var opp := 3 - color
	for i in n:
		var b := _b[i]
		if b == color:
			f[i] = 1.0
		elif b == opp:
			f[i] = 0.0
		else:
			f[i] = 0.5
	for it in iters:
		var rev := (it & 1) == 1
		for jj in n:
			var i := (n - 1 - jj) if rev else jj
			if _b[i] != EMPTY:
				continue
			var k := _as[i]
			var ke := _as[i + 1]
			if ke <= k:
				continue
			var s := 0.0
			var k0 := k
			while k < ke:
				s += f[_af[k]]
				k += 1
			f[i] = s / float(ke - k0)
	return f


## 多源 BFS 求每个点到"势力分水岭"（|φ-0.5| < frontier_band 的空点）的图距离。
func _frontier_dist(f: PackedFloat32Array) -> void:
	for i in n:
		_fd[i] = -1
	var head := 0
	var tail := 0
	for i in n:
		if _b[i] == EMPTY and absf(f[i] - 0.5) < frontier_band:
			_fd[i] = 0
			_q[tail] = i
			tail += 1
	while head < tail:
		var cur := _q[head]
		head += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _fd[nb] < 0:
				_fd[nb] = _fd[cur] + 1
				_q[tail] = nb
				tail += 1


# ===========================================================================
# 规则：气 / 组 / 落子 / 提子 / 自杀 / 劫（本引擎自足实现）
# ===========================================================================
## 填 _gbuf[0..cnt)，返回组大小。
func _group(start: int) -> int:
	_gid += 1
	var sid := _gid
	var color := _b[start]
	_gbuf[0] = start
	_gst[start] = sid
	var cnt := 1
	var qi := 0
	while qi < cnt:
		var cur := _gbuf[qi]
		qi += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == color and _gst[nb] != sid:
				_gst[nb] = sid
				_gbuf[cnt] = nb
				cnt += 1
	return cnt


## 数组的气（空邻点数，按点去重）。
func _libs(cnt: int) -> int:
	_seen_id += 1
	var sid := _seen_id
	var total := 0
	for j in cnt:
		var cur := _gbuf[j]
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == EMPTY and _seen[nb] != sid:
				_seen[nb] = sid
				total += 1
	return total


func _is_adj(a: int, b: int) -> bool:
	var k := _as[a]
	var ke := _as[a + 1]
	while k < ke:
		if _af[k] == b:
			return true
		k += 1
	return false


## 落子（含提子/自杀/劫）。返回提子数；-1 = 非法。
## 成功后必须配对 `_rollback()`。
## 劫条件与游戏侧同口径：**提一子 且 被提点紧邻落子点** ⇒ 「提一子、自己不止一气」
## 的局面同样要设劫（旧引擎曾多要两项，导致引擎放行而玩家看不到这一手）。
func _play(v: int, color: int) -> int:
	if v < 0 or v >= n or _b[v] != EMPTY or v == _ko:
		return -1
	var opp := 3 - color
	# ★ 自救-局部版（`w_rescue`）：**落子之前**把 v 四邻里"只剩 1 气"的己方块子数记下来。
	#   ⚠ 只能在这里算 —— `_play` 一返回，盘上就多了这颗子，"落子前是几气"再也拿不回来。
	#   默认 `w_rescue == 0.0` ⇒ 整段不跑（关态零开销、评分逐位不变）。
	_pre_rescue = 0
	if w_rescue != 0.0:
		_gid += 1
		var rsid := _gid
		var rk := _as[v]
		var rke := _as[v + 1]
		while rk < rke:
			var rnb := _af[rk]
			rk += 1
			if _b[rnb] != color or _gst[rnb] == rsid:
				continue
			var rcnt := _group(rnb)
			for j in rcnt:
				_gst[_gbuf[j]] = rsid
			if _libs(rcnt) == 1:
				_pre_rescue += rcnt
	_b[v] = color
	var cap: Array[int] = []
	_gid += 1
	var sid := _gid
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != opp or _gst[nb] == sid:
			continue
		var cnt := _group(nb)
		for j in cnt:
			_gst[_gbuf[j]] = sid
		if _libs(cnt) == 0:
			for j in cnt:
				cap.append(_gbuf[j])
	for p in cap:
		_b[p] = EMPTY
	if cap.is_empty():
		var cnt2 := _group(v)
		if _libs(cnt2) == 0:
			_b[v] = EMPTY          # 自杀：状态已复原，不入栈
			return -1
	var newko := -1
	if cap.size() == 1 and _is_adj(v, cap[0]):
		newko = cap[0]
	_undo.append([v, color, cap, _ko])
	_ko = newko
	return cap.size()


func _rollback() -> void:
	if _undo.is_empty():
		return
	var rec: Array = _undo.pop_back()
	var v: int = rec[0]
	var color: int = rec[1]
	var cap: Array = rec[2]
	_b[v] = EMPTY
	for p in cap:
		_b[p] = 3 - color
	_ko = rec[3]


# ===========================================================================
# 局部精算
# ===========================================================================
## BFS 收集 v 的 local_radius 邻域，写入 `_sq[0..tail)`（不含 v 自身周围的层级信息用途：顺序=由近到远）。
func _collect_local(v: int) -> int:
	_seen_id += 1
	var sid := _seen_id
	_sq[0] = v
	_seen[v] = sid
	_sd[v] = 0
	var cnt := 1
	var qi := 0
	while qi < cnt:
		var cur := _sq[qi]
		qi += 1
		var d := _sd[cur]
		if d >= local_radius:
			continue
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _seen[nb] == sid:
				continue
			_seen[nb] = sid
			_sd[nb] = d + 1
			_sq[cnt] = nb
			cnt += 1
	return cnt


## 在**已落子**状态下评估这一手对 color 的价值。
## base 必须是**落子前** color 视角的势场。
func _value_after_placed(v: int, color: int, base: PackedFloat32Array, caps: int) -> Dictionary:
	var opp := 3 - color
	var cnt := _collect_local(v)
	# ★ 自保（`w_danger`）：默认 0.0 ⇒ 这一整块**不跑**（关态零开销、评分逐位不变）。
	#   放在 `_seen` 那一块**之前**算，理由见 `_dseen` 声明处（两处标记必须互不干扰）。
	var danger := 0
	if w_danger != 0.0:
		danger = _own_danger_count(color)

	# 只在邻域内重解 Laplace：区域内空点参与更新，区域外沿用 base（截断边界）。
	# ⚠ 必须**全盘**拷 base：GS 更新只发生在 S 内，但会读 S 外邻居的 `_work`，
	# 留脏值会让远处局面渗进评估（且随候选顺序漂移 ⇒ 不可复现）。
	for i in n:
		_work[i] = base[i]
	for it in local_iters:
		var rev := (it & 1) == 1
		for jj in cnt:
			var i := _sq[(-1 - jj) if rev else jj]
			if _b[i] != EMPTY:
				continue
			var k := _as[i]
			var ke := _as[i + 1]
			if ke <= k:
				continue
			var s := 0.0
			var k0 := k
			while k < ke:
				s += _work[_af[k]]
				k += 1
			_work[i] = s / float(ke - k0)

	# 势场总增益 + 跨越临界点数
	var gain := 0.0
	var crit := 0
	for j in cnt:
		var i := _sq[j]
		if _b[i] != EMPTY:
			continue
		var d := _work[i] - base[i]
		gain += d
		if absf(_work[i] - 0.5) >= crit_band and absf(base[i] - 0.5) < crit_band:
			crit += 1

	# 救薄块：落子前被标薄的己方块，其邻域势均值提升（块的存活度 = 它连到确定区的概率）
	var saved := 0.0
	if _weak_n > 0:
		for j in cnt:
			var i := _sq[j]
			if _weak[i] == 0:
				continue
			var k2 := _as[i]
			var ke2 := _as[i + 1]
			var s2 := 0.0
			var c2 := 0
			while k2 < ke2:
				var nb := _af[k2]
				k2 += 1
				if _b[nb] == EMPTY:
					s2 += _work[nb] - base[nb]
					c2 += 1
			if c2 > 0:
				saved += s2 / float(c2)

	# 气数 / 打吃 / 送吃
	var mylibs := 0
	var atari_sz := 0
	var gcnt := _group(v)
	mylibs = _libs(gcnt)
	_seen_id += 1
	var sid2 := _seen_id
	var k3 := _as[v]
	var ke3 := _as[v + 1]
	while k3 < ke3:
		var nb := _af[k3]
		k3 += 1
		if _b[nb] != opp or _seen[nb] == sid2:
			continue
		var c3 := _group(nb)
		for j in c3:
			_seen[_gbuf[j]] = sid2
		if _libs(c3) == 1:
			atari_sz += c3

	var fd := _fd[v]
	var front := 0.0
	if fd > 0:
		front = 1.0 / float(fd)      # 越贴近分水岭越大
	elif fd == 0:
		front = 1.0

	var score := 0.0
	score += w_terr * gain
	score += w_crit * float(crit)
	score += w_frontier * front
	score += w_capture * float(caps)
	score += w_atari * float(atari_sz)
	score += w_save * saved
	score += w_libs * float(mini(mylibs, 5))
	score += w_center * _centrality[v]
	if mylibs == 1 and caps == 0:
		score += w_self_atari
	# 自救-局部版（`w_rescue`）：只有"落子前薄、落子后整组有 ≥2 气"才算真救活。
	# ★ 为什么必须再判一次 `mylibs >= 2`：`_pre_rescue` 只说明"我贴着一个薄块落子"，
	#   不说明"我把它救活了"（贴着它下一手而它仍是 1 气，是最典型的**送吃**）。
	#   这个二次判定也正是 `w_danger` 曾经想表达、但因为是**全盘**量而误伤捕获的东西。
	var rescue: int = _pre_rescue
	if w_rescue != 0.0:
		if mylibs < 2:
			rescue = 0
		else:
			score += w_rescue * float(rescue)

	# 自填眼位（前提：没提子 —— 提子后四邻未必还是己方子）
	if caps == 0 and w_fill_eye != 0.0 and base[v] > fill_eye_phi and _all_nb_are(v, color):
		score += w_fill_eye
	# 自保：全盘己方"只剩 1 气"的组，按子数扣分（`w_danger` 本身是负值）
	if w_danger != 0.0:
		score += w_danger * float(danger)

	return {
		"score": score, "gain": gain, "crit": crit, "caps": caps,
		"mylibs": mylibs, "atari": atari_sz, "saved": saved, "front": front,
		"danger": danger, "rescue": rescue,
	}


## 「战术必入根」要的那批点：己方 1 气块的唯一气点（救）+ 对方 1 气块的气点（提）。
## 返回的是**候选点集合**（去重），由 `choose_move()` 决定怎么塞进根候选。
## ★ 只数"1 气"：2 气以上的块还有一手缓冲，交给搜索去权衡；把 2 气也算进来会让根候选
##   被一堆"半危"点占满（实测会让 `--liudrill` 的捕获题一起掉）。
func _tactical_points(color: int) -> Array[int]:
	var opp := 3 - color
	var out: Array[int] = []
	_dseen_id += 1
	var sid := _dseen_id
	for i in n:
		if _b[i] == EMPTY or _dseen[i] == sid:
			continue
		var cnt := _group(i)
		for j in cnt:
			_dseen[_gbuf[j]] = sid
		if _libs(cnt) != 1:
			continue
		var col := _b[i]
		if col != color and col != opp:
			continue
		# 这块唯一的那一口气点（可能不止一个点只有 1 气？不会：气数=1 ⇒ 恰好一个点）
		for j in cnt:
			var cur := _gbuf[j]
			var k := _as[cur]
			var ke := _as[cur + 1]
			while k < ke:
				var nb := _af[k]
				k += 1
				if _b[nb] == EMPTY and nb != _ko and not out.has(nb):
					out.append(nb)
	return out


## 全盘己方"只剩 1 气"的组，返回**子数合计**（`w_danger` 的输入）。##
## ★ 用 `_dseen`/`_dseen_id` 这一对独立标记（不与 `_seen` 共用），理由见声明处。
## ★ 只数"1 气"这一档：2 气及以上的块还有一手缓冲，本引擎的搜索深度（一级应手）
##   看得住它；把 2 气也算进来会把"正常收气"误判成危机。
func _own_danger_count(color: int) -> int:
	_dseen_id += 1
	var sid := _dseen_id
	var tot := 0
	for i in n:
		if _b[i] != color or _dseen[i] == sid:
			continue
		var cnt := _group(i)
		for j in cnt:
			_dseen[_gbuf[j]] = sid
		if _libs(cnt) == 1:
			tot += cnt
	return tot


## 四邻全是 color 子（落子后调用 ⇒ v 自己是 color，只看其邻居）。
func _all_nb_are(v: int, color: int) -> bool:
	if _as[v + 1] <= _as[v]:
		return false
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		if _b[_af[k]] != color:
			return false
		k += 1
	return true


## 完整评估一手（内部配对落子/回滚）。
func _eval_move(v: int, color: int, base: PackedFloat32Array) -> Dictionary:
	var caps := _play(v, color)
	if caps < 0:
		return {}
	var r := _value_after_placed(v, color, base, caps)
	_rollback()
	return r


# ===========================================================================
# 级 1：廉价预筛（不碰势场）
# ===========================================================================
func _cheap(v: int, color: int, base: PackedFloat32Array) -> float:
	var opp := 3 - color
	var s := 0.0
	var own_nb := 0
	var opp_nb := 0
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] == color:
			own_nb += 1
		elif _b[nb] == opp:
			opp_nb += 1
	s += 3.0 * float(own_nb)
	s += 2.0 * float(opp_nb)
	# 四邻全己方子 = 单点眼位，预筛阶段先扣一次，别让它挤掉真候选
	if own_nb > 0 and own_nb == _deg[v]:
		s -= 20.0
	# 势场局部曲率：空点势高于四邻均值 = 此处是己方势力的"凹陷"，补上能扩张
	s += 6.0 * (0.5 - base[v])
	var fd := _fd[v]
	if fd > 0:
		s += 2.0 / float(fd)
	elif fd == 0:
		s += 2.0
	return s


# ===========================================================================
# 主入口
# ===========================================================================
## 线程入口包装：在后台线程完整跑一次思考（供 `choose_move_async` 使用）。
func _search_entry(board_snapshot: Dictionary, ko: int, ai: int) -> int:
	return choose_move(board_snapshot, ko, ai)


## 协程版主入口：思考在后台线程进行，主线程每帧让出、界面不冻结。
## 用法：`var mv: int = await ai_liushui.choose_move_async(board, ko_point, AI_COLOR)`
##
## ★ 形状与 `AIEngine.choose_move_async()` **逐字对齐**（快照拷贝 → 后台线程 → 每帧 await →
##   等线程结束取返回值）。理由不是风格统一：`game.gd::_start_ai_turn()` 里两档共用同一段
##   收尾逻辑（`gen != _ai_gen` 作废 + `_apply_ai_move`），任何形状差异都会让那条作废机制
##   在其中一档上失效 —— 而失效的症状是"重置后旧着法落到新盘上"，偶发且极难复现。
##
## ⚠️ 必须拷快照：后台线程只碰这份拷贝。`board` 是 `Dictionary[int→int]`（引用语义），
##   游戏侧在思考期间仍可能改它（悔棋 / 重置），并发读写同一 Dictionary 会**崩**。
func choose_move_async(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	var snap: Dictionary = {}
	for k in board_dict.keys():
		snap[k] = int(board_dict[k])
	var th := Thread.new()
	th.start(_search_entry.bind(snap, ko, ai), Thread.PRIORITY_NORMAL)
	var tree := Engine.get_main_loop() as SceneTree
	while th.is_alive():
		if tree != null:
			await tree.process_frame
		else:
			OS.delay_msec(4)
	return int(th.wait_to_finish())


## 给定当前棋盘与劫点，返回 AI 落子瓷砖号（-1 表示停一手）
func choose_move(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	if ai != -1:
		ai_color = ai
	var t0 := Time.get_ticks_msec()
	_load_board(board_dict, ko)
	_undo.clear()
	last_evals = 0
	last_scores = []
	last_reply = -1

	var color := ai_color
	var opp := 3 - color

	# ---- 1. 全局势场（远场＝已收敛，做评估基准）+ 近场（做尺度分歧）+ 分水岭 + 薄块 ----
	var f_own := _field(color, iters_far)
	var f_near := _field(color, iters_near)
	_frontier_dist(f_own)
	_mark_weak(color)

	# ---- 2. 级 1 廉价筛选 ----
	var plain: Array[int] = []
	for i in n:
		if _b[i] == EMPTY and i != _ko:
			plain.append(i)
	if plain.is_empty():
		last_ms = Time.get_ticks_msec() - t0
		return -1

	var cheap_scores: Array = []
	for v in plain:
		cheap_scores.append([_cheap(v, color, f_own), v])
	cheap_scores.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var pool: Array[int] = []
	var lim := mini(mini(prefilter_width, max_playouts), cheap_scores.size())
	for i in lim:
		pool.append(int(cheap_scores[i][1]))

	# ---- 3. 级 2 局部势场精算 ----
	# ★ 战术必入根（`tactical_roots`）：把"己方 1 气块的气点 / 对方 1 气块的气点"先塞进候选池，
	#   否则它们可能连精算都进不去（`_cheap()` 里"远离分水岭"那一项会把救点扣掉）。
	var tactical: Array[int] = []
	if tactical_roots:
		tactical = _tactical_points(color)
		for tv in tactical:
			if not pool.has(tv):
				pool.append(tv)
	var evaled: Array = []
	for v in pool:
		if Time.get_ticks_msec() - t0 > time_budget_ms:
			break
		var r := _eval_move(v, color, f_own)
		last_evals += 1
		if r.is_empty():
			continue
		# 尺度分歧：近场与远场判定不同 ⇒ 尺度敏感区（渗流模型独有的落点信号）
		var disc := absf(f_own[v] - f_near[v])
		var sc := float(r["score"]) + w_scale * disc
		r["disc"] = disc
		evaled.append([sc, v, r])
	if evaled.is_empty():
		last_ms = Time.get_ticks_msec() - t0
		return -1
	evaled.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	# ---- 3b. 战术点提到最前（只改**顺序**，不改分数）----
	#   为什么不是"加分"：加分会被别的项抵消，而这批点的要求是"**一定要被应手精算看到**"。
	#   提到最前 ⇒ 它们必然落在下面 `for i in top` 的范围内（`top` 还会为它们扩容）。
	var tac_front := 0
	if not tactical.is_empty():
		var front: Array = []
		var rest: Array = []
		for e in evaled:
			if tactical.has(int(e[1])):
				front.append(e)
			else:
				rest.append(e)
		evaled = front + rest
		tac_front = front.size()

	# ---- 4. 对手应手（前 root_width 手，且战术点一个都不许被截掉）----
	var top := mini(maxi(root_width, tac_front), evaled.size())
	var best_v := -1.0e18
	var best_p := -1
	for i in top:
		var v: int = evaled[i][1]
		var my: float = evaled[i][0]
		if _play(v, color) < 0:
			continue
		# 己方落子后**重解**对手视角的近场势（只 8 次迭代，便宜且比 1-φ 近似准：
		# 提子会把对方的"墙"变成"通道"，这一步 1-φ 表达不了）
		var f_opp_now := _field(opp, iters_mid)
		var rep := _best_reply(opp, f_opp_now, t0)
		_rollback()
		var net := my - reply_lambda * rep
		if net > best_v:
			best_v = net
			best_p = v

	if best_p < 0:
		best_p = int(evaled[0][1])

	for i in mini(8, evaled.size()):
		last_scores.append([int(evaled[i][1]), float(evaled[i][0])])

	last_ms = Time.get_ticks_msec() - t0
	return best_p


## 在兄弟局面下找对手最佳应手的分（只做一级，宽度 reply_width）。
func _best_reply(opp: int, f_opp: PackedFloat32Array, t0: int) -> float:
	# 薄块标记必须换成对手视角再评（`_weak` 平时装的是己方的薄块；
	# 借用己方标记会让 `w_save` 在对手应手上量错对象）
	_mark_weak(opp)
	var best := 0.0
	var pool: Array = []
	for i in n:
		if _b[i] == EMPTY and i != _ko:
			pool.append([_cheap(i, opp, f_opp), i])
	if pool.is_empty():
		return 0.0
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var lim := mini(reply_width, pool.size())
	for i in lim:
		if Time.get_ticks_msec() - t0 > time_budget_ms * 2:
			break
		var r := _eval_move(int(pool[i][1]), opp, f_opp)
		last_evals += 1
		if r.is_empty():
			continue
		var s := float(r["score"])
		if s > best:
			best = s
			last_reply = int(pool[i][1])
	return best


## 标记"薄"的己方块：气数 ≤ weak_libs 且所在组规模 < 8（大块不慌）。
func _mark_weak(color: int) -> void:
	_weak.fill(0)
	_weak_n = 0
	_gid += 1
	var sid := _gid
	for i in n:
		if _b[i] != color or _gst[i] == sid:
			continue
		var cnt := _group(i)
		var libs := _libs(cnt)
		for j in cnt:
			_gst[_gbuf[j]] = sid
		if libs <= weak_libs and cnt < 8:
			# 组本身 + 它的空邻居都标上（落子在邻居处才算"救"）
			for j in cnt:
				_weak[_gbuf[j]] = 1
				var p := _gbuf[j]
				var k := _as[p]
				var ke := _as[p + 1]
				while k < ke:
					if _b[_af[k]] == EMPTY:
						_weak[_af[k]] = 1
					k += 1
			_weak_n += cnt


func _load_board(board_dict: Dictionary, ko: int) -> void:
	for i in n:
		_b[i] = int(board_dict.get(i, EMPTY))
	_ko = ko
	_turn = ai_color


func export_board() -> Dictionary:
	var d := {}
	for i in n:
		if _b[i] != EMPTY:
			d[i] = int(_b[i])
	return d


## 造中盘局面用于自测：随机合法手，避开自己单点眼。
func scramble(moves: int) -> void:
	clear_board()
	_turn = BLACK
	_undo.clear()
	var played := 0
	var stuck := 0
	while played < moves and stuck < 40:
		var v := _pick_scramble_move(_turn)
		if v < 0:
			_turn = 3 - _turn
			stuck += 1
			continue
		if _play(v, _turn) < 0:
			_turn = 3 - _turn
			stuck += 1
			continue
		_undo.clear()          # 固定下来，不倒扣（_ko 由 _play 设好并保留）
		played += 1
		stuck = 0
		_turn = 3 - _turn


func _pick_scramble_move(color: int) -> int:
	var cand: Array[int] = []
	for i in n:
		if _b[i] != EMPTY or i == _ko:
			continue
		# 不填自己的单点眼
		if _is_own_eye(i, color):
			continue
		cand.append(i)
	if cand.is_empty():
		return -1
	return cand[rng.randi() % cand.size()]


func _is_own_eye(v: int, color: int) -> bool:
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		if _b[_af[k]] != color:
			return false
		k += 1
	return true


# ===========================================================================
# 面积计分（终局口径，供将来接入/对照用）
# ===========================================================================
func area_score() -> float:
	_seen.fill(0)
	var sc := 0.0
	_gid += 1
	var sid := _gid
	for i in n:
		if _b[i] == BLACK:
			sc += 1.0
		elif _b[i] == WHITE:
			sc -= 1.0
	# 空区归属：只被一方接触的地归该方
	_seen_id += 1
	var sid2 := _seen_id
	for i in n:
		if _b[i] != EMPTY or _seen[i] == sid2:
			continue
		_gbuf[0] = i
		_gst[i] = sid
		_seen[i] = sid2
		var cnt := 1
		var qi := 0
		var touch_b := false
		var touch_w := false
		while qi < cnt:
			var cur := _gbuf[qi]
			qi += 1
			var k := _as[cur]
			var ke := _as[cur + 1]
			while k < ke:
				var nb := _af[k]
				k += 1
				if _b[nb] == BLACK:
					touch_b = true
				elif _b[nb] == WHITE:
					touch_w = true
				elif _seen[nb] != sid2:
					_seen[nb] = sid2
					_gbuf[cnt] = nb
					cnt += 1
		if touch_b and not touch_w:
			sc += float(cnt)
		elif touch_w and not touch_b:
			sc -= float(cnt)
	return sc - komi


## 诊断：返回当前局面的渗流势场摘要（自测用）。
func probe_field(color: int, iters: int = -1) -> Dictionary:
	var k := iters_far if iters < 0 else iters
	var f := _field(color, k)
	var undet := 0
	var mine := 0
	var theirs := 0
	for i in n:
		if _b[i] != EMPTY:
			continue
		if absf(f[i] - 0.5) < frontier_band:
			undet += 1
		elif f[i] > 0.5:
			mine += 1
		else:
			theirs += 1
	return {"field": f, "undetermined": undet, "mine": mine, "theirs": theirs}
