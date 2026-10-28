class_name RulesKernel
extends RefCounted

# ====== 围棋规则内核（2026-10-18 自 game.gd 拆出）======
## 为什么拆：game.gd 2 万行巨石里，「棋理」是唯一与 UI / 联机 / AI 调度都不沾边的纯逻辑
## （气 / 连通块 / 提子 / 打劫 / superko / 落子合法性 / 数子），--rulestest / --hovertest /
## --xgtest 的判据全部押在它身上 ⇒ 单独成文件、单独可读、单独可测。
##
## ★ 拆分形态：**代码搬家，状态不搬**。
##   盘面（board / adjacency / tiles）、superko 指纹表（_superko_zob / _superko_hist）、
##   领地描边（_terr_mark）、贴目与提子计数（komi / black_prisoners / white_prisoners）
##   等**全部留在宿主 game.gd**（外部还有 rulestest 夹具 / place_stone / 悔棋回滚 /
##   联机中途加入 4 处直接引用），内核经 `host` 反读 ⇒ 一切跨文件状态天然同源，
##   不存在「两份状态漂移」的问题。
## ★ 宿主里保留同名薄委托（get_neighbors / get_group / ... / _compute_scores），
##   全部调用点（AI / hover 预览 / 自检夹具 / place_stone）零改动。
## ★ `enum Stone` 与 game_clock.gd / record.gd 一样**各写一份**（真源 = game.gd:95），
##   索引契约 EMPTY=0 / BLACK=1 / WHITE=2 由 --clocktest ⓪ 对账。

## 宿主 game.gd 节点（状态真源）。
## ★ 名字刻意避开 `g` / `h`：被搬函数体里有同名局部变量（`for g in get_group(...)`、
##   `var h := 0`），用短名会被遮蔽成静默 bug。
var host

## ★ 与 game.gd 的 `enum Stone { EMPTY, BLACK, WHITE }` **各写一份**
##   （同 record.gd / game_clock.gd 惯例）。索引是黑白契约：--clocktest ⓪ 对账。
enum Stone { EMPTY, BLACK, WHITE }

# ====== 围棋逻辑（气 / 连通块 / 提子）======
## 2026-10-18 自 game.gd 原样迁入（成员访问加 `host.` 前缀，正文与注释逐字未动）。

func get_neighbors(tile_id: int) -> Array:
	return host.adjacency[tile_id]

func get_group(tile_id: int) -> Array[int]:
	var color: int = host.board[tile_id]
	if color == Stone.EMPTY:
		return []
	var visited: Array[int] = []
	var queue: Array[int] = [tile_id]
	visited.append(tile_id)
	while queue.size() > 0:
		var cur: int = queue.pop_front()
		for n in get_neighbors(cur):
			if host.board[n] == color and not visited.has(n):
				visited.append(n)
				queue.append(n)
	return visited

func get_liberties(group: Array[int]) -> int:
	var liberties: int = 0
	var liberty_positions: Array[int] = []
	for vid in group:
		for n in get_neighbors(vid):
			if host.board[n] == Stone.EMPTY and not liberty_positions.has(n):
				liberties += 1
				liberty_positions.append(n)
	return liberties

func remove_group(group: Array[int]) -> void:
	for vid in group:
		host.board[vid] = Stone.EMPTY

## 提掉 color 方所有无气棋块，返回**每一颗**被提子的 id（不含重复）。
##
## 曾经的 bug：先在 `stones` 里收集全部该色子，再逐个 `get_group` 判气，
## 但 `remove_group` 直到循环结束后才执行 → 同一串会被它的每一颗子各扫一遍，
## 于是同一串被反复 append 进 `removed_ids`，长度变成「串内子数²」。
## 实战表现：一手提掉 11 子的大龙时打印「提掉 121 子」，
## 提子数被放大数倍 → 终局比分会算出远超棋盘总点数的荒谬值（曾出现 988 目）。
## 修法：① 用 `seen` 记住已处理过的串，② 判定即提，让后续同名子立刻变成空点。
func remove_dead_stones(color: int) -> Array[int]:
	var removed_ids: Array[int] = []
	var stones: Array[int] = []
	for vid in host.board.keys():
		if host.board[vid] == color:
			stones.append(vid)
	var seen: Dictionary = {}
	for vid in stones:
		if host.board[vid] != color or seen.has(vid):
			continue
		var group: Array[int] = get_group(vid)
		for g in group:
			seen[g] = true
		if get_liberties(group) == 0:
			for g in group:
				removed_ids.append(g)
			remove_group(group)
	return removed_ids

