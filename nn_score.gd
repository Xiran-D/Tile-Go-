class_name NNScore
extends RefCounted

## 瓷砖围棋 · 神经网络评分的**引擎侧前向推理**（纯 GDScript，零依赖）。
##
## 用法：
##   var nn := NNScore.new()
##   nn.setup(adjacency)                       # 一次，随盘型
##   nn.load_weights("user://nn_weights.json") # 一次
##   nn.check_golden(golden_path)              # 接入前跑一次，返回 0 才可信
##   var sc := nn.score_points(board, color, ply, ko)   # 每手一次，长度 = 点数
##
## ★★ 五条硬约束（改之前先读）
## 1. **特征只有一份实现**（`_feat_at()`）。`score_points()` 与 `check_golden()` 都走它。
##    早先我把它内联进 `score_points` 求快，结果 `check_golden` 只能自己再写一遍
##    ⇒ "两份都错得一样就永远绿"，等于没有对拍（本项目 §70 的形态）。
## 2. **特征必须与 `nn/nn_data.py::point_feats` 逐位一致**。分叉的症状是
##    "引擎好像没变强"，**不报任何错**（§13）。所以拿训练脚本导出的
##    `features_golden.json` 跑 `check_golden()`，差 > 1e-6 就是分叉。
## 3. **一次算全盘特征，再逐点前向**。`d_own`/`d_opp` 是两次多源 BFS（O(n+E)），
##    绝不能挪成"每候选各算一遍"（120 候选 = 240 次 BFS）。
##    整盘一次约 3~8ms（120 格）⇒ **只能做根候选评分/先验，不能进 playout**
##    （引擎单次评估预算 0.75ms，实测 800ms / 372 playouts）。
##    v2 多出来的 `_group_info()` 同理：**整盘一次**，不许逐候选重跑。
## 4. **盘型无关**：特征只依赖"该点邻域 + 归一化全局量"，与点数/度数无关
##    ⇒ 120 格彭罗斯上训的权重可以直接喂 204/360 格的盘。
## 5. **两档口径并存**（2026-10-24）：`feat_version` 1 = 前 17 维（v1 老权重），
##    2 = 追加 8 维结构特征（v2）。由权重的 `feat_dim` 决定，**不是**代码里写死的。
##    理由：线上已经有一份 v1 权重在跑，删掉 v1 分支等于让它在下次加载时静默算错；
##    而只留 v1 又用不上新特征。⇒ 两档都留，各配一份 golden（`ai/yema_golden_v1.json`
##    与 `ai/yema_golden.json`），`--yematest` ⑦ 两份都跑 ⇒ 两条分支各有一把刀（§138）。
## 6. **两种结构并存**（2026-10-26）：`arch = "mlp" | "gnn"`，由权重 json 决定。
##    mlp 是**逐点独立**前向；gnn 必须**整盘一起**算（邻接聚合要看到别的候选的隐状态）。
##    两者共用特征阶段 ⇒ 「特征对拍通过」**不代表**「前向通过」，前向另有 golden 的
##    `scores` 字段对拍（`check_golden()` 会印出两行）。
##    实测（彭罗斯 120 格，空盘 120 候选 = 每手上界）：mlp 2449 参数 13ms；
##    gnn h=32/1 层 4001 参数 **14ms**；gnn h=64/2 层 26561 参数 86ms ⇒ **宽度是成本的主项**，
##    `--gumbel_c` 那种"多给点数"的思路在引擎侧不成立（预算 200ms/手）。

const INF_D := 999999
const EMPTY := 0

## 两档特征维（= `_feat_at()` 会产出的长度）。`feat_dim` 只能取这两个值之一。
const FEAT_DIM_V1 := 17
const FEAT_DIM_V2 := 25

# 归一化常数（缺省值；`load_weights()` 会用 json 里的 norm 段覆盖）
var n_deg_div := 4.0
var n_ring2_div := 16.0
var n_ply_div := 200.0
var n_n_div := 200.0
var n_komi_div := 10.0
var n_dmax := 5.0
var n_komi := 0.0
# v2 结构特征的归一化常数（clamp 上界 = 除数，与 nn_data.py 的 LIB_DIV/... 必须同值）
var n_lib_div := 8.0
var n_size_div := 20.0
var n_cap_div := 10.0
var n_save_div := 10.0
var n_opplib_div := 8.0

var adj: Array = []
var n: int = 0
var deg := PackedInt32Array()
var deg_max: int = 1
var deg_mean: float = 1.0
var ring2: Array = []          # ring2[v] = 2-hop 邻居（不含 1-hop 自己）
var d_rim := PackedInt32Array()

## 权重声明了几维（17 或 25）。**只用于闸门与自检打印** —— 真正决定 `_feat_at()`
## 产出长度的东西是 `feat_version`（一处真源，别让两个变量各算一遍）。
var feat_dim: int = FEAT_DIM_V2
## 特征口径：1 ⇒ 17 维；2 ⇒ 25 维（追加 8 维结构特征）。
var feat_version: int = 2
var feat_names: Array = []
var layers: Array = []         # [{W: [[float]], b: [float]}]   —— 仅 mlp 用

