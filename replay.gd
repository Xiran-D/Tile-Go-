## 复盘器状态机（棋谱阶段②）。
##
## ★★ 为什么是**独立脚本**而不是 game.gd 里的一个模式开关：
##   复盘要反复"清盘 → 从第 0 手顺序重放到第 k 手"，而 game.gd 的对局状态有二十多个成员
##   （board / ko_point / current_player / passes / _hist / _record / 提子数 / 悔棋栈 / 额度…）。
##   在 game.gd 里加一个 `_replay_mode` 开关，**每个状态字段都要判"复盘时该不该动"** ——
##   漏判一个的症状极其隐蔽（"复盘完开新局看到旧手数"、"悔棋额度被复盘吃掉"），
##   而且是**静默**的。所以状态全部收进本文件，game.gd 只在三个地方让路：
##     ① `_replay_active` ⇒ 阻断 AI / 联机 / 悔棋 / 终局记账
##     ② `_replay_anim_gate` ⇒ 阻断落子/提子动画（否则拖滑条时满屏砖块乱飞）
##     ③ 复盘构造盘面时 `_quiet_place = true` ⇒ 探测性落子不入 `_hist`（阶段① ③ 的同一条闸）
##
## ★ 盘面重建**必须走 game.gd 的真实路径**（`generate_board()` / `place_stone()` / `_apply_pass()`），
##   不能"照着谱面摆" ⇒ 否则复盘成了绕过规则的后门（能摆出这局里根本下不出来的局面）。
##   —— 与 `--replaytest` ② / `--grecotest` ⑤ 同一条纪律。
class_name GameReplay
extends RefCounted

## 复盘到第几手。0 = 空盘（还没落任何一手），n = 谱有 n 手且已全部重放。
var replay_ply: int = 0
## 正在连续播放中（空格暂停会把它置假）
var replay_playing: bool = false
## 播放的**余量累积**（手）。不足一手的部分留到下一帧 ⇒ 慢速也能走起来，
## 且**平均速率精确等于** plays_per_sec（不累积就会每帧扔掉小数 ⇒ 系统性偏慢）。
var replay_frac: float = 0.0
## 当前这份谱（`GameRecord.load_by_id()` / `load_from()` 的返回值）
var replay_record: Dictionary = {}

## 每次成功换到新一手就发这个。带参数是为了让 UI 不用回头查状态。
signal replay_ply_changed(ply: int)
## 播放到末手（或用户按播放时已在末手）⇒ 发这个，UI 用来自动停。
signal replay_finished()

## 谱的总手数。空谱返回 0。
func replay_total() -> int:
	if replay_record.is_empty():
		return 0
	return (replay_record["moves"] as Array).size()

## 当前手的展示信息（信息栏用）。空盘/越界返回空字典。
##
## ★ `ko` 是**本手之后**的劫点（阶段① 的口径，与 `_hist` 的 `ko_before` 相反）。
##   想答"落这手时是不是在劫争中"，要读**下一手的 `ko`** 或盘面 `ko_point`，
##   别把本手的 `ko` 当成"落子前被拦" —— 那会把"这手制造了劫"误报成"这手被劫拦了"。
func replay_info() -> Dictionary:
	if replay_ply <= 0 or replay_ply > replay_total():
		return {}
	var mv: Dictionary = (replay_record["moves"] as Array)[replay_ply - 1]
	var in_ko: bool = replay_ply < replay_total() \
		and int((replay_record["moves"] as Array)[replay_ply]["ko"]) >= 0
	return {
		"ply": replay_ply,
		"total": replay_total(),
		"color": str(mv["color"]),
		"captures": int(mv["captures"]),
		"ko_after": int(mv["ko"]),
		"in_ko": in_ko,
		"is_pass": int(mv["tile"]) < 0,
	}

## 跳到第 ply 手。**顺序重放**，不保存任何局面快照 ——
##
## ★ 为什么顺序重放而不是随机跳转：200 手的重放是毫秒级（`--replaytest` ② 已测过），
##   顺序重放简单且**绝不会分叉**（没有"从任意局面往下走"的组合爆炸）。
## ★ 为什么**不存快照**：存 `board` 的引用会踩别名坑（跳走后原局面被改坏），
##   `duplicate()` 则既多占内存又和"重放走的是真实棋理"这条纪律分家。
func replay_goto(ply: int, host: Node, by_user: bool = true) -> bool:
	if replay_record.is_empty():
		return false
	var n: int = replay_total()
	var target: int = clampi(ply, 0, n)
	# ★★ 手动跳转要**清掉播放余量**：否则用户拖完滑条再按播放，会突然多走半秒的量
	#   （症状：拖完滑条按播放"手数跳了一截"，像滑条没同步）。
	# ★★ `by_user` 必须**由调用方显式传**，不能靠"当前是不是在播"来猜 ——
	#   `replay_tick()` 调本函数时恰好把 `replay_playing` 置假了（防递归 emit），
	#   于是自动推进也被当成手动跳转 ⇒ 每帧清一次余量 ⇒ **累积彻底失效**
	#   （症状：慢速永远停在原地，余量恒等于一帧的量 —— 判据 ⑥a 逮到）。
	if by_user:
		replay_frac = 0.0
	if target == replay_ply:
		# 同手重入也要把盘面刷回来 —— 调用方可能在 host 上换过盘（如"点棋盘跳转"）
		_rebuild(host, target)
		return true
	# ★★ 顺序铁律：**先挪游标，再重建盘面**。`replay_sync_turn()` 要读 `replay_ply`
	#   才知道"该轮到谁"，而它在 `_rebuild()` 末尾被调 ⇒ 先重建就会拿**旧游标**算执色，
	#   把已经翻对的 `current_player` 又改回去。症状：逐手跳转在第 1 手就错，且**只错 turn 一项**
	#   （盘面/劫点/提子数全对）—— 读起来像"指纹算错了"，实际是调用顺序。
	replay_ply = target
	_rebuild(host, target)
	replay_ply_changed.emit(replay_ply)
	if replay_ply >= n:
		replay_finished.emit()
	return true