# ====== superko（positional，2026-10-14，研报 §3 的规则补课）======
## ★ 口径与设计档案的真源在宿主 game.gd 的「====== superko ======」章节头
##   （positional 口径 / _quiet_place 守卫 / 同种子同生成式，以及状态变量
##   `_superko_zob` / `_superko_hist` 的声明都留在那边）。
##   2026-10-18 函数体原样迁入，成员访问加 `host.` 前缀。

## ★ **同种子同生成式**（与镜像 `_xg_reset()` 同一套种子）⇒ 同盘得同一张指纹表，
##   `--xgtest` 的两套 hash 可逐位对拍。种子值 2026-10-14 定版，**不许再改**——
##   改了等于换指纹表，历史对拍基线全部作废。
const SUPERKO_SEED: int = 20261014

## 与镜像 `_xg_rand64()` **同式**（Godot 4 int 是 64 位有符号，避开符号位）。
func _superko_rand64(rng: RandomNumberGenerator) -> int:
	return ((rng.randi() & 0x7FFFFFFF) << 32) | (rng.randi() & 0xFFFFFFFF)

## 只**建表**：按当前 `tiles` 重建 `_superko_zob`（不碰历史）。
## 抽出来是因为"表失配"与"开新局"要做的**后半件事不同** —— 前者**不许**入档当前局面
## （会与外层"落子后查重"自锁，见 `_superko_hash()` 守卫的注释）。
func _superko_rebuild_table() -> void:
	host._superko_zob.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SUPERKO_SEED
	for i in host.tiles.size():
		host._superko_zob[i] = [0, _superko_rand64(rng), _superko_rand64(rng)]

## 开新局：建表 + 清历史 + 把**当前局面**作为第一个局面入档。
## `reset_game()` 每局调一次（新局 = 新历史），此刻 `board` 已清空 ⇒ 首个局面 = 空盘。
func _superko_init() -> void:
	_superko_rebuild_table()
	host._superko_hist.clear()
	host._superko_hist[_superko_hash()] = true

## 从 `board` 重算局面指纹（只读盘面；**仅**在指纹表与盘失配时重建一次，见下）。
## ★★ 尺寸守卫（2026-10-14 `--hatdead` 逮到的越界）：
##   `_superko_zob` 是**按盘建**的表（下标 0..`tiles.size()-1`），而换盘路径未必经过
##   `reset_game()` —— 实测 `--hatdead` 直接调 `generate_hat()` 换成帽子盘（140+ 格），
##   表却还留在标准盘那 120 项 ⇒ `_superko_zob[121]` 取到 nil、`(nil as Array)[c]` 抛
##   `Out of bounds get index '121'`；**抛错后本函数返回残值 0，而 0 恰是空盘指纹**
##   （`_superko_init()` 第一件事就是把空盘入档）⇒ `place_stone()` 判「超级劫」
##   ⇒ **拒绝一切落子**（症状是"点了没反应"，比崩溃更难查）。
##   ⇒ 尺寸不匹配就当场重建—— ★★ 且**只重建表 + 清历史，绝不入档当前局面**：
##     本函数的调用点之一是"落子后查重"`_superko_hist.has(_superko_hash())`，
##     若顺带把当前局面入档，那条**正是**外层待查的那条 ⇒ 必然同形 ⇒ 拒绝一切落子
##     （2026-10-14 `--hatdead` 修第一版后**实测坐实**：SCRIPT ERROR 没了，但落子仍被拒）。
##     清历史是因为旧盘的局面与本次判定**不同源**（跨盘 hash 无意义，留着只有巧合误拦）；
##     清空后历史从"本手落定"开始，由 `_superko_commit()` 接手。
##   ★ 守卫修在**读取点**而不是"生成盘之后重建"：生成器有 7 个且**各可直调**
##     （`generate_penrose()` 实测 8 个直接调用点）⇒ 挂收尾要写 7 处、漏一处就静默脏点；
##     而本函数是**所有**指纹读取的必经点（`_superko_blocks` / `_superko_commit` /
##     `_superko_hash_after` 都从它开始）⇒ 一处覆盖全部路径。
##   ⚠️ 这是**防崩溃兜底**，不是"表内容必然对得上"的保证：同格数的两张不同盘尺寸相同 ⇒
##     这里看不出来。换盘路径仍应走 `reset_game()`（它在清盘后重建）。
##   ⚠️ 自愈会 `clear()` 历史 ⇒ 新盘的历史从"当前局面"重新开始（换盘场景正是要这个）。
##     递归安全：`_superko_init()` 末尾才调本函数，那时表已按新盘填满 ⇒ 不再触发。
func _superko_hash() -> int:
	if host._superko_zob.size() != host.tiles.size():
		# ★★ 只重建表 + 清历史，**不入档当前局面**（否则与本函数外层的"落子后查重"自锁）。
		_superko_rebuild_table()
		host._superko_hist.clear()
	var h := 0
	for i in host.tiles.size():
		var c: int = int(host.board.get(i, Stone.EMPTY))
		if c == Stone.EMPTY:
			continue
		h ^= int((host._superko_zob[i] as Array)[c])
	return h

