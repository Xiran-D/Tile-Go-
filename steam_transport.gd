class_name SteamTransport
extends NetChannel

# Steam P2P 传输层（`NetChannel` 唯一实现，契约见基类 `net_channel.gd`）
# ---------------------------------------------------------------------------
# 它解决的问题：让玩家不必做路由器端口映射 —— **Steam 自己做 NAT 穿透**
#   （P2P + 中继兜底），而且不用我们运维任何服务器。
#   ★ 历史上这里还有一条对照物：自建 TCP 中继（`RelayTransport`，靠"双方都外连服务器"绕开
#     NAT）。第 5 步按用户口令「删除自建联机代码」把它删了 ⇒ 现在本类是本工程**唯一**的通道实现，
#     对照对象只剩"老方案 ENet 直连要房主开端口"这条历史背景。
#
# ★★ 与"已知房间号"的语义差异（这是接这个层最容易想错的地方）：
#   中继时代房间键 = 邀请码 = **开局前就已知**（本地生成、随 UI 显示）；
#   Steam 房主的 `lobby_id` 要 **`createLobby()` 异步回调之后**才有。
#   ⇒ 下面这个"分两个信号"的设计**正是为它而做**，删不得。
#   ⇒ 所以本类**分两个信号**：
#       `lobby_ready(lobby_id)` —— 房间已建好/已加入（**拿到 id 了**，UI 应该在这里显示房间号）
#       `relay_ready()`         —— 双方**到齐**（基类契约：此刻才能传业务数据）
#     房主侧 `start()` 拿不到 id 是**正常**的，不是错误 —— 别在 UI 里同步去读。
#
# ★ 就绪判定用**轮询成员表**而不是 `lobby_chat_update` 信号：
#   chat_update 的语义绕（还要区分"进/出/改数据"），而成员表在回调泵里必然已更新
#   ⇒ 每帧查一次 `lobby_member_count() >= 2` 更直白、更好测。
#
# ★ 实测事实（2026-09-30，`--steamp2p` 量出来的，写代码时直接信这几条）：
#   · `sendP2PPacket(发给自己)` 返回 true，且**自己的 `readP2PPacket` 能收到**载荷
#     （同账号同机的 P2P 回环是通的）⇒ 见 `peer_override` 的自检模式。
#   · 但**回环包报的 `steam_id_remote` 是 0**（不是自己的 id）⇒ 本类**不按来源过滤**，
#     否则自检路径会一条都收不到。
#   · 同账号 `joinLobby(自己建的房)` 返回 OK，可**成员数仍是 1** —— 一个 SteamID 在
#     一个房里只算一个成员。⇒ 「等第二个成员」在单账号下永远不会成立，
#     这也是必须有 `peer_override` 的原因。
# ---------------------------------------------------------------------------

## 房间已建好 / 已加入（**早于** relay_ready）。UI 用它在房主侧显示房间号。
signal lobby_ready(lobby_id: int)

enum St { INIT, WAIT_LOBBY, WAIT_PEER, LIVE, CLOSED }

## 等 lobby 回调的帧数上限（Steam 后端无响应时别无限挂着）
const WAIT_LOBBY_FRAMES := 1800        # ≈30 秒 @60fps

var _st: int = St.INIT
var _role: String = "host"
var _lobby_id: int = 0
var _peer: int = 0
var _peer_override: int = 0
var _live: bool = false
var _frames: int = 0


## 启动。role：`"host"`（建房）/ `"guest"`（加入）。
##   host 传 `lobby_id = 0`（id 由异步回调给出）；guest 必须传真实 id。
## `peer_override`：非 0 时**直接指定对端**，跳过"等第二个成员"——
##   只给**自检**用（同账号下房间里只会有一个成员，推不出对端；
##   而 P2P 回环本身是通的 ⇒ 用手动指定对端就能跑通完整的收发路径）。
func start(lobby_id: int, role: String, peer_override: int = 0) -> Error:
	_role = role
	_peer_override = peer_override
	_st = St.INIT
	_live = false
	_frames = 0
	_peer = 0

	if not SteamNet.ensure_init():
		# ★ 环境不可用（插件缺失/Steam 没开/未登录）走这里 —— 返回明确错误码，
		#   调用方（game.gd）据此给出人话提示，而不是卡在半路。
		printerr("[Steam] 传输层不可用：state=%s reason=%s" % [SteamNet.state(), SteamNet.reason()])
		return ERR_UNAVAILABLE

	# NAT 兜底：直连失败时允许走 Steam 中继（不保证低延迟，但比连不上好）
	SteamNet.allow_relay(true)

	_hook(SteamNet.steam_lobby_created, _on_lobby_created)
	_hook(SteamNet.steam_lobby_joined, _on_lobby_joined)
	_hook(SteamNet.steam_peer_packet, _on_packet)
	_hook(SteamNet.steam_session_request, _on_session_request)
	_hook(SteamNet.steam_session_failed, _on_session_failed)

	_st = St.WAIT_LOBBY
	set_process(true)

	if role == "host":
		_lobby_id = 0
		if not SteamNet.create_lobby():
			_fail("createLobby 调用失败")
			return ERR_CANT_CREATE
		print("[Steam] 建房中（lobby_id 由回调给出）…")
	else:
		_lobby_id = lobby_id
		if lobby_id == 0 or not SteamNet.join_lobby(lobby_id):
			_fail("joinLobby 调用失败（lobby_id=%d）" % lobby_id)
			return ERR_CANT_CONNECT
		print("[Steam] 加入房间中：lobby_id=%d …" % lobby_id)
	return OK