# --- 图网络（arch == "gnn"，2026-10-26 起可上引擎）---
## "mlp" | "gnn"。由权重 json 决定，缺省 mlp（旧权重不用改）。
var arch: String = "mlp"
## 隐层宽度 h（gnn）。0 = 没加载 gnn 权重。
var g_h: int = 0
## 每层的线性层，**加载时就把 W 转成 PackedFloat32Array**：
## 原始 json 的 W 是 Array[Array[Variant]]，逐元素 `float(row[j])` 是 Variant 转换，
## 实测占掉大部分时间。图前向约 290 万次乘加（MLP 只有 28 万），必须先把类型钉死。
## 结构：{W: Array[PackedFloat32Array], b: PackedFloat32Array}
var g_enc: Dictionary = {}
var g_msg: Array = []          # [{W,b}] × n_layers，**无激活**（Python 里 m(h[src])）
var g_upd: Array = []          # [{W,b}] × n_layers，拼接 [h, agg] 后过 relu
var g_out: Dictionary = {}

## 一次图前向的深度（= g_msg.size()），便于自检打印
var last_graph_ms: int = 0

## `check_golden()` 上一次跑到的有效分母（= 实际复算的点数）。
## ★ 有它才能把"分母 0"和"全对"分开 —— 否则 golden 的盘型对不上时
##   每个局面都被 `continue` 跳过，`bad` 恒 0 ⇒ 长得跟"通过"一模一样（§106）。
var golden_checked: int = 0
## 前向对拍的有效分母（golden 里带 `scores` 时才有）
var forward_checked: int = 0


func setup(adjacency: Array) -> void:
	adj = adjacency
	n = adjacency.size()
	deg.resize(n)
	deg_max = 1
	var s := 0
	for v in n:
		var dv: int = adjacency[v].size()
		deg[v] = dv
		s += dv
		if dv > deg_max:
			deg_max = dv
	deg_mean = float(s) / float(maxi(n, 1))
	_compute_ring2()
	_compute_d_rim()


## 2-hop 邻居表（与盘面无关 ⇒ 只算一次）。
func _compute_ring2() -> void:
	var seen := PackedInt32Array()
	seen.resize(n)
	var sid := 0
	ring2 = []
	ring2.resize(n)
	for v in n:
		sid += 1
		seen[v] = sid
		for u in adj[v]:
			seen[u] = sid
		var two: Array = []
		for u in adj[v]:
			for w in adj[u]:
				if seen[w] != sid:
					seen[w] = sid
					two.append(w)
		ring2[v] = two


## "盘缘" = 度数低于最大度数的点（不规则密铺的边缘点）。
## ★ 不用几何坐标判缘：那样就把盘型几何带进了推理层，而这份代码必须与盘型无关。
func _compute_d_rim() -> void:
	var srcs: Array = []
	for v in n:
		if deg[v] < deg_max:
			srcs.append(v)
	d_rim = _multi_bfs(srcs)


