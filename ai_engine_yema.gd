class_name YemaAI
extends RefCounted

## 「野马」——神经网络先验 + 磐石搜索（2026-10-23）
##
## 分工（这是本引擎唯一的立论，改之前先读）：
##   · **网络**（`NNScore`，17 维或 25 维点级特征，按权重的 `feat_dim` 二选一）负责
##     **根层候选排序**。它学的是教师
##     （`AIEngine`，`pt=500`）在 1442 个彭罗斯局面上的偏好；跨盘（183 点立方体盘，
##     一手都没训练过）`top1 = 30.3%`，同特征线性基线只有 10.5%。
##     ★ 25 维口径（v2，2026-10-24）追加了 8 维**生死结构**：落子后的气数/组子数/
##       提子数/救子数/对方最小气/抱团连边/送吃标记。v1 的 17 维里"邻居"只以计数出现，
##       没有任何一维描述生死 ⇒ 这是真局 A/B 打成 1:11 的根因（见文件末尾那段警告）。
##   · **搜索**（`AIEngine`）负责**读深**——沿用它成熟的 playout / 提子 / 征子 / 硬过滤。
##
## ★ 为什么不让网络直接落子：`NNScore.score_points()` 一次要把全盘特征算一遍
##   （两次多源 BFS + ring2）⇒ 实测整盘 3~8ms，而引擎单次评估预算只有 **0.75ms**
##   ⇒ 它**进不了 playout**。而且纯贪心 top1 只有 35.7%（教师一致率），当落子函数太弱。
##   当**先验**才是它该待的位置 —— `ai_engine.gd::_effective_root_width` 的注释原话：
##   「加时间不如改先验」。
##
## ★ 关态纪律：`nn_enabled = false` 或 `nn_weight = 0` 时，`inner.ext_prior` 清空、
##   `w_external_prior = 0` ⇒ `ai_engine.gd::_prepare_root()` 走**完全原路径**，
##   逐位等价于磐石。这是 A/B 的基线，不许破坏。
##
## ★ `g_ply` 的近似：训练时 `ply` 是真实手数，但引擎侧没有这个概念。这里用
##   **盘上非空点数**代替（被抓的子会让真实手数偏大 10% 左右 ⇒ `g_ply` 偏小约 0.05）。
##   这是已知近似：网络对 `g_ply` 的依赖若很重，这个偏差会体现在实战强度上。
##
## ★★★ 实测棋力（2026-10-23，`--yemaduel` 12 局）：**开网络 1 胜 / 关网络 11 负**。
##   · pw30/w=1.00：0:4（z=−2.00）｜pw100/w=1.00：1:3（z=−1.00）｜pw100/w=0.30：0:4（z=−2.00）
##   · **w=0.3 比 w=1.0 更差** ⇒ 不是"权重给多了"，而是**网络排序的信息量本身低于
##     磐石的 `_root_score`**（那套是提子/救子/征子/影响力/贴身应战调出来的复合启发式）。
##   机制：pw 小时**先验决定一切**，搜索来不及修正；而网络只是"教师最终选哪"的模仿
##   （跨盘 top1 30.3%），学不到教师强度所依赖的搜索修正。
##   ⇒ **"用网络替换先验"这个方向本身是错的**，不是"再训训就好"。要真提升，至少得让网络
##     **看到**那些启发式（当特征喂进去 / 只做 tie-break），而不是接管排序。
##   ⚠️ `--yematest` 全绿**不代表野马更强** —— 它量的是"接得对"（权重加载 / 钩子位置 /
##     关态等价 / 先验真的进了根层 / 特征不漂），不是棋力。两件事必须分开说。

@export_group("搜索（转发给磐石）")
## 每手思考预算。磐石默认 200ms；野马多花的是 NN 打分那 3~8ms（见 `last_priors_ms`）。
@export var time_budget_ms: int = 200
## 0 = 用 `AIEngine` 自己的默认线程数。
@export var threads: int = 0
@export var komi: float = 0.0
## 0 = 自动（用 `auto_root_width`）。
@export var root_width: int = 0
@export var auto_root_width: int = 14