## ★把刚落下的这手记入历史。内部自守 `_quiet_place`（探测性落子不入历史，同上口径）。
## ★★ 2026-10-27：静音门与「是否执行超级劫」**必须解耦**（`game._superko_enforce`）。
##   原来这里写死 `if host._quiet_place: return` ⇒ 静音语境下**历史表根本不被写入**，
##   于是 `game.place_stone()` 那个 superko 关口即使打开也查不到任何东西
##   （历史里永远只有初始局面）⇒ 表现为「打开了超级劫却一次都不触发」。
##   ⇒ 判据：只把 `_superko_enforce` 置真而不同时改本处，实验读出来的是空操作（§138 同族）。
func _superko_commit() -> void:
	if host._quiet_place and not host._superko_enforce:
		return
	host._superko_hist[_superko_hash()] = true

## 「在 `tile_id` 落 `color`」之后的局面指纹（**只读预测**，供 `can_place_at()` 用）。
## 提子判定与 `can_place_at()` ③ 同源（邻居敌串除本点外无气 ⇒ 该串被提），
## 依据：合法局面下远处的串不可能因这一手新死（同 `_xg_occ_play()` 的注释）。
func _superko_hash_after(tile_id: int, color: int) -> int:
	var h: int = _superko_hash() ^ int((host._superko_zob[tile_id] as Array)[color])
	var opp: int = Stone.WHITE if color == Stone.BLACK else Stone.BLACK
	var seen := {}
	for n in host.adjacency[tile_id]:
		if host.board[n] != opp or seen.has(n):
			continue
		if _libs_of_group_excluding(n, tile_id) == 0:
			for g in get_group(n):
				seen[g] = true
				h ^= int((host._superko_zob[g] as Array)[opp])
	return h

## 同形再现 → 禁着。**供 `can_place_at()`（只读预览）用**：它不能真落子，只能预测。
## ⚠️ `place_stone()` 走的是**实测式**（盘面已定稿 ⇒ 直接 `_superko_hash()` 查表），
##   与本函数是"同一判据的两种访问方式"，不是两份实现。
##   两者的一致性**不能用 `--hovertest` 覆盖** —— 那条穷举对照跑在 `_quiet_place = true` 下，
##   而 superko 在该语境被守卫关掉 ⇒ 必须由 `--rulestest` 的 superko 专项判据单独钉死
##   （夹具法：把"落子后指纹"直接塞进历史，再对拍两个函数都必须拒）。
func _superko_blocks(tile_id: int, color: int) -> bool:
	if host._quiet_place and not host._superko_enforce:
		return false
	return host._superko_hist.has(_superko_hash_after(tile_id, color))