func _multi_bfs(srcs: Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(INF_D)
	var q: Array = []
	for s in srcs:
		dist[s] = 0
		q.append(s)
	var qi := 0
	while qi < q.size():
		var cur: int = q[qi]
		qi += 1
		var d1: int = dist[cur] + 1
		for nb in adj[cur]:
			if dist[nb] > d1:
				dist[nb] = d1
				q.append(nb)
	return dist


func _dist_from_stones(board: Dictionary, color: int) -> PackedInt32Array:
	var srcs: Array = []
	for v in n:
		if int(board.get(v, EMPTY)) == color:
			srcs.append(v)
	if srcs.is_empty():
		var far := PackedInt32Array()
		far.resize(n)
		far.fill(INF_D)
		return far
	return _multi_bfs(srcs)


func load_weights(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[NNScore] 打不开 %s" % path)
		return false
	var txt := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("[NNScore] %s 不是合法 JSON" % path)
		return false
	var dd: Dictionary = d
	# ★ 拒收"不能上引擎"的权重。`exportable:false` 是训练脚本给"只导了一半"的网络
	#   打的标记（历史上 gnn 只导 enc 层）。那种文件拿来前向会算出一堆**看起来像分数**
	#   的随机数，而且不会报错 ⇒ 这条检查必须靠字段，不能靠文件名自觉。
	var want_arch: String = str(dd.get("arch", "mlp"))
	if not bool(dd.get("exportable", true)):
		push_error("[NNScore] 拒收 %s：exportable=false ⇒ 这份权重不是完整的前向网络" % path)
		return false
	if want_arch != "mlp" and want_arch != "gnn":
		push_error("[NNScore] 拒收 %s：未知 arch=%s（只认 mlp / gnn）" % [path, want_arch])
		return false
	# ★★ 维度闸门（2026-10-24）：合法维数**只有两档**，别的一律拒收。
	#   原代码是 `feat_dim = int(dd.get("feat_dim", feat_dim))` —— 让 JSON **覆盖**本侧、
	#   且不校验 ⇒ 一旦特征扩容，有人拿旧权重进来：`layers` 的 W 列数与实际输入维不匹配，
	#   `_forward()` 里 `row[j]` 越界（或静默少算一部分）⇒ 算出一堆"看起来像分数"的东西，
	#   而本函数照样 `return true`。同族：上面 arch / exportable 那两条闸门。
	var want_dim: int = int(dd.get("feat_dim", -1))
	if want_dim != FEAT_DIM_V1 and want_dim != FEAT_DIM_V2:
		push_error("[NNScore] 拒收 %s：feat_dim=%d 不是本侧支持的两档（%d=v1 / %d=v2）"
			% [path, want_dim, FEAT_DIM_V1, FEAT_DIM_V2]
			+ "（特征改过就必须重训权重；旧权重喂新特征不会报错，只会静默算错）")
		return false
	feat_dim = want_dim
	feat_version = 1 if want_dim == FEAT_DIM_V1 else 2
	# `feat_dim` 与 `feat_version` 两个字段必须自洽（训练脚本两个都写；手改过的文件会露馅）
	var want_ver: int = int(dd.get("feat_version", feat_version))
	if want_ver != feat_version:
		push_error("[NNScore] 拒收 %s：feat_dim=%d 对应 v%d，但 feat_version=%d"
			% [path, want_dim, feat_version, want_ver])
		return false
	var nrm: Dictionary = dd.get("norm", {})
	n_deg_div = float(nrm.get("deg_div", n_deg_div))
	n_ring2_div = float(nrm.get("ring2_div", n_ring2_div))
	n_ply_div = float(nrm.get("ply_div", n_ply_div))
	n_n_div = float(nrm.get("n_div", n_n_div))
	n_komi_div = float(nrm.get("komi_div", n_komi_div))
	n_dmax = float(nrm.get("dmax", n_dmax))
	n_komi = float(nrm.get("komi", n_komi))
	n_lib_div = float(nrm.get("lib_div", n_lib_div))
	n_size_div = float(nrm.get("size_div", n_size_div))
	n_cap_div = float(nrm.get("cap_div", n_cap_div))
	n_save_div = float(nrm.get("save_div", n_save_div))
	n_opplib_div = float(nrm.get("opplib_div", n_opplib_div))
	feat_names = dd.get("feat_names", [])
	arch = want_arch
	if arch == "mlp":
		layers = dd.get("layers", [])
		if layers.size() > 0:
			# 形状守卫：第一层 W 的列数必须等于特征维（`feat_dim` 一致但 layers 内部错也要拦）
			var w0: Array = (layers[0] as Dictionary).get("W", [])
			if w0.size() > 0 and (w0[0] as Array).size() != feat_dim:
				push_error("[NNScore] 拒收 %s：第一层 W 列数 %d ≠ feat_dim %d"
					% [path, (w0[0] as Array).size(), feat_dim])
				return false
		g_enc = {}
		g_msg = []
		g_upd = []
		g_out = {}
		g_h = 0
		return layers.size() > 0

	# --- gnn ---------------------------------------------------------------
	# ★ 三件事都要查：① `gnn` 块存在（缺了 = 只导了一半）② 各层形状 ③ 层数自洽。
	#   任何一条漏掉，拿错权重进来都**不会报错**，只会算出看起来像分数的数。
	var gb: Variant = dd.get("gnn", null)
	if typeof(gb) != TYPE_DICTIONARY:
		push_error("[NNScore] 拒收 %s：arch=gnn 但缺 `gnn` 块（只导了一半的权重）" % path)
		return false
	var g: Dictionary = gb
	g_h = int(g.get("h", 0))
	var nl: int = int(g.get("n_layers", 0))
	if g_h <= 0 or nl <= 0:
		push_error("[NNScore] 拒收 %s：gnn.h=%d / n_layers=%d 非法" % [path, g_h, nl])
		return false
	g_enc = _pack_lin(g.get("enc", null), feat_dim, g_h)
	if g_enc.is_empty():
		push_error("[NNScore] 拒收 %s：gnn.enc 形状不符（应 %d→%d）" % [path, feat_dim, g_h])
		return false
	var mlist: Array = g.get("msg", [])
	var ulist: Array = g.get("upd", [])
	if mlist.size() != nl or ulist.size() != nl:
		push_error("[NNScore] 拒收 %s：msg/upd 层数 %d/%d ≠ n_layers %d"
			% [path, mlist.size(), ulist.size(), nl])
		return false
	g_msg = []
	g_upd = []
	for li in nl:
		var ml := _pack_lin(mlist[li], g_h, g_h)
		if ml.is_empty():
			push_error("[NNScore] 拒收 %s：msg[%d] 形状不符（应 %d→%d）" % [path, li, g_h, g_h])
			return false
		var ul := _pack_lin(ulist[li], 2 * g_h, g_h)
		if ul.is_empty():
			push_error("[NNScore] 拒收 %s：upd[%d] 形状不符（应 %d→%d）"
				% [path, li, 2 * g_h, g_h])
			return false
		g_msg.append(ml)
		g_upd.append(ul)
	g_out = _pack_lin(g.get("out", null), g_h, 1)
	if g_out.is_empty():
		push_error("[NNScore] 拒收 %s：gnn.out 形状不符（应 %d→1）" % [path, g_h])
		return false
	layers = []
	return true


## 把 json 里的 {W:Array[Array], b:Array} 打成 {W:Array[PackedFloat32Array], b:PackedFloat32Array}。
## 形状不对返回空字典（**不许**"能塞就塞"，那是静默算错的入口）。
func _pack_lin(d: Variant, nin: int, nout: int) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var dd: Dictionary = d
	var W: Array = dd.get("W", [])
	var b: Array = dd.get("b", [])
	if W.size() != nout or b.size() != nout:
		return {}
	var pw: Array = []
	pw.resize(nout)
	for i in nout:
		var row: Array = W[i]
		if row.size() != nin:
			return {}
		var pr := PackedFloat32Array()
		pr.resize(nin)
		for j in nin:
			pr[j] = float(row[j])
		pw[i] = pr
	var pb := PackedFloat32Array()
	pb.resize(nout)
	for i in nout:
		pb[i] = float(b[i])
	return {"W": pw, "b": pb}


## 全盘连通块预处理 —— **两侧必须同源**（训练侧 `nn_data.py::_group_info` 是同一算法）。
##
## 返回 `[gid, gsize, glibs, gpts]`：
##   gid     PackedInt32Array，非空点所属块编号；空点 = -1
##   gsize   Array[int]，该块子数
##   glibs   Array[Dictionary]，该块的**气点集合**（点 → true）
##   gpts    Array[Array]，该块的**成员点列表**
##
## ★ 颜色直接从盘面读（`board` 里的值就是 0/1/2）⇒ 不需要传 own/opp。
## ★ 为什么预处理：`_struct_vals()` 要对每个候选点算"落子后"的组/气，
##   逐点重跑 BFS 会变成 O(候选 × 块大小)。这里一次 O(n+E) 扫完，后面每点只做集合合并。
func _group_info(board: Dictionary) -> Array:
	var gid := PackedInt32Array()
	gid.resize(n)
	gid.fill(-1)
	var gsize: Array = []
	var glibs: Array = []
	var gpts: Array = []
	for v0 in n:
		if gid[v0] != -1:
			continue
		var c: int = int(board.get(v0, EMPTY))
		if c == EMPTY:
			continue
		var gi: int = gsize.size()
		gid[v0] = gi
		var stack: Array = [v0]
		var pts: Array = []
		var libs := {}
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			pts.append(cur)
			for u in adj[cur]:
				var s: int = int(board.get(u, EMPTY))
				if s == EMPTY:
					libs[u] = true
				elif s == c and gid[u] == -1:
					gid[u] = gi
					stack.append(u)
		gsize.append(pts.size())
		glibs.append(libs)
		gpts.append(pts)
	return [gid, gsize, glibs, gpts]


## "假设我在 v 落子"之后，新组的气数 —— **只在提子时走**（少见，约 5% 候选）。
##
## ★★ 为什么要这条精确路径：快路径把"己方块的气 ∪ v 的空邻居"当新组的气，
##   但**提掉的对方子腾出来的点也是气**。不补这一步的后果不是"略有偏差"，而是
##   **正好错在最关键的着法上**：一手既能提子又能救自己（倒扑 / 接不归 / 打劫）时，
##   快路径算出 lib_after = 0~1 ⇒ `self_atari=1`（标成送吃）+ `atari_saved=0`（标成没救活）
##   ⇒ 网络学到的是"最好的手是送死"。这类点占比小，但棋力主要就压在这些点上。
##   做法：真把子摆上去、把被提的点清空，再跑一次 `_group_info()` 读新组的气数。
func _sim_lib_after(board: Dictionary, v: int, own_c: int, cap_pts: Array) -> int:
	var b2 := board.duplicate()
	b2[v] = own_c
	for p in cap_pts:
		b2[p] = EMPTY
	var gi: Array = _group_info(b2)
	var gid2: PackedInt32Array = gi[0]
	var glibs2: Array = gi[2]
	var gv: int = gid2[v]
	if gv < 0:
		return 0
	return (glibs2[gv] as Dictionary).size()


## v 上"如果落子"的 7 个结构量（未归一化，`self_atari` 由 `_feat_at()` 补）。
## 与 `nn_data.py::_struct_feats()` **必须逐位一致**，口径见那边的 docstring：
##   · `cap_gain`：相邻对方块**唯一的气就是 v** ⇒ 落 v 后整块被提。
##   · `atari_saved`：相邻己方块唯一气是 v，且落子后整组气数 ≥ 2（1 气只算延命）。
##   · `opp_min_lib`：相邻对方块落子后的气数；没有相邻对方块时取满值 8（= 无威胁）。
func _struct_vals(board: Dictionary, v: int, own_c: int, opp_c: int, grp: Array) -> Array:
	var gid: PackedInt32Array = grp[0]
	var gsize: Array = grp[1]
	var glibs: Array = grp[2]
	var gpts: Array = grp[3]
	var dv: float = float(deg[v]) if deg[v] > 0 else 1.0
	var own_groups: Array = []
	var opp_groups: Array = []
	var nb: Array = adj[v]
	for u in nb:
		var s: int = int(board.get(u, EMPTY))
		if s == own_c:
			var gu: int = gid[u]
			if not own_groups.has(gu):
				own_groups.append(gu)
		elif s == opp_c:
			var go: int = gid[u]
			if not opp_groups.has(go):
				opp_groups.append(go)
	# 1-hop 同色邻居**之间**的连边数（拓扑形状：抱团 vs 分散）
	var own_link := 0
	var opp_link := 0
	var nd: int = nb.size()
	for i in nd:
		var u2: int = nb[i]
		var su: int = int(board.get(u2, EMPTY))
		if su == EMPTY:
			continue
		var nu: Array = adj[u2]
		for j in range(i + 1, nd):
			var w: int = nb[j]
			if int(board.get(w, EMPTY)) != su:
				continue
			if nu.has(w):
				if su == own_c:
					own_link += 1
				else:
					opp_link += 1
	# 落子后己方新组：v + 相邻己方块合并
	var size_after := 1
	var libs := {}
	for u3 in nb:
		if int(board.get(u3, EMPTY)) == EMPTY:
			libs[u3] = true
	for gg1 in own_groups:
		size_after += int(gsize[gg1])
		for p in (glibs[gg1] as Dictionary).keys():
			libs[p] = true
	libs.erase(v)                     # v 落子后不再是空点
	var lib_after: int = libs.size()
	# 提子（必须在 lib_after 之前算：提子会改气，见 `_sim_lib_after()`）
	var cap_gain := 0
	var cap_pts: Array = []
	for go1 in opp_groups:
		var lo: Dictionary = glibs[go1]
		if lo.size() == 1 and lo.has(v):
			cap_gain += int(gsize[go1])
			cap_pts.append_array(gpts[go1])
	if cap_gain > 0:
		lib_after = _sim_lib_after(board, v, own_c, cap_pts)
	# 救子
	var atari_saved := 0
	if lib_after >= 2:
		for gg2 in own_groups:
			if (glibs[gg2] as Dictionary).size() == 1:
				atari_saved += int(gsize[gg2])
	# 相邻对方块的最小气数（落子后）
	var opp_min := 8
	if not opp_groups.is_empty():
		for go2 in opp_groups:
			var lo2: Dictionary = glibs[go2]
			var l2: int = lo2.size() - (1 if lo2.has(v) else 0)
			if l2 < opp_min:
				opp_min = l2
		if opp_min < 0:
			opp_min = 0
	return [lib_after, size_after, cap_gain, atari_saved, opp_min,
		float(own_link) / dv, float(opp_link) / dv]


## 单点特征 —— **唯一真源**。`score_points()` 与 `check_golden()` 都调它。
##
## `version` 决定口径：1 ⇒ 17 维（v1 老权重）；2 ⇒ 25 维（追加 8 维结构特征）。
## `grp` 是 `_group_info()` 的产物，**整盘算一次**后传进来；version 1 传空数组。
## ★ 两个参数都**不给缺省值**：缺省值会让"忘了传"变成静默走错口径（§121 哑刀形态）。
func _feat_at(v: int, board: Dictionary, own_c: int, opp_c: int,
		d_own: PackedInt32Array, d_opp: PackedInt32Array,
		g: PackedFloat32Array, version: int, grp: Array) -> PackedFloat32Array:
	var dv: float = float(deg[v]) if deg[v] > 0 else 1.0
	var own1 := 0
	var opp1 := 0
	var emp1 := 0
	for u in adj[v]:
		var s: int = int(board.get(u, EMPTY))
		if s == own_c:
			own1 += 1
		elif s == opp_c:
			opp1 += 1
		else:
			emp1 += 1
	var own2 := 0
	var opp2 := 0
	var emp2 := 0
	for u in ring2[v]:
		var s2: int = int(board.get(u, EMPTY))
		if s2 == own_c:
			own2 += 1
		elif s2 == opp_c:
			opp2 += 1
		else:
			emp2 += 1
	# ★ 长度只由 version 决定（不从 feat_dim 推）—— 一处真源，免得两个变量各算一遍
	var dim: int = FEAT_DIM_V1 if version < 2 else FEAT_DIM_V2
	var x := PackedFloat32Array()
	x.resize(dim)
	x[0] = float(deg[v]) / n_deg_div
	x[1] = float(own1) / dv
	x[2] = float(opp1) / dv
	x[3] = float(emp1) / dv
	x[4] = minf(float(d_own[v]), n_dmax) / n_dmax
	x[5] = minf(float(d_opp[v]), n_dmax) / n_dmax
	x[6] = minf(float(d_rim[v]), n_dmax) / n_dmax
	x[7] = float(own2) / n_ring2_div
	x[8] = float(opp2) / n_ring2_div
	x[9] = float(emp2) / n_ring2_div
	for i in 6:
		x[10 + i] = g[i]
	x[16] = 1.0
	if dim > FEAT_DIM_V1:
		var sv: Array = _struct_vals(board, v, own_c, opp_c, grp)
		var lb: int = int(sv[0])
		x[17] = minf(float(lb), n_lib_div) / n_lib_div
		x[18] = minf(float(int(sv[1])), n_size_div) / n_size_div
		x[19] = minf(float(int(sv[2])), n_cap_div) / n_cap_div
		x[20] = minf(float(int(sv[3])), n_save_div) / n_save_div
		x[21] = minf(float(int(sv[4])), n_opplib_div) / n_opplib_div
		x[22] = float(sv[5])
		x[23] = float(sv[6])
		x[24] = 1.0 if lb <= 1 else 0.0
	return x


## 全局量（6 维）。与盘面只通过子数差相关 ⇒ 每局面算一次。
func _global_vec(board: Dictionary, color: int, ply: int) -> PackedFloat32Array:
	var own_c := color
	var opp_c := 3 - color
	var own_st := 0
	var opp_st := 0
	for v in n:
		var x: int = int(board.get(v, EMPTY))
		if x == own_c:
			own_st += 1
		elif x == opp_c:
			opp_st += 1
	var g := PackedFloat32Array()
	g.resize(6)
	g[0] = minf(float(ply), n_ply_div) / n_ply_div
	g[1] = float(own_st - opp_st) / float(maxi(n, 1))
	g[2] = 1.0 if color == 1 else 0.0
	g[3] = n_komi / n_komi_div
	g[4] = deg_mean / n_deg_div
	g[5] = float(n) / n_n_div
	return g


## 整盘特征阶段 —— **唯一出口**。返回 `[pts: PackedInt32Array, X: Array[PackedFloat32Array]]`
## （只含候选点 = 空点且不是劫点，顺序 = 格点 id 升序）。
##
## ★ 为什么抽成独立函数：`score_points()` 与 `--yematest` 的 ⑦b 耗时对照**都调它**
##   ⇒ "`_group_info()` 是整盘一次还是逐点一次"这件事落在**被测代码里**。
##   早先 ⑦b 自己写了一遍"先算 grp 再逐点"的循环 ⇒ 把 `score_points` 里的 `_group_info`
##   挪进逐点循环它照样全绿（§70：判据不许自己重写一遍被测逻辑）。
## ★ `grp` 必须在循环**外**算：整盘一次 O(n+E)，挪进去就是 O(n×(n+E))，功能完全正确、
##   golden 对拍照样 0 条不一致，只是慢约 120 倍 ⇒ 只有 ⑦b 的比值判据能咬住它。
func compute_feats(board: Dictionary, color: int, ply: int, ko: int, version: int) -> Array:
	var own_c := color
	var opp_c := 3 - color
	var d_own := _dist_from_stones(board, own_c)
	var d_opp := _dist_from_stones(board, opp_c)
	var g := _global_vec(board, color, ply)
	var grp: Array = []
	if version >= 2:
		grp = _group_info(board)
	var pts := PackedInt32Array()
	var X: Array = []
	for v in n:
		if int(board.get(v, EMPTY)) != EMPTY or v == ko:
			continue
		pts.append(v)
		X.append(_feat_at(v, board, own_c, opp_c, d_own, d_opp, g, version, grp))
	return [pts, X]


## 全盘评分：返回长度 n 的数组，**非候选点填 -1e9**（调用方按 > -1e8 过滤）。
func score_points(board: Dictionary, color: int, ply: int, ko: int) -> PackedFloat32Array:
	var fr: Array = compute_feats(board, color, ply, ko, feat_version)
	var pts: PackedInt32Array = fr[0]
	var X: Array = fr[1]
	# ★ 两种结构的分叉点只有这一处：mlp 是**逐点独立**前向，gnn 必须**整盘一起**算
	#   （邻接聚合要看到别的候选点的隐状态）。特征阶段两者共用，所以"特征对拍"通不
	#   代表"前向通" —— 前向另有 golden 的 `scores` 字段对拍。
	if arch == "gnn":
		var t0 := Time.get_ticks_usec()
		var sg := _score_points_graph(pts, X)
		last_graph_ms = int((Time.get_ticks_usec() - t0) / 1000)
		return sg
	return _scores_mlp(pts, X)


## 图网络前向（与 `nn_train.PointGNN.forward` 逐位对齐）。
##
## 结构（h = 隐宽，L = 层数）：
##   h⁰   = relu(enc·x)
##   每层: agg = (Σ_{u∈adj[v]} msg·h[u]) / deg
##         h  = relu(upd·[h ; agg])
##   输出: out·h
##
## ★ 三处必须与 Python 完全一致，任何一处不同都**不会报错**，只会让分数悄悄偏掉：
##   1. **邻域里的点不在候选集时，Python 加的是自环**（`src=dst=iv`），deg 也照算 1。
##      照抄，不许"跳过不在候选集的邻居" —— 那会让 deg 变小、agg 变大。
##   2. **deg 不是图论度数**，而是"该候选的 adj 长度"（= `t.deg`），且 `clamp(min=1)`。
##   3. **聚合顺序**：先按目标候选 i，再按 `adj[v]` 的顺序累加。浮点加法不结合，
##      换顺序会差最后几位 —— golden 的容差按 1e-5 判，所以顺序也要照抄。
## ★ 性能：`msg` 层对每个**节点**算一次（而不是每条边算一次）—— 数学上完全等价
##   （m(h[src]) 只依赖 src），但把 `边数 × h²` 降到 `节点数 × h²`。
func _score_points_graph(pts: PackedInt32Array, X: Array) -> PackedFloat32Array:
	var k := pts.size()
	var hdim := g_h
	var idx := {}
	for i in k:
		idx[pts[i]] = i
	# ① h⁰ = relu(enc·x)
	var H: Array = []
	H.resize(k)
	for i in k:
		H[i] = _dense_relu(X[i], g_enc)
	# ② 逐层消息传递
	for li in g_msg.size():
		var MH: Array = []
		MH.resize(k)
		for i in k:
			MH[i] = _dense(H[i], g_msg[li])
		var AGG: Array = []
		AGG.resize(k)
		for i in k:
			var acc := PackedFloat32Array()
			acc.resize(hdim)
			var v: int = pts[i]
			var cnt := 0
			for u in adj[v]:
				var j: int = int(idx.get(u, -1))
				var sv: PackedFloat32Array = MH[i] if j < 0 else MH[j]
				for t in hdim:
					acc[t] += sv[t]
				cnt += 1
			var inv := 1.0 / float(maxi(cnt, 1))
			for t in hdim:
				acc[t] *= inv
			AGG[i] = acc
		var upd: Dictionary = g_upd[li]
		for i in k:
			var cat := PackedFloat32Array()
			cat.resize(2 * hdim)
			var hi: PackedFloat32Array = H[i]
			var ai: PackedFloat32Array = AGG[i]
			for t in hdim:
				cat[t] = hi[t]
				cat[hdim + t] = ai[t]
			H[i] = _dense_relu(cat, upd)
	# ③ 输出层（无激活）
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(-1.0e9)
	for i in k:
		out[pts[i]] = _dense_scalar(H[i], g_out)
	return out


## y = max(W·x + b, 0)，W 已预打包成 PackedFloat32Array。
func _dense_relu(x: PackedFloat32Array, L: Dictionary) -> PackedFloat32Array:
	var y := _dense(x, L)
	for i in y.size():
		if y[i] < 0.0:
			y[i] = 0.0
	return y


## y = W·x + b（无激活）
func _dense(x: PackedFloat32Array, L: Dictionary) -> PackedFloat32Array:
	var W: Array = L["W"]
	var b: PackedFloat32Array = L["b"]
	var m: int = W.size()
	var k: int = x.size()
	var y := PackedFloat32Array()
	y.resize(m)
	for i in m:
		var row: PackedFloat32Array = W[i]
		var s: float = b[i]
		for j in k:
			s += row[j] * x[j]
		y[i] = s
	return y


func _dense_scalar(x: PackedFloat32Array, L: Dictionary) -> float:
	var W: Array = L["W"]
	var b: PackedFloat32Array = L["b"]
	var row: PackedFloat32Array = W[0]
	var k: int = x.size()
	var s: float = b[0]
	for j in k:
		s += row[j] * x[j]
	return s


func _forward(x: PackedFloat32Array) -> float:
	var cur := x
	var last: int = layers.size() - 1
	for li in layers.size():
		var L: Dictionary = layers[li]
		var W: Array = L["W"]
		var b: Array = L["b"]
		var m: int = W.size()
		var k: int = cur.size()
		var nxt := PackedFloat32Array()
		nxt.resize(m)
		for i in m:
			var row: Array = W[i]
			var s: float = float(b[i])
			for j in k:
				s += float(row[j]) * cur[j]
			nxt[i] = s if li == last else maxf(s, 0.0)
		cur = nxt
	return cur[0]


## 特征对拍（**接入前必跑一次**）：拿训练脚本导出的 `features_golden.json` 逐条复算。
##
## 返回：0 = 两边同源；> 0 = 不一致条数；-1 = 文件读不了；-2 = **有效分母 0**。
##
## ★ 口径由 **golden 自己声明的 `feat_version`** 决定，不读 `self.feat_version`。
##   这样"引擎加载的是 v1 权重、手上是 v2 golden"也能验 —— 否则两条分支里永远只有
##   线上权重那一条被测到，另一条坏不坏没人知道（§138 对照组）。
## ★ `state` 长度 = 本盘点数才比较；对不上的局面计入"跳过"，**跳到最后分母为 0 就报 -2**
##   而不是 0 —— 否则"盘型对不上"会安静地长得像"通过"（§106）。
## ★ golden 里带 state / pts / X ⇒ 不需要盘型几何，只要 `setup()` 过同一张盘。
func check_golden(path: String, tol: float = 1e-6, tol_fwd: float = 1e-5) -> int:
	golden_checked = 0
	forward_checked = 0
	var fwd_bad := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[NNScore] 打不开 %s" % path)
		return -1
	var txt := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("[NNScore] %s 不是合法 JSON" % path)
		return -1
	var dd: Dictionary = d
	var ver: int = int(dd.get("feat_version", 1))
	var items: Array = dd.get("items", [])
	var bad := 0
	var checked := 0
	var skipped := 0
	for it in items:
		var itd: Dictionary = it
		var st: String = str(itd.get("state", ""))
		if st.length() != n:
			skipped += 1
			continue                 # 这份 golden 是另一张盘导出的 ⇒ 跳过，不判红
		var bd: Dictionary = {}
		for v in n:
			bd[v] = int(st[v])
		var color: int = int(itd.get("color", 1))
		var own_c := color
		var opp_c := 3 - color
		var d_own := _dist_from_stones(bd, own_c)
		var d_opp := _dist_from_stones(bd, opp_c)
		var g := _global_vec(bd, color, int(itd.get("ply", 0)))
		var grp: Array = []
		if ver >= 2:
			grp = _group_info(bd)
		var pts: Array = itd.get("pts", [])
		var X: Array = itd.get("X", [])
		for i in mini(pts.size(), X.size()):
			var pv: int = int(pts[i])
			var have := _feat_at(pv, bd, own_c, opp_c, d_own, d_opp, g, ver, grp)
			var want: Array = X[i]
			if want.size() != have.size():
				bad += 1
				push_warning("[NNScore] 维数不符 gid=%s pts[%d]: golden %d 维 ≠ 本侧 %d 维（v%d 口径）"
					% [str(itd.get("gid", "?")), pv, want.size(), have.size(), ver])
				continue
			checked += 1
			for j in have.size():
				if absf(float(want[j]) - have[j]) > tol:
					bad += 1
					push_warning("[NNScore] 特征分叉 gid=%s pts[%d] dim%d(%s): py=%.8f gd=%.8f"
						% [str(itd.get("gid", "?")), pv, j,
							str(feat_names[j]) if j < feat_names.size() else "?",
							float(want[j]), have[j]])
					break
		# --- 前向对拍（2026-10-26 新增；golden 里带 `scores` 时才有）---
		# ★ 为什么必须单独对拍：特征对拍只能证明"喂进去的东西一样"，证明不了
		#   "算出来的分数一样"。图网络的前向多了一步邻接聚合，它写错时特征逐位相同、
		#   权重加载也不报错，只有分数悄悄偏掉 —— 那只会表现成"引擎好像没变强"。
		var want_s: Variant = itd.get("scores", null)
		if typeof(want_s) == TYPE_ARRAY:
			var wa: Array = want_s
			if wa.size() == pts.size() and pts.size() > 0:
				var pv2 := PackedInt32Array()
				pv2.resize(pts.size())
				for i in pts.size():
					pv2[i] = int(pts[i])
				var got: PackedFloat32Array
				if arch == "gnn":
					got = _score_points_graph(pv2, X)
				else:
					got = _scores_mlp(pv2, X)
				forward_checked += pts.size()
				for i in pts.size():
					var wv: float = float(wa[i])
					var gv: float = got[pv2[i]]
					if absf(gv - wv) > tol_fwd:
						fwd_bad += 1
						push_warning("[NNScore] 前向分叉 gid=%s pts[%d]: py=%.8f gd=%.8f"
							% [str(itd.get("gid", "?")), pv2[i], wv, gv])
						break
	golden_checked = checked
	print("[NNScore] 特征对拍 %s：口径 v%d · 检查 %d 点 · 跳过 %d 局面 · 不一致 %d 条"
		% ["✓" if bad == 0 and checked > 0 else "✗", ver, checked, skipped, bad])
	print("[NNScore] 前向对拍 %s：arch=%s · 检查 %d 点 · 不一致 %d 条%s"
		% ["✓" if fwd_bad == 0 and forward_checked > 0 else "✗", arch, forward_checked,
			fwd_bad, "" if forward_checked > 0 else "（golden 没带 scores ⇒ 本条无分辨力）"])
	if checked == 0:
		print("[NNScore] ✗ 有效分母 0：没有任何局面的点数与这张盘一致（%s）"
			% path + " ⇒ 本条没有分辨力，不能当通过")
		return -2
	return bad + fwd_bad


## mlp 的批量评分（供 `check_golden` 与 `score_points` 共用同一口径）。
func _scores_mlp(pts: PackedInt32Array, X: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(-1.0e9)
	for i in mini(pts.size(), X.size()):
		out[pts[i]] = _forward(X[i])
	return out