@export_group("神经先验")
## 总开关。关掉 ⇒ 逐位等价于磐石（A/B 用）。
@export var nn_enabled: bool = true
## 先验混合权重：0 = 纯磐石排序，1 = 纯网络排序。
## ★ 用**名次混合**而不是分数混合：`_root_score` 的量纲是几万，网络输出是 −4.5~−1.6，
##   直接加权等于让网络消失。名次对量纲完全不敏感（`ai_engine.gd::_prepare_root` 里实现）。
@export var nn_weight: float = 1.0
@export var weights_path: String = "res://ai/yema_weights.json"
## 权重缺失/不可用时是否允许「静默退化成磐石」。默认 false —— 宁可开局就报红，
## 也不要让人以为在下野马、其实在下磐石（那种错没人看得出来）。
@export var allow_fallback_to_panshi: bool = false

var nn: NNScore = null
var inner: AIEngine = null
var adj: Array = []
var n: int = 0
var ai_color: int = 1

## 诊断（给自检/探针读，判据量得到才叫有牙齿）
var nn_ready: bool = false
var nn_error: String = ""
var last_priors_ms: int = -1
var last_ply: int = -1
var last_nn_ms: int = -1
var prior_calls: int = 0
var fallback_calls: int = 0


## `seed` 与磐石同义：同一 seed + 同一局面 ⇒ 同一手（关掉网络时必须可复现）。
func setup(adjacency: Array, ai: int, seed: int = 0) -> void:
	adj = adjacency
	n = adjacency.size()
	ai_color = ai
	inner = AIEngine.new()
	inner.setup(adjacency, ai, seed)
	_apply_search_params()
	nn = NNScore.new()
	nn.setup(adjacency)
	nn_ready = nn.load_weights(weights_path)
	if not nn_ready:
		nn_error = "load_weights(%s) 失败（文件缺失 / 不是 mlp / exportable=false）" % weights_path
		push_error("[YemaAI] " + nn_error)


func _apply_search_params() -> void:
	if inner == null:
		return
	inner.time_budget_ms = time_budget_ms
	inner.komi = komi
	if threads > 0:
		inner.threads = threads
	if root_width > 0:
		inner.root_width = root_width
	inner.auto_root_width = auto_root_width


## 把网络分数注入内部磐石的根先验。**必须在 `choose_move*` 之前调用**：
## `choose_move_async` 一进去就把棋盘快照丢给后台线程，那时再写 `ext_prior` 就晚了
## （线程已经在读 ⇒ 数据竞争，且大概率读到上一手的先验）。
func _prepare_prior(board: Dictionary, ko: int, ai: int) -> void:
	var c: int = ai if ai != -1 else ai_color
	if not nn_enabled or not nn_ready or nn_weight <= 0.0:
		inner.ext_prior = PackedFloat32Array()
		inner.w_external_prior = 0.0
		fallback_calls += 1
		return
	var stones := 0
	for v in n:
		if int(board.get(v, 0)) != 0:
			stones += 1
	last_ply = stones
	var t0 := Time.get_ticks_usec()
	inner.ext_prior = nn.score_points(board, c, stones, ko)
	inner.w_external_prior = clampf(nn_weight, 0.0, 1.0)
	last_priors_ms = int((Time.get_ticks_usec() - t0) / 1000)
	last_nn_ms = last_priors_ms
	prior_calls += 1


## 与 `AIEngine.choose_move_async` 同签名同语义（快照 + 后台线程 + `gen != _ai_gen` 作废），
## 所以 `game.gd` 的收尾代码一行都不用分叉。
func choose_move_async(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	if inner == null:
		push_error("[YemaAI] choose_move_async 在 setup() 之前被调用")
		return -1
	if not nn_ready and not allow_fallback_to_panshi:
		push_error("[YemaAI] 网络不可用且 `allow_fallback_to_panshi=false` ⇒ 拒绝走棋。"
			+ " 修好 %s，或显式把 allow_fallback_to_panshi 打开（那就不是野马了）。"
			% weights_path)
		return -1
	_prepare_prior(board_dict, ko, ai)
	return await inner.choose_move_async(board_dict, ko, ai)


## 同步版（自检/探针用）。同样先注入先验。
func choose_move(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	if inner == null:
		push_error("[YemaAI] choose_move 在 setup() 之前被调用")
		return -1
	if not nn_ready and not allow_fallback_to_panshi:
		push_error("[YemaAI] 网络不可用，拒绝走棋（同 choose_move_async）")
		return -1
	_prepare_prior(board_dict, ko, ai)
	return inner.choose_move(board_dict, ko, ai)