## 这一手**棋理上是否可下**（空点 + 非劫点 + 不是自杀）—— ★ **只读、无副作用**，
## 供 `_draw_hover_preview()` 用（每帧都要问，不能真去 `place_stone` 试一手再回滚）。
##
## ★★ 真源纪律：判据必须与 `place_stone()` 逐位一致，否则会从「预览说有戏、点下去没反应」
##    翻转成反向的「明明能下、预览却不亮」。二者的一致性由 `--hovertest` ④ **穷举对照**
##    钉死（对每个空点同时跑本函数与真 `place_stone`，逐格比结果），改任一边都会立刻变红。
##
## 判定（把「落子后本方串还有没有气」拆成三条充分条件，任一成立即可下）：
##   ① 邻居里有空点 → 落下后自己就有气；
##   ② 邻居里有**同色串、且该串除这一点外还有别的气** → 连上去就有气；
##      （注意不能只看「有同色邻居」——单气串被自己堵上最后一口气照样是自杀）
##   ③ 邻居里有**敌方串、且该串除这一点外已无气** → 提子腾出的点就是自己的气（含打劫提）。
func can_place_at(tile_id: int, color: int = -1) -> bool:
	if tile_id < 0 or tile_id >= host.tiles.size():
		return false
	if host.board.get(tile_id, Stone.EMPTY) != Stone.EMPTY:
		return false
	if tile_id == host.ko_point:
		return false        # 打劫禁着（与 place_stone 同一条）
	var c: int = host.current_player if color < 0 else color
	var opp: int = Stone.WHITE if c == Stone.BLACK else Stone.BLACK
	# ★ superko 前置检查（同形再现 ⇒ 禁着）。放在 ①②③ **之前**是故意的：
	#   superko 与那三条是**与**关系（棋理上可下 **且** 历史上没出现过），先后无关；
	#   而循环末尾那个 `return false` 是"①②③ 都不成立"的**不可下**分支 ——
	#   加在那儿等于没加（结果本来就是 false），这是写这条时差点踩进去的错。
	#   放前面还有个好处：`_quiet_place` 时本函数第一行就返回 false ⇒ 穷举对照零成本。
	if _superko_blocks(tile_id, c):
		return false
	for n in host.adjacency[tile_id]:
		var v: int = host.board[n]
		if v == Stone.EMPTY:
			return true
		if v == c:
			if _libs_of_group_excluding(n, tile_id) > 0:
				return true
		else:
			if _libs_of_group_excluding(n, tile_id) == 0:
				return true
	return false

## 某子所在串的**气数**，但把 `exclude` 这个点当作已被占掉（＝我们正打算落在那里）。
## 用途就是 `can_place_at()` 的 ②③：问「(若我占了 exclude) 这串还有没有气」。
func _libs_of_group_excluding(stone_id: int, exclude: int) -> int:
	var seen: Dictionary = {}
	var n := 0
	for g in get_group(stone_id):
		for m in host.adjacency[g]:
			if m == exclude or seen.has(m):
				continue
			if host.board[m] == Stone.EMPTY:
				seen[m] = true
				n += 1
	return n

# ====== 数子判定（简单面积法，纯逻辑计分）======
## 2026-10-18 自 game.gd 原样迁入（成员访问加 `host.` 前缀）。
## 领地描边 `_terr_mark` 留在宿主（绘制层要读），本函数经 `host` 写入。

## 纯逻辑计分（无 UI 依赖，便于脚本单测）：
## 空区 flood fill —— 边界只邻接黑棋 → 黑领地；只邻接白棋 → 白领地；双色接触 → 无主。
## 总分 = 盘面子数 + 领地 + 提子（白方总分另加贴目 komi）
func _compute_scores() -> Dictionary:
	var terr_b := 0
	var terr_w := 0
	host._terr_mark.clear()
	var seen: Dictionary = {}
	for i in range(host.tiles.size()):
		if host.board[i] != Stone.EMPTY or seen.has(i):
			continue
		var region: Array[int] = [i]
		seen[i] = true
		var qi := 0
		var touch_b := false
		var touch_w := false
		while qi < region.size():
			var cur: int = region[qi]
			qi += 1
			for nb in host.adjacency[cur]:
				var st: int = host.board[nb]
				if st == Stone.EMPTY:
					if not seen.has(nb):
						seen[nb] = true
						region.append(nb)
				elif st == Stone.BLACK:
					touch_b = true
				else:
					touch_w = true
		if touch_b and not touch_w:
			terr_b += region.size()
			for tid in region:
				host._terr_mark[tid] = Stone.BLACK
		elif touch_w and not touch_b:
			terr_w += region.size()
			for tid in region:
				host._terr_mark[tid] = Stone.WHITE
		# 双色接触的空区：无主，双方都不计

	var stones_b := 0
	var stones_w := 0
	for i in range(host.tiles.size()):
		if host.board[i] == Stone.BLACK:
			stones_b += 1
		elif host.board[i] == Stone.WHITE:
			stones_w += 1

	return {
		"stones_black": stones_b, "stones_white": stones_w,
		"territory_black": terr_b, "territory_white": terr_w,
		"total_black": stones_b + terr_b + host.black_prisoners,
		"total_white": stones_w + terr_w + host.white_prisoners + host.komi,
	}