## 清盘 + 顺序重放到第 ply 手。**所有对局状态的写都发生在 host 里**，
##   本文件只负责"该放什么手"，不自己碰 board —— 那是 game.gd 的真源。
func _rebuild(host: Node, ply: int) -> void:
	if host == null or not host.has_method("reset_game"):
		return
	# 钉死种子：复盘的盘必须与原局同一张，否则"重放"是在另一张盘上自说自话
	if host.has_method("replay_lock_seed"):
		host.call("replay_lock_seed", int(replay_record.get("board_seed", -1)))
	# ★ 探测性落子不入 `_hist`（与阶段① `--grecotest` ③ 同一条闸）。不开的话
	#   复盘会在 `_hist` 里攒出几百手，玩家退出复盘后按悔棋会退到"复盘的手数"上。
	host.set("_quiet_place", true)
	host.call("reset_game", true)
	var moves: Array = replay_record["moves"] as Array
	for i in range(mini(ply, moves.size())):
		var mv: Dictionary = moves[i]
		var tile: int = int(mv["tile"])
		if tile < 0:
			# 停一手必须走 `_apply_pass()`：它才翻 `current_player` 与 `passes`，
			# 直接改 board 会让"轮到谁"与真实对局不一致
			if host.has_method("replay_apply_pass"):
				host.call("replay_apply_pass")
			continue
		if not host.call("place_stone", tile, false):
			# 谱与棋理不自洽 —— 走到这里说明谱坏了。**不静默**：
			# 停在能重放的那一手，让 UI 显示的行号就是出错的地方。
			push_warning("复盘：第 %d 手（tile=%d）被棋理拒绝，谱可能已损坏" % [i + 1, tile])
			break
	host.set("_quiet_place", false)
	if host.has_method("replay_sync_turn"):
		host.call("replay_sync_turn")
	if host.has_method("queue_redraw"):
		host.call("queue_redraw")

## 连续播放推进。`delta` 秒。返回本次推进了几手。
##
## ★ 判据要量"时间轴真的在动"（速率 × 时间 == 游标增量），
##   别只判"最终到了末手" —— 那是恒真式（任何速率最终都停在末手）。
##
## ★★ 不足一手的余量必须**累积**（`replay_frac`），不能每帧 `int()` 扔掉：
##   首版写 `1 + int(rate * delta)` 想"至少走一手"，在 10 手/秒 + 60fps 下变成 **2 手/帧 = 120 手/秒**，
##   而"5 帧 × 0.1s = 0.5s ⇒ 应走 5 手"这条判据会红。症状：**倍速播放**，
##   而任何"最终到了末手"的判据都绿 —— 又一次恒真式。
## 正确形状：每帧推进 `floor(rate*dt)` 手，**余数留到下一帧**（`replay_frac`）。
func replay_tick(delta: float, host: Node, plays_per_sec: float) -> int:
	if not replay_playing or replay_record.is_empty():
		return 0
	if replay_ply >= replay_total():
		replay_playing = false
		replay_finished.emit()
		return 0
	replay_playing = false          # 抑制 _rebuild 里的递归 emit
	replay_frac += maxf(plays_per_sec, 0.0) * maxf(delta, 0.0)
	var steps: int = int(replay_frac)
	replay_frac -= float(steps)
	steps = mini(steps, replay_total() - replay_ply)
	for _i in range(steps):
		if not replay_goto(replay_ply + 1, host, false):
			break
	# ★★★ 必须在 for **之外**恢复，不能只在循环体里恢复。
	#   慢速时 `steps` 经常为 0（余量还不够 1 手）⇒ 循环体一次都不执行
	#   ⇒ `replay_playing` 留在 false ⇒ **下一帧开头直接 return 0** ⇒ 余量永远停在
	#   一帧的量（实测 3 手/秒 × 16ms 跑 100 帧：游标 0·余量恒 0.048）——**自锁死**。
	#   症状是"慢速播放永远不动"，而"最终到了末手"那条恒真判据照样绿。
	replay_playing = replay_ply < replay_total()
	return steps

func replay_toggle_play(host: Node) -> bool:
	if replay_record.is_empty():
		return false
	if replay_ply >= replay_total():
		# 在末手按播放 = 从头再来（用户预期），不是"什么也不做"
		replay_frac = 0.0
		replay_goto(0, host)
		replay_ply = 0
	replay_playing = not replay_playing
	return replay_playing