func is_live() -> bool:
	return _live


func get_lobby_id() -> int:
	return _lobby_id


func get_peer() -> int:
	return _peer


func send_message(msg: Dictionary) -> void:
	if not _live or _peer == 0:
		return
	SteamNet.send_message(_peer, msg)


func close_relay() -> void:
	if _st == St.CLOSED:
		return
	_st = St.CLOSED
	_live = false
	if _lobby_id != 0:
		SteamNet.leave_lobby(_lobby_id)
	if _peer != 0:
		SteamNet.close_session(_peer)
	_unhook(SteamNet.steam_lobby_created, _on_lobby_created)
	_unhook(SteamNet.steam_lobby_joined, _on_lobby_joined)
	_unhook(SteamNet.steam_peer_packet, _on_packet)
	_unhook(SteamNet.steam_session_request, _on_session_request)
	_unhook(SteamNet.steam_session_failed, _on_session_failed)
	set_process(false)


# ------------------------------------------------------------------ 主循环
func _process(_delta: float) -> void:
	if _st == St.CLOSED:
		return
	# ★ 必须显式轮询：`SteamNet._process` 只泵 `run_callbacks()`（不然信号永不触发），
	#   但**不读 P2P 包** —— 读包是 `readP2PPacket` 主动拉。漏了这一步就是"发得出去、收不回来"。
	SteamNet.poll_packets()

	_frames += 1
	match _st:
		St.WAIT_LOBBY:
			if _frames > WAIT_LOBBY_FRAMES:
				_fail("等待房间回调超时（%d 帧）——Steam 后端无响应？" % WAIT_LOBBY_FRAMES)
		St.WAIT_PEER:
			_resolve_peer()


## 从 lobby 成员表里认出对端。房主取"第一个不是自己的成员"；加入方取房主。
func _resolve_peer() -> void:
	if _peer_override != 0:
		_peer = _peer_override
		_go_live()
		return
	if _lobby_id == 0:
		return
	var me := SteamNet.my_id()
	if _role == "guest":
		var owner := SteamNet.lobby_owner(_lobby_id)
		# 房主就是自己 ⇒ 说明这个房还没别人（同账号自环时的典型情形），继续等
		if owner != 0 and owner != me:
			_peer = owner
	elif SteamNet.lobby_member_count(_lobby_id) >= 2:
		for m in SteamNet.lobby_members(_lobby_id):
			if int(m) != me:
				_peer = int(m)
				break
	if _peer != 0:
		_go_live()


func _go_live() -> void:
	if _live:
		return
	_live = true
	_st = St.LIVE
	print("[Steam] 对局通道已就绪：lobby=%d role=%s peer=%d" % [_lobby_id, _role, _peer])
	emit_signal("relay_ready")


func _fail(reason: String) -> void:
	if _st == St.CLOSED:
		return
	printerr("[Steam] ", reason)
	_st = St.CLOSED
	_live = false
	set_process(false)
	emit_signal("relay_failed")


# ------------------------------------------------------------------ 回调
func _on_lobby_created(ok: bool, lobby_id: int) -> void:
	if _st != St.WAIT_LOBBY or _role != "host":
		return
	if not ok:
		_fail("创建房间失败（lobby_created 回调 ok=false）")
		return
	_lobby_id = lobby_id
	_st = St.WAIT_PEER
	# ★ id 一拿到就广播给 UI（房主要靠它邀请好友），**不要**等 relay_ready
	emit_signal("lobby_ready", _lobby_id)
	print("[Steam] 房间已建：lobby_id=%d（等对端加入…）" % _lobby_id)


func _on_lobby_joined(ok: bool, lobby_id: int, response: int) -> void:
	if _st != St.WAIT_LOBBY or _role != "guest":
		return
	if not ok:
		_fail("加入房间失败（EResult=%d）" % response)
		return
	_lobby_id = lobby_id
	_st = St.WAIT_PEER
	emit_signal("lobby_ready", _lobby_id)
	print("[Steam] 已进房：lobby_id=%d" % _lobby_id)


## ★ 刻意**不按来源过滤**：实测同机回环包的 `steam_id_remote` 是 **0**，
##   真对局里房间里也只有对端一个人 ⇒ 按来源过滤只会白白丢掉自检路径的包。
func _on_packet(remote_id: int, data: Dictionary) -> void:
	if _st == St.CLOSED:
		return
	# ⚠️ 文案口径：`data.size()` 是**字段数**（字典的 size()），不是字节数 ——
	#    首版写成"字节"，实测一次完整的 init 快照打出"2 字节"，才发现读错了口径。
	#    这类"量具文案说谎"会让排查照着假数字走，比不打日志更坏。
	print("[Steam] 收到数据包（来源=%d，字段=%d）" % [remote_id, data.size()])
	emit_signal("message_received", data)


func _on_session_request(remote_id: int) -> void:
	# 接受动作已在 `SteamNet._on_session_request` 里做掉了（官方口径：必须主动 accept）
	print("[Steam] 对端发起 P2P 会话：%d" % remote_id)


func _on_session_failed(remote_id: int, session_error: int) -> void:
	# 会话建立失败不立刻判死：Steam 会回退到中继，重试往往就通了。
	# 只有**已经 ready 之后**对端掉线才值得报错。
	printerr("[Steam] P2P 会话失败：remote=%d err=%d" % [remote_id, session_error])


# ------------------------------------------------------------------ 小工具
func _hook(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)


func _unhook(sig: Signal, cb: Callable) -> void:
	if sig.is_connected(cb):
		sig.disconnect(cb)
