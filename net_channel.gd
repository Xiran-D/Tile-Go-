class_name NetChannel
extends Node

# 对局通道契约（`SteamTransport` 是当前**唯一**实现）
# ---------------------------------------------------------------------------
# 为什么要有这个基类：
#   `game.gd` 用**一个** `_chan: NetChannel` 变量表示「本局走的是传输层通道（而不是直呼本地）」，
#   这就是全工程唯一的传输层判据。2026-09-30 之前它有两个实现（自建 TCP 中继 `RelayTransport`
#   + Steam P2P），第 5 步按用户口令「删除自建联机代码」删掉了自建中继 ⇒ **只剩 Steam 一个实现**。
#   ★ 基类**保留**（没有把它降级成 `SteamTransport` 类型），理由：它早已把调用点变成
#     "一处写、一处读" —— `game.gd` 里 11 处 `_chan.xxx()` 这次**一个字都没改**。
#     将来再加通道（例如局域网直连）也照旧：只多一个实现类，调用点零改动。
#
# ★★ 为什么**不用** Godot 高层 multiplayer（`MultiplayerPeer` / `@rpc`）：
#   Godot 4 的 `MultiplayerPeer` 是抽象类，GDScript 无法继承；
#   `MultiplayerPeerExtension` 的 `_put_packet(int,int)` 是指针式 API，GDScript 也用不了。
#   ⇒ 我们的通道是**普通 Node**，只负责"把 Dictionary 可靠地送到对端"，
#     对局层的权威判定 / 回放 / 校验全部留在 `game.gd`（`_apply_action` / `_validate_action`）。
#   ★★ 这段话**原在 `relay_transport.gd` 头部**，该文件第 5 步已移出工程根，故搬到这里保存 ——
#      它是"本工程为什么没有 RPC"的**唯一论证**。丢了它的后果不是报错，而是后来者重新引入
#      `@rpc` 并踩一遍当年的坑（第 5 步顺手删掉的那两个 `@rpc` 与 `sync_init` 就是当年的产物）。
#
# ★ 契约（实现必须满足）：
#   信号  relay_ready()                       通道就绪（**双方已到齐**，可以开始传业务数据）
#         relay_failed()                      连接失败或中断
#         message_received(msg: Dictionary)   收到对端一条消息
#   方法  send_message(msg: Dictionary)        发给对端（未就绪时**静默丢弃**，不报错）
#         is_live() -> bool                   通道是否可用
#         close_relay() -> void               主动关闭（可重复调用）
#
#   ⚠️ `start()` **故意不进基类**：各实现的入参本来就不同（Steam 要 lobby_id），
#      硬统一只会逼出"传一堆用不上的参数"这种更差的接口。各自 `start()` 契约写在各自文件头。
#
#   ⚠️ `relay_ready` 的语义是「**双方已到齐**」而不是「本端已连上」——
#      这条**必须**成立：`game.gd::_on_relay_ready()` 里房主会立刻下发初始盘面，
#      若在"对端还没来"时就触发，那份盘面会发给空气。
#
#   ★ 函数/信号名里的 `relay` 是**历史词**（自建中继时代的命名），现在不再指任何中继服务器。
#     改名要同时动基类 + `SteamTransport` + `game.gd` 十几处，收益为零，故保留。

signal relay_ready()                          # 双方都已就绪，通道可用
signal relay_failed()                         # 连接失败或中断
signal message_received(msg: Dictionary)      # 收到对端消息

## 通道是否可用（双方就绪）。默认 false —— 未实现的子类不会误报"可用"。
func is_live() -> bool:
	return false


## 主动关闭。可重复调用（第二次应是空操作）。
func close_relay() -> void:
	pass


## 发送一条消息。未就绪时应**静默丢弃**（与中继的行为一致：联机中断不该崩在发送点上）。
func send_message(_msg: Dictionary) -> void:
	pass
