extends Node

# SteamNet —— Steam 联机薄封装（Autoload，2026-09-30 新增）
# ===========================================================================
# 职责：把 GodotSteam GDExtension 的 Steam 单例包成一层**永不崩、可探测**的门面。
#   第 1 步只做：可用性探测 / 惰性初始化 / 回调泵 / lobby 与 P2P 薄原语 / 自检。
#   与 game.gd 的传输层接线在第 2 步（届时 `_start_network()` 的单一分支点由两路变三路）。
#
# ★★ 为什么**全程用反射**（Engine.get_singleton + has_method + callv），
#    而不是直接写 `Steam.steamInit()`：
#    `Steam` 是 GDExtension 注册的单例。插件不在时（没装 addon / 导出包漏了库），
#    源码里只要出现 `Steam.` 字面量，**整个脚本会解析失败**。本脚本是 Autoload
#    ⇒ 解析失败 = **游戏一启动就死**，而且只留一行 Parse Error，极难定位。
#    ⇒ 反射版在插件缺失时只是 is_available() 返回 false，游戏照常跑。
#    （这条有结构守卫 S17 盯着：本文件非注释行里不许出现 `Steam.`，见 struct_guard.py）
#
# ★★ 反射调用前**必须先 has_method 守卫** —— 这不是"优化"，是硬要求：
#    调用不存在的方法**不是可捕获异常**，而是
#      `SCRIPT ERROR: Invalid call. Nonexistent function 'x' in base 'Steam'.`
#    并**中止整个调用函数**。实测（2026-09-30）：探针里因此没跑到 quit()，
#    进程挂死到被超时杀掉（EXIT=124）。少了守卫，一次改名就能把调用方整个函数带走。
#    ⇒ 一律走内部的 _invoke()，它自带守卫。
#
# ★ 本工程**不用** Godot 高层 multiplayer（自有 `SteamTransport` 传 Dictionary），
#   所以这里只需要 Steam 的 **Lobby + P2P socket** 两件事。
#   ★ 那段"为什么不用 MultiplayerPeer"的论证（GDScript 继承不了抽象类 / 指针式 API 用不了）
#     原在 `relay_transport.gd` 头部，第 5 步该文件移出工程根时已搬到 `net_channel.gd` 头部。
#
# ★ 枚举取值口径（对着 Steamworks 官方文档核过，别想当然）：
#    sendP2PPacket 的 send_type 吃的是**老 API 的 P2PSend**：
#      P2P_SEND_UNRELIABLE=0 / UNRELIABLE_NO_DELAY=1 / **RELIABLE=2** / RELIABLE_WITH_BUFFERING=3
#    ⚠️ 不是 `NETWORKING_SEND_RELIABLE = 8` —— 那是另一套（Networking Sockets）的旗标，
#       值不同、用错**不报错**，只会让消息永远发不出去（静默失效）。
#    P2P_SEND_RELIABLE 单条上限 1MB 且底层自动分片重组 ⇒ 我们**不需要自己做分片**。
# ===========================================================================

signal steam_state_changed()
signal steam_lobby_created(ok: bool, lobby_id: int)
signal steam_lobby_joined(ok: bool, lobby_id: int, response: int)
signal steam_session_request(remote_id: int)
signal steam_session_failed(remote_id: int, session_error: int)
signal steam_peer_packet(remote_id: int, data: Dictionary)
signal steam_packet_read(remote_id: int, data: Dictionary)   # 原始字节解出的 Dictionary（Step 2 用）
signal steam_lobby_list_received(lobby_ids: Array)           # 大厅列表回来了（异步，UI 挂这里）
## 好友接受邀请 / 用 Steam 好友列表的「加入游戏」进来了（2026-10-21）。
## ★ 这是「邀请好友」功能**唯一的入站出口**：好友点接受后，Steam 会
##   ① 程序没开 ⇒ 用 `+connect_lobby <id>` 拉起（`_scan_launch_command()` 解析后也走这个信号）
##   ② 程序已开 ⇒ 直接触发 `join_requested`（本文件 `_on_join_requested` 转发）
##   ③ 游戏**已被 Steam 拉起但还在菜单** ⇒ 情形 ① 的解析结果由菜单侧消费
##   ⇒ 菜单只需要连这一个信号，不必分别处理三种情形（否则三条路各缺一条 = 静默不联动）。
## `friend_id == 0` 表示"不是运行时收到的好友请求"（来自启动参数）。
signal steam_join_requested(lobby_id: int, friend_id: int)

const SINGLETON := "Steam"
const P2P_CHANNEL := 0

# 可用性状态（字符串而非枚举：日志里直接可读，且自检好断言）
const ST_MISSING := "插件缺失"       # 没有 Steam 单例（addon 没装 / 导出漏库）
const ST_NOT_RUNNING := "Steam 未运行"     # 单例在，但 Steam 客户端没开 / 没登录
const ST_INIT_FAILED := "Steam 初始化失败"  # steamInit() 返回 false
const ST_READY := "就绪"
const ST_IDLE := "未初始化"          # 还没试过（惰性）

# P2PSend（老 API 口径，已核）
const P2P_SEND_UNRELIABLE := 0
const P2P_SEND_RELIABLE := 2

# 自检用：强制"假装插件缺失"（专门用来验证优雅降级这条路真的走得通）
var _force_missing: bool = false

var _inited: bool = false
var _state: String = ST_IDLE
var _reason: String = ""
var _app_id: int = 0
var _own_id: int = 0
var _persona: String = ""
var _version: String = ""

## 当前所在 lobby。**唯一写点**：`_on_lobby_created` / `_on_lobby_joined`（写）、
## `leave_lobby`（清 0）。读点：`current_lobby_id()` / `open_invite_dialog()`。
## ★ 为什么不在 SteamNet 之外再存一份：`activateGameOverlayInviteDialog` 要的正是它，
##   而"传输层手里的 lobby"与"能弹邀请窗口的 lobby"必须是同一个数（两处各存一份 = 迟早分家）。
var _lobby_id: int = 0
## 启动参数 `+connect_lobby <id>` 解析出来的房间号（0 = 没有）。
## 由 `take_pending_join()` 消费（读即清空）—— 否则菜单每次进对弈页都会再跳一次。
var _pending_join: int = 0


func _ready() -> void:
	# ★ 刻意**不自动初始化**：第 1 步里没有任何调用方，自动初始化只会给
	#   现有 200+ 个 headless 自检引入一个无谓的 Steam 依赖。
	#   第 2 步由联机入口显式 ensure_init()。
	set_process(false)


## 每帧泵回调。★ 不调它 Steam 的信号**永不触发**（GodotSteam 最经典的坑）。
func _process(_delta: float) -> void:
	if _inited:
		_invoke("run_callbacks", [])


# ------------------------------------------------------------------ 反射内核

## 取 Steam 单例；插件缺失返回 null。**所有对 Steam 的访问都必须经过这里。**
func _singleton() -> Object:
	if _force_missing:
		return null
	if not Engine.has_singleton(SINGLETON):
		return null
	return Engine.get_singleton(SINGLETON)


## 安全调用。★ 先 has_method 守卫（理由见文件头）—— 缺了它会把调用方整个函数带走。
func _invoke(method: String, args: Array = []) -> Variant:
	var s := _singleton()
	if s == null:
		return null
	if not s.has_method(method):
		return null
	return s.callv(method, args)


func _has_method(method: String) -> bool:
	var s := _singleton()
	return s != null and s.has_method(method)


## 取 Steam 的整数常量（反射，带兜底）。用来核对枚举口径而不写死。
func _iconst(name: String, fallback: int) -> int:
	var s := _singleton()
	if s == null:
		return fallback
	if not ClassDB.class_has_integer_constant(SINGLETON, name):
		return fallback
	return ClassDB.class_get_integer_constant(SINGLETON, name)


# ★★ 取默认值**绝不用 `a or b`** —— 实测（2026-09-30）：**GDScript 的 `or` 返回 bool**，
#   不像 Python 那样返回左值。`int(_invoke("getAppID", []) or 0)` 得到的是 `int(true)` = **1**，
#   于是 appid / steamid 全变成 1、昵称变成字符串 "true"，**一条错都不报**。
#   ★ 更阴的是它会让判据**假阳性**：⑤e「房主==自己」两边用的是同一个坏表达式，
#     坏得一样 ⇒ "相等" ⇒ 亮绿灯。⇒ 必须显式判 null。
func _i(method: String, args: Array = [], dflt: int = 0) -> int:
	var v: Variant = _invoke(method, args)
	return dflt if v == null else int(v)


func _b(method: String, args: Array = [], dflt: bool = false) -> bool:
	var v: Variant = _invoke(method, args)
	return dflt if v == null else bool(v)


func _str(method: String, args: Array = [], dflt: String = "") -> String:
	var v: Variant = _invoke(method, args)
	return dflt if v == null else str(v)


## 合法 SteamID64 的下界（个人账号基址）。
## ★★ 为什么要专门有这么一条：`int(true)` = 1 这类「值悄悄变成 1」的 bug，用 `> 0` **根本抓不住**
##    （1 > 0 为真）。实测就是靠「是不是合法 SteamID64」才发现 appid/steamid 全变成 1 的。
const STEAM_ID_FLOOR := 76561197960265728


func _is_steam_id(v: int) -> bool:
	return v >= STEAM_ID_FLOOR


func _connect_signal(sig: String, cb: Callable) -> bool:
	var s := _singleton()
	if s == null or not s.has_signal(sig):
		return false
	if s.is_connected(sig, cb):
		return true
	return s.connect(sig, cb) == OK


# ------------------------------------------------------------------ 可用性

func is_plugin_present() -> bool:
	return (not _force_missing) and Engine.has_singleton(SINGLETON)


## 供**自检**强制"插件缺失"（§21 第 3 步：菜单里 Steam 那一档必须**禁用**并给理由）。
## ★ 幂等、只赋值、不做任何额外探测 —— 探测本身就读这个开关，写与读必须同一处状态。
## ★★ 2026-10-01 修正：开闸（`true`）时**同时复位 `_inited`**。
##   起因：`ensure_init()` 头一句是 `if _inited: return _state == ST_READY` ——
##   已经 init 成功过就直接短路返回，`is_plugin_present()` 那一层**根本不会被问**。
##   于是"强制复现插件缺失"对已 init 的实例**完全无效**（实测：本机 Steam 真能 init，
##   `--steamuitest` ⑪ 恒红）。而要靠 `shutdown_steam()` 复位又会连带触发
##   `_show_error_toast()` 重建页面 ⇒ 整个自检被静默中止（一条判据都打不出来）。
##   语义上也该这样：「强制复现插件缺失」= 让下一次 init 从头判一次，
##   而不是"在已就绪的状态上假装插件不在"（那是自相矛盾的状态）。
##   ★ 关闸（`false`）**不复位**：那是"恢复正常"，下一次 init 该走真路径。
func set_force_missing(v: bool) -> void:
	_force_missing = v
	if v:
		_inited = false



func is_available() -> bool:
	return _inited and _state == ST_READY


func state() -> String:
	return _state


func reason() -> String:
	return _reason


## 惰性初始化，幂等。返回是否可用。
func ensure_init() -> bool:
	if _inited:
		return _state == ST_READY
	if not is_plugin_present():
		_state = ST_MISSING
		_reason = missing_diag()
		emit_signal("steam_state_changed")
		return false

	# 先看客户端在不在（steamInit 会去连本地 Steam，未运行时给更准确的理由）
	if _has_method("isSteamRunning") and not _b("isSteamRunning"):
		_state = ST_NOT_RUNNING
		_reason = "Steam 客户端未运行"
		emit_signal("steam_state_changed")
		return false

	# ★ steamInit 返回 bool（不是字典）。app_id 传 0 = 用 steam_appid.txt / Steam 注入的
	var ok: bool = _b("steamInit", [], false)
	_inited = true
	set_process(true)
	if not ok:
		_state = ST_INIT_FAILED
		_reason = "steamInit() 返回 false（未登录 / appid 不对 / steam_appid.txt 缺失）"
		emit_signal("steam_state_changed")
		return false

	_state = ST_READY
	_reason = ""
	_app_id = _i("getAppID")
	_own_id = _i("getSteamID")
	_persona = _str("getPersonaName")
	_version = _str("get_godotsteam_version")
	_hook_signals()
	print("[SteamNet] 就绪 | appid=", _app_id, " | steamid=", _own_id,
			" | 昵称=", _persona, " | GodotSteam ", _version)
	# ★ 「被邀请启动」：Steam 会用 `+connect_lobby <id>` 拉起本程序。
	#   解析到就**立刻**发一次 `steam_join_requested`（friend_id=0 标记来源是启动参数），
	#   同时把 id 留在 `_pending_join` 里供菜单消费 —— 两条都留的理由：
	#   发射可能比菜单 `_ready` 里的 connect 早（顺序不定），而 pending 读即清空，
	#   谁先到谁处理，不会重复进局。
	_scan_launch_command()
	if _pending_join != 0:
		print("[SteamNet] 启动参数带房间号：", _pending_join)
		emit_signal("steam_join_requested", _pending_join, 0)
	emit_signal("steam_state_changed")
	return true


func _hook_signals() -> void:
	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("p2p_session_request", _on_session_request)
	_connect_signal("p2p_session_connect_fail", _on_session_fail)
	_connect_signal("lobby_match_list", _on_lobby_match_list)
	# ★ 好友接受邀请 / 「加入游戏」（2026-10-21）。信号名对着本机 GodotSteam 实测核过
	#   （`activateGameOverlayInviteDialog` / `join_requested` / `getLaunchCommandLine` 都在），
	#   不是照文档猜的 —— 核对记录见 `_probe_steam_api.gd` 那次的输出。
	_connect_signal("join_requested", _on_join_requested)


func shutdown_steam() -> void:
	if _inited:
		_invoke("steamShutdown", [])
	_inited = false
	_state = ST_IDLE
	set_process(false)


## 供自检/诊断用的一份快照
func info() -> Dictionary:
	return {
		"plugin_present": is_plugin_present(),
		"inited": _inited,
		"state": _state,
		"reason": _reason,
		"app_id": _app_id,
		"steam_id": _own_id,
		"persona": _persona,
		"godotsteam_version": _version,
		"logged_on": _b("loggedOn"),
		"lobby_id": _lobby_id,
		"pending_join": _pending_join,
	}


# ------------------------------------------------------------------ 头像 / 昵称（2026-10-21）

## 头像尺寸档（Steam `AvatarSize` 口径）：0=小 32×32 / 1=中 64×64 / 2=大 184×184。
## ★ 生产默认取**中档**：对局页头像的逻辑直径约 44~56px，64 已覆盖到 2× 显隐比；
##   大档是 184×184 = 135,424 字节的 RGBA，为一个 44px 的圆多传 8 倍数据，换不到可见差异。
const AVATAR_SMALL := 0
const AVATAR_MEDIUM := 1
const AVATAR_LARGE := 2

## 同一个 (size, steam_id) 最多试几次就放弃。
## 每次 `avatar_texture()` 返回 null 记一次；UI 侧按 0.5s 节奏重试 ⇒ 14 次 ≈ 7 秒。
## ★ 为什么要"重试"：对端头像**首次查询时 Steam 往往还没下载完**，`getXxxFriendAvatar`
##   在未就绪时返回 handle = 0（这不报错）。它能下载，是靠 `run_callbacks()` 在跑
##   （本文件 `_process` 一直在泵）⇒ 正确做法是"下帧再问"，不是阻塞等。
## ★ 为什么要"上限"：永远返回 0 的情形真实存在（对方没设头像 / 非好友被隐私挡住 /
##   单例半初始化）。不封顶就是每秒两次空调用陪跑整局。
const AVATAR_RETRY_LIMIT := 14

var _avatar_cache: Dictionary = {}    # "size:steam_id" -> Texture2D
var _avatar_miss: Dictionary = {}     # 同上 -> 已经失败过几次


## 取某人的 Steam 头像。**拿不到返回 null** —— 调用方必须画占位，不许假设非空。
##
## ★★ 这里**刻意不用** `Steam.getPlayerAvatar(size, steam_id)`：
##   2026-10-21 实测（工作区 `_probe_steam_avatar.gd`）—— 它的返回类型是 **NIL**，
##   而且**会阻塞**：内部要等 `avatar_loaded` 回调，在没有主循环泵 `runCallbacks()`
##   的语境里直接卡死（探针 60 秒超时，日志停在调用行）。
##   进游戏后更糟：它会卡住主线程（掉帧，且看不出来是谁卡了）。
##   ⇒ 正路是方法表里那三个**同步返回 handle** 的 `getSmall/Medium/LargeFriendAvatar`，
##     handle 为 0 时下一帧再问（见 `AVATAR_RETRY_LIMIT` 的注）。
##
## ★ 返回值形态实测（同上探针，GodotSteam 4.22.1）：
##     `getImageSize(handle)`  -> Dictionary { success: bool, width: int, height: int }
##     `getImageRGBA(handle)`  -> Dictionary { success: bool, buffer: PackedByteArray }
##     buffer 长度 == width*height*4，RGBA8 排列，**行序从上到下**（无需翻转）。
func avatar_texture(steam_id: int, size: int = AVATAR_MEDIUM) -> Texture2D:
	if not _inited or not _is_steam_id(steam_id):
		return null
	var key := "%d:%d" % [size, steam_id]
	var cached: Variant = _avatar_cache.get(key)
	if cached != null and is_instance_valid(cached):
		return cached as Texture2D
	if int(_avatar_miss.get(key, 0)) >= AVATAR_RETRY_LIMIT:
		return null      # 已放弃：不再对 Steam 做无谓调用（见 AVATAR_RETRY_LIMIT）
	var handle := _avatar_handle(steam_id, size)
	if handle == 0:
		_avatar_miss[key] = int(_avatar_miss.get(key, 0)) + 1
		return null
	var tex := _decode_avatar(handle)
	if tex == null:
		_avatar_miss[key] = int(_avatar_miss.get(key, 0)) + 1
		return null
	_avatar_cache[key] = tex
	return tex


## 是否"还值得再问一次"：没缓存、也没超过重试上限。
## ★ UI 侧的重试闸必须问这个谓词（而不是自己数次数）—— 否则两处各有一份计数迟早分家，
##   典型症状是"头像已经放弃了，界面还在每秒空转"。
func avatar_pending(steam_id: int, size: int = AVATAR_MEDIUM) -> bool:
	if not _inited or not _is_steam_id(steam_id):
		return false
	var key := "%d:%d" % [size, steam_id]
	if _avatar_cache.has(key):
		return false
	return int(_avatar_miss.get(key, 0)) < AVATAR_RETRY_LIMIT


## 清头像缓存（换对端 / 重进对局时用）。★ 不清的表现不是崩，是"新对手显示旧头像"。
func clear_avatar_cache() -> void:
	_avatar_cache.clear()
	_avatar_miss.clear()


func _avatar_handle(steam_id: int, size: int) -> int:
	match size:
		AVATAR_SMALL:
			return _i("getSmallFriendAvatar", [steam_id])
		AVATAR_LARGE:
			return _i("getLargeFriendAvatar", [steam_id])
		_:
			return _i("getMediumFriendAvatar", [steam_id])


func _decode_avatar(handle: int) -> Texture2D:
	var isz: Variant = _invoke("getImageSize", [handle])
	if not (isz is Dictionary):
		return null
	var sd: Dictionary = isz
	if not bool(sd.get("success", false)):
		return null
	var w: int = int(sd.get("width", 0))
	var h: int = int(sd.get("height", 0))
	if w <= 0 or h <= 0:
		return null
	var rgba: Variant = _invoke("getImageRGBA", [handle])
	if not (rgba is Dictionary):
		return null
	var rd: Dictionary = rgba
	if not bool(rd.get("success", false)):
		return null
	var buf: PackedByteArray = rd.get("buffer", PackedByteArray())
	# ★ 长度自校验：`create_from_data` 对短 buffer **不报错**，会造出一张半黑的图
	#   （右下半截全 0）。这种"没报错的坏图"只能靠长度判据挡。
	if buf.size() < w * h * 4:
		return null
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## 某一方的昵称。自己走缓存的 `_persona`（`getFriendPersonaName(self)` 在某些
## 登录态下返回空串），别人问 Steam。
func persona_of(steam_id: int) -> String:
	if not _inited or not _is_steam_id(steam_id):
		return ""
	if steam_id == _own_id:
		return _persona
	return _str("getFriendPersonaName", [steam_id])


# ------------------------------------------------------------------ 回调

func _on_lobby_created(connect: int, lobby_id: int) -> void:
	# connect == 1 是 k_EResultOK
	var ok := int(connect) == 1
	if not ok:
		_reason = "创建房间失败（EResult=%d）" % int(connect)
	else:
		# ★ 唯一写点之一（建好房 ⇒ 这就是"当前房间"）。失败时**不写** ——
		#   写 0 会把上一间房（可能还活着）的 id 抹掉，而邀请窗口正是按它弹的。
		_lobby_id = int(lobby_id)
	emit_signal("steam_lobby_created", ok, int(lobby_id))


func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	var ok := int(response) == 1
	if not ok:
		_reason = "加入房间失败（EResult=%d）" % int(response)
	else:
		_lobby_id = int(lobby)       # 唯一写点之二（见 `_on_lobby_created` 的说明）
	emit_signal("steam_lobby_joined", ok, int(lobby), int(response))


func _on_session_request(remote_id: int) -> void:
	# ★ 官方口径：收到 p2p_session_request 后**必须**主动 accept，否则对端超时（20s）后报 connect_fail。
	#   （若我们先前已 sendP2PPacket 给对端，则视为隐式接受。）
	_invoke("acceptP2PSessionWithUser", [int(remote_id)])
	emit_signal("steam_session_request", int(remote_id))


func _on_session_fail(remote_id: int, session_error: int) -> void:
	emit_signal("steam_session_failed", int(remote_id), int(session_error))


## lobby_match_list 回调。GodotSteam 4.x 传 Array（lobby id 列表）；老版本可能传 int（已处理数）。
## 用 Variant 接收、运行时判类型 —— 实际到了什么就接什么（不照文档猜）。
func _on_lobby_match_list(arg: Variant = null) -> void:
	var ids: Array = []
	if arg is Array:
		ids = arg
	elif arg is int:
		for i in int(arg):
			var lid := _i("getLobbyByIndex", [i])
			if lid != 0:
				ids.append(lid)
	emit_signal("steam_lobby_list_received", ids)


# ------------------------------------------------------------------ Lobby 原语
# 全部是"失败即安全返回"，没有一处会在插件缺失/未初始化时抛出去。

func my_id() -> int:
	return _own_id


## 自己的昵称（联机大厅：房主写进 lobby data 供陌生人显示）。
func my_persona() -> String:
	return _persona


func create_lobby(lobby_type: int = 2, max_members: int = 2) -> bool:
	if not is_available():
		return false
	# 官方口径：ELobbyType 0=Private 1=FriendsOnly 2=Public 3=Invisible
	var t := lobby_type if lobby_type >= 0 else _iconst("LOBBY_TYPE_PUBLIC", 2)
	_invoke("createLobby", [t, max_members])
	return true


# ------------------------------------------------------------------ 大厅列表（大厅浏览器）
const LOBBY_GAME_KEY := "game"       # lobby data 里"本游戏标识"的键名
const LOBBY_GAME_TAG := "tile-go"    # 本游戏在 lobby data 里写的值（建房时写入，浏览时用它过滤）
const LOBBY_NAME_KEY := "name"       # 房主昵称
const LOBBY_RECORD_KEY := "record"   # 房主战绩串（record_str()）

## 请求公开大厅列表。回调走 `steam_lobby_list_received`（异步）。
## ★ 只搜本游戏的大厅：StringFilter 过滤 `game == tile-go` —— AppID 480 是公共测试 id，
##   不过滤会把**其他开发者**的测试大厅也列进来（"看到不同玩家"必须是"本游戏的玩家"）。
func request_lobby_list() -> bool:
	if not is_available():
		return false
	_invoke("addRequestLobbyListStringFilter",
			[LOBBY_GAME_KEY, LOBBY_GAME_TAG, _iconst("LOBBY_COMPARISON_EQUAL", 0)])
	_invoke("requestLobbyList", [])
	return true


func join_lobby(lobby_id: int) -> bool:
	if not is_available():
		return false
	_invoke("joinLobby", [lobby_id])
	return true


func leave_lobby(lobby_id: int) -> void:
	if not is_available():
		return
	_invoke("leaveLobby", [lobby_id])
	# ★ 退房后「当前房间」必须归零：留着旧 id 的话，下一局开局前点「邀请好友」
	#   会把好友拉进一个**已经不存在**的房间（Steam 那边不报错，好友干等 = 静默失效）。
	if int(lobby_id) == _lobby_id:
		_lobby_id = 0


func lobby_member_count(lobby_id: int) -> int:
	return _i("getNumLobbyMembers", [lobby_id])


func lobby_member_at(lobby_id: int, index: int) -> int:
	return _i("getLobbyMemberByIndex", [lobby_id, index])


func lobby_members(lobby_id: int) -> Array:
	var out: Array = []
	var n := lobby_member_count(lobby_id)
	for i in n:
		out.append(lobby_member_at(lobby_id, i))
	return out


func lobby_owner(lobby_id: int) -> int:
	return _i("getLobbyOwner", [lobby_id])


func lobby_set_data(lobby_id: int, key: String, value: String) -> bool:
	return _b("setLobbyData", [lobby_id, key, value])


func lobby_get_data(lobby_id: int, key: String) -> String:
	return _str("getLobbyData", [lobby_id, key])


func lobby_set_member_data(lobby_id: int, key: String, value: String) -> void:
	if not is_available():
		return
	_invoke("setLobbyMemberData", [lobby_id, key, value])



# ------------------------------------------------------------------ P2P 原语

## 发送一条 Dictionary 消息。★ 分片交给 Steam（P2P_SEND_RELIABLE 单条上限 1MB）。
func send_message(remote_id: int, msg: Dictionary) -> bool:
	if not is_available() or remote_id == 0:
		return false
	var payload := var_to_bytes(msg)
	return _b("sendP2PPacket",
			[int(remote_id), payload, P2P_SEND_RELIABLE, P2P_CHANNEL])


## 把通道 0 上攒着的包全读掉，逐条发 steam_peer_packet。
## 返回读到的条数（自检/诊断用）。
func poll_packets() -> int:
	if not is_available():
		return 0
	var n := 0
	while true:
		var sz := _i("getAvailableP2PPacketSize", [P2P_CHANNEL])
		if sz <= 0:
			break
		var r: Variant = _invoke("readP2PPacket", [sz, P2P_CHANNEL])
		if not (r is Dictionary) or (r as Dictionary).is_empty():
			break
		var d: Dictionary = r
		var src := int(d.get("steam_id_remote", 0))
		var raw: Variant = d.get("data", PackedByteArray())
		if raw is PackedByteArray:
			var msg: Variant = bytes_to_var(raw)
			if msg is Dictionary:
				emit_signal("steam_peer_packet", src, msg)
		n += 1
		if n > 4096:      # 防呆：理论上读不空也不能死循环
			break
	return n


func allow_relay(allow: bool) -> void:
	_invoke("allowP2PPacketRelay", [allow])


# ------------------------------------------------------------------ 邀请好友（2026-10-21）
# ★★ 用户口令「我想要在游戏里直接点击就能召唤 steam 邀请好友窗口邀请好友对弈」。
#   唯一正确的 API 是 **`activateGameOverlayInviteDialog(lobby_id)`** —— 它弹出的是
#   Steam 自己的「邀请好友到大厅」覆盖层（好友列表 + 在线状态 + 一键邀请），
#   而不是我们自己画一个好友列表（那需要好友列表权限与大量 UI，且不会有 Steam 的互通性）。
#
# ★ 三条硬约束（踩了都不报错，只表现为"点了没反应"）：
#   ① **必须已经在 lobby 里**：lobby_id=0 时调用等于弹一个空对话框 ⇒ 本层显式挡下并给理由。
#   ② **必须由 Steam 启动、且 Steam 覆盖层可用**：从 Godot 编辑器启动时覆盖层基本不起作用
#      （addons/godotsteam/readme.md 第 72 行原话：Overlay *may not* work when running
#      your game from Godot but the exported project should work）。⇒ 本层先问
#      `isOverlayEnabled()`，不对就明说原因，绝不假装成功。
#   ③ 覆盖层是**异步的 UI**：调用成功只代表"请求弹窗了"，不代表好友已经收到/接受。
#      ⇒ 进局的真实判据仍然是「lobby 成员数 ≥ 2」（`SteamTransport` 的轮询），
#        本条不做任何"邀请成功"的承诺。

func current_lobby_id() -> int:
	return _lobby_id


## 邀请窗口此刻能不能弹。返回 {"ok": bool, "reason": String, "warn": String}（**不弹窗**，纯探测）。
## ★ 给 UI 用：按钮该不该可点、点不了时给人看什么理由 —— 都在这一处派生，
##   免得按钮在"点了必然失败"的状态下依然亮着（铁律 7：能点但点了没反应）。
##
## ★★ `isOverlayEnabled()==false` **不当作拒绝**（2026-10-21 实测后改口）：
##   本机实测（真窗口 + 编辑器运行）它返回 **false** —— 因为 Steam 覆盖层只有在游戏
##   **由 Steam 启动**时才会被注入，从编辑器跑出来就是 false。若拿它当硬闸，
##   "在编辑器里点邀请"会永远被拒 ⇒ 功能没法调试，用户只会说"按钮是灰的"。
##   ⇒ 口径改成：**照样请求弹窗**，但把"覆盖层未启用"作为 `warn` 带回去，由 UI 明说
##     "若没看到弹窗，请用 Steam 启动的导出包 / 或把房间号给好友"（诚实 + 可调试）。
func invite_capability() -> Dictionary:
	if not ensure_init():
		return {"ok": false, "reason": "Steam 不可用：%s" % _reason, "warn": ""}
	if _lobby_id == 0:
		return {"ok": false, "reason": "还没有房间号（建房回调未返回，或已退房）", "warn": ""}
	if not _has_method("activateGameOverlayInviteDialog"):
		return {"ok": false, "reason": "GodotSteam 缺 activateGameOverlayInviteDialog（版本过旧）", "warn": ""}
	var warn := ""
	if _has_method("isOverlayEnabled") and not _b("isOverlayEnabled", [], true):
		warn = "Steam 覆盖层当前未启用（编辑器里运行不会注入覆盖层）" \
				+ "——若没看到弹窗，请用由 Steam 启动的导出包，或把房间号发给好友"
	return {"ok": true, "reason": "", "warn": warn}


## 弹出 Steam「邀请好友到大厅」覆盖层。返回 {"ok": bool, "reason": String, "warn": String}。
## ★ 返回值只表示**请求已发出且前置条件成立**；好友是否收到/接受，回执是
##   `steam_join_requested` + lobby 成员数变化，不是这里。
func open_invite_dialog() -> Dictionary:
	var cap := invite_capability()
	if not bool(cap.get("ok", false)):
		return cap
	_invoke("activateGameOverlayInviteDialog", [_lobby_id])
	print("[SteamNet] 已请求弹出邀请好友对话框 | lobby_id=", _lobby_id,
			" | 覆盖层警告=", str(cap.get("warn", "")))
	return cap


## `join_requested` 回调：好友接受了邀请 / 从 Steam 好友列表点了「加入游戏」。
## ★ 参数口径（本机实测信号签名）：(lobby: int, friend: int)。
##   这里**只转发**，不做加入动作 —— "加入"要切场景，属菜单/对局的职责。
func _on_join_requested(lobby_id: int, friend_id: int) -> void:
	print("[SteamNet] 收到好友加入请求 | lobby=", lobby_id, " friend=", friend_id)
	emit_signal("steam_join_requested", int(lobby_id), int(friend_id))


## 启动命令行里 `+connect_lobby <id>` 解析（Steam 拉起被邀请的玩家时用这一招）。
## ★ 只认这一个旗标：Steam 也会传别的 `+xxx`，扫到别的就跳过，绝不猜。
const CONNECT_LOBBY_FLAG := "+connect_lobby"

func _scan_launch_command() -> int:
	_pending_join = 0
	if not _has_method("getLaunchCommandLine"):
		return 0
	var raw := _str("getLaunchCommandLine").strip_edges()
	if raw == "":
		return 0
	var parts := raw.split(" ", false)
	for i in parts.size():
		var t := str(parts[i])
		var val := ""
		if t == CONNECT_LOBBY_FLAG and i + 1 < parts.size():
			val = str(parts[i + 1])
		elif t.begins_with(CONNECT_LOBBY_FLAG + "="):
			val = t.substr(CONNECT_LOBBY_FLAG.length() + 1)
		if val.is_valid_int() and int(val) > 0:
			_pending_join = int(val)
			break
	return _pending_join


## **读即清空**：消费掉"启动参数带来的房间号"。菜单只在真的要用它进局时调。
func take_pending_join() -> int:
	var v := _pending_join
	_pending_join = 0
	return v


# ------------------------------------------------------------------ 插件缺失诊断（2026-10-21）

## 「插件缺失」时到底缺哪一层 —— 逐层体检，返回一行可读的原因。
##
## ★★ 为什么必须有它（用户实测：第二台电脑大厅里显示"未找到 Steam 单例"）：
##   原来那一句 `未找到 Steam 单例（addons/godotsteam 未安装？）` 只是**猜测**，
##   而这件事有四种完全不同的成因，处置方式相反：
##     ① 编辑器里跑，但工程副本没带 `addons/godotsteam`（第二台是拷过去的旧副本/瘦身副本）
##     ② 导出包缺库：`.dll` 没跟着 exe 走（`steam_api64.dll` 是 GDExtension 的
##        dependency，缺了它整个扩展加载失败 —— 报错只会出现在启动日志里，游戏内看不到）
##     ③ 引擎版本 < `compatibility_minimum`（本工程写 4.4）⇒ GDExtension 被拒装
##     ④ 库文件被 Windows 拦（从别的机器拷来的 dll 带 Zone.Identifier）或被杀软隔离
##   ⇒ 把"猜测"换成"体检报告"：**每一层都指名**，玩家/开发者截图就能定位。
##   体检本身**只读**（不动任何文件），插件在时也可以随时调来印一份（自检用）。
func missing_diag() -> String:
	return "未找到 Steam 单例（addons/godotsteam 未安装？）｜" + diag_report()


## 一个随包 dll 在**当前运行方式下**的真实位置。
## ★★ 为什么不能一律用 `res://`（2026-10-21 导出 demo0.8 时当场抓到）：导出包里
##   `.gdextension` 写的 `res://addons/godotsteam/win64/x.dll` 会被引擎**映射到 exe 同级**
##   （实测导出目录里就是 `steam_api64.dll` / `libgodotsteam.…dll` 平铺在 exe 旁边），
##   而 `FileAccess.file_exists("res://addons/…")` 在导出包里**恒 false**
##   ⇒ 旧实现对着一个**完好**的导出包报「库=缺失:res://addons/…」外加一句
##     「把 addons/godotsteam 整目录随工程一起拷过去」，**指错方向**（量具不许说谎）。
##   实测现场：`dist/demo0.8/瓷砖围棋.exe -- --steamdiag` 报「库=缺失」，而**同一行**的
##   「exe 同级 dll」里两个 dll 都在，且 `ensure_init=true state=就绪`。
##   ⇒ 编辑器里看 `res://`（那里就是文件真身），导出包里看 exe 同级。
func _runtime_dll_path(res_path: String) -> String:
	if res_path == "":
		return ""
	if OS.has_feature("editor"):
		return res_path
	return OS.get_executable_path().get_base_dir().path_join(res_path.get_file())


## 逐层体检报告（**不带结论前缀**）。插件在的时候也随时可调 —— 命令行入口是
## `瓷砖围棋.exe -- --steamdiag`（见 menu.gd），专给"另一台机器上到底缺哪一层"用。
func diag_report() -> String:
	var bits: Array = []
	var editor: bool = OS.has_feature("editor")
	bits.append("运行方式=%s" % ("编辑器" if editor else "导出包"))
	bits.append("引擎=%s" % str(Engine.get_version_info().get("string", "?")))
	# ① .gdextension 在不在（不在 = 整个 addon 没跟过来）
	#   ★ 这一条**在导出包里也有意义**：.gdextension 是**打进 pck** 的，`res://` 读得到。
	var ext := "res://addons/godotsteam/godotsteam.gdextension"
	var has_ext := FileAccess.file_exists(ext)
	bits.append("gdextension=%s" % ("在" if has_ext else "缺失"))
	# ② 本平台该加载的库 + steam_api64.dll（dependency）—— 位置按运行方式取（见 `_runtime_dll_path`）
	var lib := _runtime_dll_path(_expected_lib_path())
	var has_lib := lib != "" and FileAccess.file_exists(lib)
	bits.append("库=%s" % ("在" if has_lib else ("缺失:%s" % lib if lib != "" else "未知平台")))
	var api := _runtime_dll_path(_expected_api_path())
	var has_api := api != "" and FileAccess.file_exists(api)
	bits.append("steam_api64=%s" % ("在" if has_api else ("缺失:%s" % api if api != "" else "未知平台")))
	# ③ 引擎版本 vs compatibility_minimum
	if has_ext:
		var txt := FileAccess.get_file_as_string(ext)
		var need := _parse_min_version(txt)
		if need != "":
			var cur := str(Engine.get_version_info().get("major", 0)) + "." \
					+ str(Engine.get_version_info().get("minor", 0))
			bits.append("需要≥%s 当前=%s%s" % [need, cur, "" if _ver_ge(cur, need) else "（过低！）"])
	# ④ 导出包里再报一次 exe 目录里的实际文件（布局与 res:// 解析不一致时这一条能立刻看出来）
	if not editor:
		var dir := OS.get_executable_path().get_base_dir()
		var found: Array = []
		for f in DirAccess.get_files_at(dir):
			var lo := str(f).to_lower()
			if lo.contains("godotsteam") or lo == "steam_api64.dll":
				found.append(str(f))
		bits.append("exe 同级 dll=[%s]" % ", ".join(found))
	# ⑤ 处置建议 —— **按运行方式分开给**：导出包里说"把 addons 整目录拷过去"是错的，
	#   那里根本不该有 addons 目录（dll 就该平铺在 exe 旁边）。
	if not has_lib:
		if editor:
			bits.append("⇒ 把 addons/godotsteam 整目录随工程一起拷过去（只拷 .gdextension 不够）")
		else:
			bits.append("⇒ 导出目录缺 %s（重新导出一次；或手工把它拷到 exe 旁边）"
					% (lib.get_file() if lib != "" else "本平台的 godotsteam 库"))
	elif not has_api:
		if editor:
			bits.append("⇒ 导出目录要同时带 steam_api64.dll（GDExtension 的 dependency，缺了扩展不加载）")
		else:
			bits.append("⇒ 导出目录缺 steam_api64.dll（GDExtension 的 dependency，缺了扩展不加载）")
	elif has_lib and has_api and not is_plugin_present():
		bits.append("⇒ 库都在但单例没注册：查引擎版本/库被拦（右键 dll→属性→解除锁定）")
	return "｜".join(bits)


## 本平台 `windows.debug/release.x86_64` 对应的库路径（不在 .gdextension 里硬查；
## 按平台+架构拼，口径与 addons/godotsteam/godotsteam.gdextension 的 [libraries] 一致）。
## ★ 编辑器跑的是 debug 库、导出包跑的是 release 库 —— 两者都可能缺，故两个都列。
func _expected_lib_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	if Engine.get_architecture_name() == "x86_64":
		if OS.has_feature("editor"):
			return "res://addons/godotsteam/win64/libgodotsteam.windows.template_debug.x86_64.dll"
		return "res://addons/godotsteam/win64/libgodotsteam.windows.template_release.x86_64.dll"
	return ""


func _expected_api_path() -> String:
	if OS.get_name() != "Windows":
		return ""
	return "res://addons/godotsteam/win64/steam_api64.dll"


## 从 .gdextension 文本里读 `compatibility_minimum = "4.4"`（读不到返回 ""）。
func _parse_min_version(txt: String) -> String:
	for line in txt.split("\n"):
		var s := str(line).strip_edges()
		if s.begins_with("compatibility_minimum"):
			var i := s.find("\"")
			var j := s.rfind("\"")
			if i >= 0 and j > i:
				return s.substr(i + 1, j - i - 1)
	return ""


## "4.7" >= "4.4" 这类比较（只比主次两位，够用且不依赖 Version 类）。
func _ver_ge(cur: String, need: String) -> bool:
	var a := cur.split(".")
	var b := need.split(".")
	for i in 2:
		var x := int(str(a[i])) if i < a.size() and str(a[i]).is_valid_int() else 0
		var y := int(str(b[i])) if i < b.size() and str(b[i]).is_valid_int() else 0
		if x > y:
			return true
		if x < y:
			return false
	return true


func close_session(remote_id: int) -> void:
	if not is_available():
		return
	_invoke("closeP2PSessionWithUser", [int(remote_id)])


# ------------------------------------------------------------------ 自检

## `--steamtest` 的测试体（触发在 menu.gd，见 GAME/MENU_TESTS 约定）。
## 返回 {"pass": bool, "checks": [[名称, 是否通过, 实测串], ...]}
##
## ★ 判据设计口径：
##   · 每条都要能"红" —— 尤其第 ① ② 组（降级路径），实现里漏一个守卫就会红。
##   · **"环境不可用"与"代码坏"必须分开报**：lobby 端到端依赖真实 Steam 后端与网络，
##     失败时如实报"环境"并**显式写出来**，绝不静默变绿（静默绿是最坏的假通过）。
func run_selftest() -> Dictionary:
	var checks: Array = []

	# ---------- 组① 常量口径：send_type 用错不报错，只会静默发不出去 ----------
	# ★★ **必须双向核对**：既要用对 Steam 那边枚举的值，也要让**本文件的常量**与它一致。
	#    第一版只断言了 Steam 那边的值，本文件常量只在明细里"印了一下"、**没进判据** ——
	#    阴性对照 D4（把常量改成 8）当场证明它**照样绿**。判据自己留洞，等于没测。
	var live_rel := _iconst("P2P_SEND_RELIABLE", -1)
	checks.append(["①a P2P_SEND_RELIABLE｜Steam 实测=2 且本文件常量与之一致",
			live_rel == 2 and P2P_SEND_RELIABLE == live_rel,
			"Steam=%d 本文件常量=%d" % [live_rel, P2P_SEND_RELIABLE]])
	var live_uns := _iconst("P2P_SEND_UNRELIABLE", -1)
	checks.append(["①b P2P_SEND_UNRELIABLE｜Steam 实测=0 且本文件常量与之一致",
			live_uns == 0 and P2P_SEND_UNRELIABLE == live_uns,
			"Steam=%d 本文件常量=%d" % [live_uns, P2P_SEND_UNRELIABLE]])
	var live_to := _iconst("P2P_SESSION_ERROR_TIMEOUT", -1)
	checks.append(["①c P2P_SESSION_ERROR_TIMEOUT=4｜文档口径核对，用于失败诊断",
			live_to == 4, "实测=%d" % live_to])

	# ---------- 组② 降级路径：**本步最关键的不变量** ----------
	# 阳性对照：先证明"没强制缺失时"探测确实能认出插件在（否则下面的 ②b 是空转）
	var present_before := is_plugin_present()
	_force_missing = true
	var safe: Array = []
	safe.append(["is_plugin_present()==false", is_plugin_present() == false])
	safe.append(["is_available()==false", is_available() == false])
	# ⚠️ 顺序要紧：`state()` 只有在 ensure_init() 被拒**之后**才应变成"插件缺失"。
	#    第一次写成先查 state() 后调 ensure_init() ⇒ 永远读到"未初始化" ⇒ 红。
	#    （这是**判据自己**的错，不是代码的错 —— 判据红得有理也要能读懂它红在哪。）
	safe.append(["ensure_init()==false", ensure_init() == false])
	safe.append(["state()==插件缺失", state() == ST_MISSING])
	safe.append(["create_lobby()==false", create_lobby() == false])
	safe.append(["join_lobby(0)==false", join_lobby(0) == false])
	safe.append(["send_message()==false", send_message(12345, {"m": "t"}) == false])
	safe.append(["poll_packets()==0", poll_packets() == 0])
	safe.append(["lobby_member_count()==0", lobby_member_count(0) == 0])
	safe.append(["lobby_members() 空", (lobby_members(0) as Array).is_empty()])
	safe.append(["lobby_owner()==0", lobby_owner(0) == 0])
	safe.append(["lobby_get_data()==\"\"", lobby_get_data(0, "k") == ""])
	safe.append(["request_lobby_list()==false", request_lobby_list() == false])
	safe.append(["my_id()==0", my_id() == 0])
	safe.append(["info() 可读", (info() as Dictionary).has("state")])
	# ★ 2026-10-21 邀请好友：插件缺失时「点邀请」必须安全失败并给理由，
	#   绝不允许静默返回 ok（那会让按钮看起来点上了、实际什么都没发生）。
	var inv: Dictionary = open_invite_dialog()
	safe.append(["open_invite_dialog() ok==false", not bool(inv.get("ok", true))])
	safe.append(["open_invite_dialog() 给了理由", str(inv.get("reason", "")) != ""])
	safe.append(["invite_capability() ok==false", not bool(invite_capability().get("ok", true))])
	# 无副作用原语也不许崩
	leave_lobby(0)
	lobby_set_member_data(0, "k", "v")
	allow_relay(true)
	close_session(0)
	shutdown_steam()
	var bad: Array = []
	for e in safe:
		if not bool(e[1]):
			bad.append(str(e[0]))
	# ★ 判据名里**不许出现全角括号**（用 `｜`）——阴性对照仪靠 `split("（")[0]` 切「哪条红了」，
	#   名字里带全角括号会被切掉尾巴、不以 ✗ 结尾 ⇒ 这条红**读不出来**（判定退化成
	#   "无编号判据红，看结论"，D6/D3 两条对照实测就是这么被吞掉理由的）。
	checks.append(["②a 强制缺失时全部原语安全｜%d 项" % safe.size(),
			bad.is_empty(), "失败项=" + ("无" if bad.is_empty() else ", ".join(bad))])
	# ★ 阳性对照：证明"探测"不是恒 false 的死值
	_force_missing = false
	checks.append(["②b 阳性对照：解除强制后探测恢复｜证明 ②a 不是空转",
			is_plugin_present() == present_before and present_before == true,
			"解除前=%s 解除后=%s" % [present_before, is_plugin_present()]])
	# ③ 未初始化时调用也必须安全（第二条降级路径，与 ②a 不同：这里插件是在的）
	_inited = false
	var pre: Array = []
	pre.append(["send_message()==false", send_message(1, {}) == false])
	pre.append(["create_lobby()==false", create_lobby() == false])
	pre.append(["poll_packets()==0", poll_packets() == 0])
	pre.append(["is_available()==false", is_available() == false])
	var bad2: Array = []
	for e in pre:
		if not bool(e[1]):
			bad2.append(str(e[0]))
	checks.append(["③ 未初始化｜插件在但没 init时原语同样安全",
			bad2.is_empty(), "失败项=" + ("无" if bad2.is_empty() else ", ".join(bad2))])

	# ---------- 组③b 反射守卫本身 ----------
	# ★★ 这条守的是本文件的**立身之本**：`_invoke()` 遇到不存在的方法必须
	#    **返回 null 并让调用方继续往下走**。没有守卫时，Godot 抛的是
	#      `SCRIPT ERROR: Invalid call. Nonexistent function '...' in base 'Steam'.`
	#    它会**中止整个调用函数**（实测把 quit() 也一起带走 ⇒ 进程挂死到被超时杀掉）。
	var probe_ret: Variant = _invoke("thisMethodMustNeverExist_zzz", [])
	checks.append(["③b 反射守卫：不存在的方法返回 null 且不中断调用方",
			probe_ret == null, "返回=%s（非 null 说明守卫被绕开/改成哨兵值了）" % str(probe_ret)])

	# ---------- 组④ 真实初始化事实 ----------
	var ok := ensure_init()
	var inf := info()
	checks.append(["④a ensure_init() 成功", ok, "state=%s reason=%s" % [inf.state, inf.reason]])
	if ok:
		# ④b ★ 与 steam_appid.txt 对账（开发期真实生效的 appid 就该是它）。
		#    文件导不出去（export_filter=all_resources 不含纯文本）⇒ 发行版读不到，此时只要求 >1。
		var aid := int(inf.app_id)
		var file_aid := FileAccess.get_file_as_string("res://steam_appid.txt").strip_edges()
		var b_ok := aid > 1
		var b_note := "appid=%d" % aid
		if file_aid.is_valid_int():
			b_ok = b_ok and aid == int(file_aid)
			b_note += "，steam_appid.txt=%s" % file_aid
		else:
			b_note += "（无 steam_appid.txt，按 Steam 注入）"
		checks.append(["④b appid 有效且与 steam_appid.txt 一致", b_ok, b_note])
		# ④c ★ 用「合法 SteamID64」而不是「>0」—— 后者抓不住 int(true)=1 那类 bug
		var sid := int(inf.steam_id)
		checks.append(["④c steamid 是合法 SteamID64｜≥%d" % STEAM_ID_FLOOR,
				_is_steam_id(sid), "steamid=%d" % sid])
		checks.append(["④d 已登录", bool(inf.logged_on), "logged_on=%s" % str(inf.logged_on)])
		checks.append(["④e 昵称非空", str(inf.persona) != "", "昵称=%s" % str(inf.persona)])
		checks.append(["④f GodotSteam 版本非空｜≥4.20 才支持 Godot 4.7",
				str(inf.godotsteam_version) != "", "版本=%s" % str(inf.godotsteam_version)])
		checks.append(["④g 回调泵已开｜run_callbacks 不崩",
				_invoke("run_callbacks", []) == null, "已在 _process 里每帧泵"])
		# ④h ★ 本层调用的每个 Steam 方法都必须**真实存在**。
		#   为什么这条重要：守卫在方法缺失时会静默返回 null ⇒ 表现是"功能没生效但一条错都不报"。
		#   一旦 GodotSteam 改名/删方法，这条立刻红，而不是让玩家遇到"联机悄悄失灵"。
		# ★★ `getLobbyByIndex` **不在** need 里（2026-10-01 实测后移出）：
		#   GodotSteam 4.22.1 根本不提供它 —— 4.x 的 `lobby_match_list` 回调**直接传 Array**
		#   （lobby id 列表，见 `_on_lobby_match_list()`）。该方法只在 `arg is int` 的
		#   **老版本兼容分支**里由 `_i()` 反射调用一次，缺它属于正常、不是代码坏。
		#   ⇒ 留在 need 里就是"拿老版本的 API 判新版本"⇒ 恒红的假信号（同一个恒真式家族）。
		#   它仍由下面的 ④h2 单独报（存在就报存在、不存在**不算红**）。
		var need: Array = ["steamInit", "isSteamRunning", "run_callbacks", "getAppID",
				"getSteamID", "getPersonaName", "get_godotsteam_version", "loggedOn",
				"createLobby", "joinLobby", "leaveLobby", "getNumLobbyMembers",
				"getLobbyMemberByIndex", "getLobbyOwner", "setLobbyData", "getLobbyData",
				"setLobbyMemberData", "getLobbyMemberData", "sendP2PPacket",
				"readP2PPacket", "getAvailableP2PPacketSize", "acceptP2PSessionWithUser",
				"allowP2PPacketRelay", "closeP2PSessionWithUser", "steamShutdown",
				"requestLobbyList", "addRequestLobbyListStringFilter",
				# 2026-10-21 邀请好友（用户口令）：这三条是本层新增依赖，缺一条
				# "点邀请"就变成静默失效（`_invoke` 守卫生效 ⇒ 返回 null、不报错）。
				"activateGameOverlayInviteDialog", "isOverlayEnabled", "getLaunchCommandLine"]
		var miss: Array = []
		for m in need:
			if not _has_method(str(m)):
				miss.append(str(m))
		checks.append(["④h 本层用到的 %d 个 Steam 方法全部存在" % need.size(),
				miss.is_empty(), "缺失=" + ("无" if miss.is_empty() else ", ".join(miss))])
		# ④h2 老版本兼容分支用的方法：只**报状态**，缺失不算红（理由见上面那段）。
		#   ★ 它守的不是"存在"，而是"有人真的在用它"（对照 `_on_lobby_match_list` 的 int 分支）。
		checks.append(["④h2 老版本兼容方法 getLobbyByIndex 状态已报｜缺失不算红", true,
				"存在=%s（4.x 走 Array 分支，本工程当前版本用不到）" % str(_has_method("getLobbyByIndex"))])
		# ④i 邀请好友的**入站出口**：`join_requested` 信号必须在。
		#   缺它 = 好友接受了邀请、本程序却毫无反应（而邀请方那侧看着"弹窗成功"）—— 静默失效。
		var s_obj := _singleton()
		var has_join_sig: bool = s_obj != null and s_obj.has_signal("join_requested")
		checks.append(["④i join_requested 信号存在｜好友接受邀请的唯一入站出口",
				has_join_sig, "存在=%s" % str(has_join_sig)])
		# ④j 诊断仪器自身的**有效性**：插件在的时候，报告必须显示 "gdextension=在" 且 "库=在"。
		#   ★ 这不是恒真式：`_expected_lib_path()` 的路径拼错 / FileAccess 查不到时，
		#     **本机（插件明明在）也会红** ⇒ 它守的是"第二台机器上看到『库缺失』到底是真缺还是仪器错"。
		#     少了这条，诊断报告本身没有可信度（同 §110：参照物不能和被测量共用退化出口）。
		#   ★ 读 `diag_report()` 而**不是** `missing_diag()`：后者是"失败时给玩家看的"包装，
		#     开头固定顶着「未找到 Steam 单例（addons/godotsteam 未安装？）」——
		#     插件明明在场时把它印进 ✓ 判据的明细里，等于自己打自己（2026-10-21 导出包实测发现）。
		var dg := diag_report()
		checks.append(["④j 诊断仪器：插件在时报告必须显示 gdextension=在 且 库=在｜证明路径映射正确",
				dg.contains("gdextension=在") and dg.contains("库=在"), "报告=%s" % dg])
		# ④j2 路径判定必须**跟着运行方式走**（2026-10-21 导出 demo0.8 时抓到的真 bug）：
		#   旧实现一律用 `res://addons/…`，而导出包里那些 dll **平铺在 exe 同级**、
		#   `FileAccess.file_exists("res://addons/…")` 恒 false ⇒ 对着一个完好的包报
		#   「库=缺失」+ 一句指错方向的处置建议（量具说谎）。
		#   ★ 本条**两个分支各有意义**：编辑器里守"别把它改成恒 exe 同级"（那会让编辑器
		#     诊断失效），导出包里守"别退回 res://"。⇒ 只在编辑器跑是不够的，
		#     真验收要 `瓷砖围棋.exe --headless -- --steamtest`（导出包自己跑一遍）。
		var probe_res := "res://addons/godotsteam/win64/steam_api64.dll"
		var mapped := _runtime_dll_path(probe_res)
		var want_abs: String = OS.get_executable_path().get_base_dir().path_join("steam_api64.dll")
		var editor_now: bool = OS.has_feature("editor")
		var map_ok: bool = (mapped == probe_res) if editor_now else (mapped == want_abs)
		checks.append(["④j2 dll 路径判定跟着运行方式走｜导出包里必须指向 exe 同级，恒返回 res:// 会红",
				map_ok, "运行方式=%s 映射=%s 期望=%s" % [
						"编辑器" if editor_now else "导出包", mapped,
						probe_res if editor_now else want_abs]])
		# ④k 头像（2026-10-21）：真去 Steam 取一张图，真解码成纹理，真量尺寸。
		#   ★ 为什么量尺寸而不是"非 null"：`getImageSize` / `getImageRGBA` 的返回是
		#     Dictionary（实测 `{success, width, height}` / `{success, buffer}`），
		#     少写一层解包就会造出一张 0×0 或半黑的图 —— 那**不是 null**，
		#     只断言"非空"会全绿。中档的权威尺寸是 64×64（小 32 / 大 184）。
		#   ★ 第一次可能拿不到（Steam 还没下载完，handle=0 不报错）⇒ 这里泵几轮回调重试，
		#     与生产路径（`_tick_net_identity` 每 0.5s 一问）同一套语义。
		var av: Texture2D = avatar_texture(_own_id, AVATAR_MEDIUM)
		for _i in range(8):
			if av != null:
				break
			_invoke("run_callbacks", [])
			OS.delay_msec(120)
			av = avatar_texture(_own_id, AVATAR_MEDIUM)
		var av_ok := false
		var av_note := ""
		if av == null:
			av_note = "取不到头像（Steam 未下载完 / 自己没设头像 / 隐私受限）"
		else:
			var s_av := av.get_size()
			av_ok = int(s_av.x) == 64 and int(s_av.y) == 64
			av_note = "尺寸=%d×%d（期望 64×64 = 中档）" % [int(s_av.x), int(s_av.y)]
		checks.append(["④k Steam 头像能取到并解码成纹理｜中档必须量出 64×64，非 null 不够",
				av_ok, av_note])
		# ④k2 昵称（身份条第二行要靠它）。
		#   ★ 与 ④e 拆开：④e 读的是 `ensure_init()` 缓存的 `_persona`，本条读的是
		#     `persona_of()` 这个**查表入口**（自己走缓存、别人问 Steam）。合成一条时，
		#     `persona_of()` 写坏（例如一律返回别人的名字）④e 照样绿。
		var pn_mine := persona_of(_own_id)
		var pn_other := persona_of(0)      # 非法 id：必须安静返回 ""，不许抛
		checks.append(["④k2 昵称查表入口正确｜查自己走缓存非空，非法 id 返回空串",
				pn_mine != "" and pn_other == "",
				"自己=%s 非法id=%s" % [pn_mine, "空" if pn_other == "" else "非空"]])
	else:
		checks.append(["④ 初始化未成功 —— 后续 lobby 判据不可判",
				false, "state=%s reason=%s（属环境问题，非代码）" % [inf.state, inf.reason]])

	# ---------- 组⑤ lobby 端到端（单进程可测：建房 → 读回 → 数据往返 → 退房）----------
	if ok:
		# ★ _selftest_lobby() 里有 await ⇒ 它是**协程**，不 await 拿到的是协程对象而不是数组。
		checks.append_array(await _selftest_lobby())

	# ---------- 组⑥ 元判据：判据自己的形状 ----------
	# ★ 检查的是**本条之前的全部判据**（⑥ 自己不在内 —— 自指无法在同一次求值里完成）。
	#   它自己按同一格式书写，能否被覆盖由「⑥ 变红」这个事实本身兜底。
	# ★ 为什么必须有：`_all_pass()` 的形状守卫能防崩，但只会显示一条**没有名字**的"不通过"，
	#   排查时得从头翻。元判据把"某条写歪了"变成一条带名字的红。
	var shape_bad := _bad_shape(checks)
	checks.append(["⑥ 全部判据元素形状合法｜[名称, bool] / [名称, bool, 明细]",
			shape_bad.is_empty(),
			"畸形项=" + ("无" if shape_bad.is_empty() else ", ".join(shape_bad))])

	return {"pass": _all_pass(checks), "checks": checks}


## 判「全部判据是否都通过」。
## ★★ 必须**先守形状再取值**：判据条约定是 `[名称, 是否通过]` 或 `[名称, 是否通过, 明细]`。
##    一旦手滑写成 `[名称, "明细字符串"]`（漏写判断位），`bool(c[1])` 就会对 **String** 求
##    bool 构造 —— Godot 抛 `SCRIPT ERROR: Nonexistent 'bool' constructor.`，
##    而 SCRIPT ERROR 会**中止整个调用函数**，把调用链上下的 `quit()` 一起带走
##    ⇒ 自检挂死到被 timeout 杀掉（EXIT=124）。实测 2026-09-30（⑤i 那条）。
##    ⇒ 畸形元素一律**判不通过**，绝不崩。写歪了该红，不该死。
func _all_pass(checks: Array) -> bool:
	for c in checks:
		if not (c is Array) or (c as Array).size() < 2:
			return false
		var v: Variant = (c as Array)[1]
		# ★ 注意用 `is bool` 而不是 `bool(...)`：后者正是上面那个崩点。
		if not (v is bool):
			return false
		if not v:
			return false
	return true


## 返回「形状不合法」的判据名清单（空 = 全部合法）。供组⑥元判据用。
## ★ 为什么要有它：`_all_pass()` 的守卫能**防崩**但只会显示一条没名字的"不通过"，
##   不会告诉你**是哪条写歪了**。元判据把"写歪"变成一条**有名字的红**。
func _bad_shape(checks: Array) -> Array:
	var bad: Array = []
	for c in checks:
		if not (c is Array) or (c as Array).size() < 1 or not (c[0] is String):
			bad.append("<非数组或缺名称>")
			continue
		var nm: String = c[0]
		var n: int = (c as Array).size()
		if not (c[0] is String):
			bad.append(nm + "（名称非 String）")
		if n < 2:
			bad.append(nm + "（元素数<2：漏了判断位）")
			continue
		if not ((c as Array)[1] is bool):
			bad.append(nm + "（第 2 位应为 bool，实为 %s）" % type_string(typeof((c as Array)[1])))
		if n > 3:
			bad.append(nm + "（元素数=%d>3）" % n)
		elif n == 3 and not ((c as Array)[2] is String):
			bad.append(nm + "（第 3 位明细应为 String，实为 %s）" % type_string(typeof((c as Array)[2])))
	return bad


## 建房往返。用 await 等 lobby_created 信号（带超时，绝不能挂死）。
func _selftest_lobby() -> Array:
	var out: Array = []
	var got := {"id": 0, "fired": false}

	var cb := func(o: bool, lid: int) -> void:
		got["fired"] = true
		got["id"] = lid if o else 0
	steam_lobby_created.connect(cb)

	var t_public := _iconst("LOBBY_TYPE_PUBLIC", 2)
	var started := create_lobby(t_public, 2)
	# 轮询等回调：Steam 是异步的，但 run_callbacks 在 _process 里泵 ⇒ 必须让出帧
	var waited := 0
	while not bool(got.fired) and waited < 300:
		await get_tree().process_frame
		waited += 1
	steam_lobby_created.disconnect(cb)

	out.append(["⑤a createLobby 已发出", started, "lobby_type=%d" % t_public])
	out.append(["⑤b 收到 lobby_created 回调｜异步路径真的通了",
			bool(got.fired), "等待帧数=%d/300" % waited])
	var lid := int(got.id)
	out.append(["⑤c 拿到有效 lobby_id", lid != 0,
			"lobby_id=%d" % lid + ("" if lid != 0 else "（0=创建失败，属环境/后端问题）")])
	if lid != 0:
		# ★ ⑤c2「当前房间」记录（2026-10-21 邀请好友）：`open_invite_dialog()` 全靠它。
		#   把 `_on_lobby_created` 里那行赋值删掉、或改成写 `GameConfig` ⇒ 本条红。
		#   ⚠️ 不能拿 `lid != 0` 代替：那是**回调参数**，本条读的是**对象自己的状态**
		#     （两者分开正是为了抓"回调收到了但没记下来"——那正是邀请功能会静默失效的那种坏法）。
		out.append(["⑤c2 current_lobby_id 与建房回调一致｜邀请窗口按它弹",
				current_lobby_id() == lid, "记录=%d 回调=%d" % [current_lobby_id(), lid]])
		# ★ ⑤c3 端到端：房建好之后「邀请好友」能力必须为真（warn 允许有，ok 必须真）。
		#   这一条把「建房回调 → _lobby_id → invite_capability」整条链钉在一次断言里 ——
		#   ⑤c2 只证明"记下来了"，本条证明"记下来的东西真的能让按钮变可点"。
		#   ⚠️ 它**不**断言 `warn == ""`：编辑器运行下 `isOverlayEnabled()` 实测为 false
		#     （覆盖层只在 Steam 启动的游戏里注入），那是环境事实，不是代码坏。
		var cap5 := invite_capability()
		out.append(["⑤c3 建房后 invite_capability().ok 为真｜邀请按钮此刻应可点",
				bool(cap5.get("ok", false)),
				"ok=%s reason=%s warn=%s" % [str(cap5.get("ok", false)),
						str(cap5.get("reason", "")), str(cap5.get("warn", ""))]])
		out.append(["⑤d 房内人数 == 1", lobby_member_count(lid) == 1,
				"人数=%d" % lobby_member_count(lid)])
		# ★ ⑤e 必须**同时**要求 my_id() 合法。只判 `owner == my_id()` 是**假阳性陷阱**：
		#   两个值都由同一个坏表达式算出来时，坏得一样就"相等"（实测踩过：房主=1 自己=1 亮绿灯）。
		out.append(["⑤e 房主是自己 且 id 合法 SteamID64",
				_is_steam_id(my_id()) and lobby_owner(lid) == my_id(),
				"房主=%d 自己=%d" % [lobby_owner(lid), my_id()]])
		out.append(["⑤f 成员表含自己 且 id 合法",
				_is_steam_id(my_id()) and (lobby_members(lid) as Array).has(my_id()),
				"成员=%s" % str(lobby_members(lid))])
		# lobby data 往返（这就是第 2 步同步「盘型/种子/执色」要用的通道）
		var wrote := lobby_set_data(lid, "probe_key", "probe_val_42")
		out.append(["⑤g setLobbyData 成功", wrote, "写入=%s" % str(wrote)])
		out.append(["⑤h getLobbyData 往返一致",
				lobby_get_data(lid, "probe_key") == "probe_val_42",
				"读回=%s" % lobby_get_data(lid, "probe_key")])
		leave_lobby(lid)
		# ★★ 这里**必须写满三元组**。曾经写成 `[名称, "人数=…"]`（漏了判断位，第 2 位成了 String）
		#   ⇒ `_all_pass()` 里 `bool(c[1])` 对 String 求 bool 构造 ⇒
		#      `SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor.`
		#   ⇒ SCRIPT ERROR **中止整个调用函数**（`run_selftest` / `_steam_self_test` 一起报废，
		#     连 `quit()` 都没执行到）⇒ 自检挂死到被 timeout 杀掉：EXIT=124、回归要干等 300s。
		#   实测 2026-09-30。判据条 = `[名称, 是否通过, 明细]`，第 2 位**只能是 bool**。
		out.append(["⑤i leaveLobby 已发出｜异步：人数此刻 ≤1，归 0 要等回调",
				lobby_member_count(lid) <= 1,
				"人数=%d" % lobby_member_count(lid)])
		# ★ ⑤j 退房后「当前房间」必须归零（否则下一局开局前点「邀请好友」会把好友
		#   拉进一个已经不存在的房间 —— Steam 不报错、好友干等，典型静默失效）。
		out.append(["⑤j 退房后 current_lobby_id 归零｜防止邀请到已失效的房间",
				current_lobby_id() == 0, "退房后=%d" % current_lobby_id()])
	return out


# ------------------------------------------------------------------ 探测仪器（非判据）

## `--steamp2p`：量清「**同一 Steam 账号 + 同一台机器**能不能自环 P2P」。
##
## ★ 为什么必须先量这个：Step 2（传输层接 P2P）的自检能**做到哪一层**完全取决于它 ——
##   自环通 ⇒ 可以做真·双进程 e2e（自发自收、断言载荷回来）；
##   自环不通 ⇒ 只能测到「发送调用成功」那一层，真联机验证**必须等第二个 Steam 账号
##   或另一台机器**，这一点要如实写进文档，不许假装测过。
##
## ★ 它是**仪器不是判据**：只出数 + 一句结论，不参与 `--steamtest` 的通过/失败。
##   （Steam 的 P2P 通道通常要**两个不同 SteamID** 才建立，所以"不通"大概率是
##     Steam 的平台限制而非本工程代码错 —— 把它写成判据会变成一条永远红的假信号。）
func probe_p2p_self() -> Dictionary:
	var lines: Array = []
	var out := {"lines": lines, "verdict": "未知"}
	if not ensure_init():
		lines.append("环境不可用：state=%s reason=%s" % [state(), reason()])
		out["verdict"] = "环境不可用（需要真实 Steam 客户端）"
		return out

	var my := my_id()
	lines.append("自己 steam_id=%d（合法=%s）" % [my, str(_is_steam_id(my))])

	# ① 把单例上所有 P2P / 会话相关的方法与信号列出来（只印）—— 口径核对用，
	#    避免照着文档猜方法名（本工程的"反射先 has_method"纪律同理）。
	var s := _singleton()
	var meths: Array = []
	var sigs: Array = []
	if s != null:
		for m in s.get_method_list():
			var nm := str(m.get("name", ""))
			var lo := nm.to_lower()
			if lo.contains("p2p") or lo.contains("session"):
				meths.append(nm)
		for sg in s.get_signal_list():
			var n2 := str(sg.get("name", ""))
			var lo2 := n2.to_lower()
			if lo2.contains("p2p") or lo2.contains("session") or lo2.contains("lobby"):
				sigs.append(n2)
	meths.sort()
	sigs.sort()
	lines.append("单例上 P2P/会话 方法 %d 个：%s" % [meths.size(), ", ".join(meths)])
	lines.append("单例上 相关 信号：%s" % ", ".join(sigs))

	# ② 建一个真 lobby（给 P2P 一个真实上下文）
	var got := {"fired": false, "id": 0}
	var cb := func(o: bool, lid: int) -> void:
		got["fired"] = true
		got["id"] = lid if o else 0
	steam_lobby_created.connect(cb)
	create_lobby(_iconst("LOBBY_TYPE_PUBLIC", 2), 2)
	var w := 0
	while not bool(got["fired"]) and w < 300:
		await get_tree().process_frame
		w += 1
	steam_lobby_created.disconnect(cb)
	var lid := int(got["id"])
	lines.append("lobby_id=%d（等待 %d 帧）" % [lid, w])

	# ③ 自环发送：连上请求/收包信号，发给自己，泵帧看有没有回来
	var got_req: Array = []
	var got_pkt: Array = []
	var cb_req := func(remote: int) -> void: got_req.append(remote)
	var cb_pkt := func(remote: int, data: Dictionary) -> void: got_pkt.append([remote, str(data)])
	steam_session_request.connect(cb_req)
	steam_peer_packet.connect(cb_pkt)
	allow_relay(true)

	var sent := send_message(my, {"probe": "self_loop", "n": 7})
	lines.append("sendP2PPacket(发给自己) → 返回 %s" % str(sent))

	var w2 := 0
	var read_total := 0
	var last_sz := -1
	while w2 < 180:
		last_sz = _i("getAvailableP2PPacketSize", [P2P_CHANNEL], -1)
		read_total += poll_packets()
		await get_tree().process_frame
		w2 += 1
	lines.append("泵 %d 帧：收到 session_request=%s｜收到包 %d 条｜readP2PPacket 读到 %d｜末次可读字节=%d" % [
			w2, str(got_req), got_pkt.size(), read_total, last_sz])
	if not got_pkt.is_empty():
		lines.append("回环收到的包内容=%s（来自 id=%d）" % [str(got_pkt[0][1]), int(got_pkt[0][0])])

	steam_session_request.disconnect(cb_req)
	steam_peer_packet.disconnect(cb_pkt)

	# ④ 同一进程再 join 自己建的 lobby —— Steam 同账号能不能在同一个房里算两个成员
	var joined := {"fired": false, "resp": -1}
	var cb2 := func(ok: bool, _lid: int, resp: int) -> void:
		joined["fired"] = true
		joined["resp"] = resp if ok else -resp
	steam_lobby_joined.connect(cb2)
	join_lobby(lid)
	var w3 := 0
	while not bool(joined["fired"]) and w3 < 300:
		await get_tree().process_frame
		w3 += 1
	steam_lobby_joined.disconnect(cb2)
	lines.append("joinLobby(自己建的) → fired=%s resp=%s｜之后成员数=%d（成员表=%s）" % [
			str(joined["fired"]), str(joined["resp"]),
			lobby_member_count(lid), str(lobby_members(lid))])

	# ⑤ 结论
	if not got_pkt.is_empty():
		out["verdict"] = "★ 自环可行：同账号同机 P2P 能回环 ⇒ Step 2 可以做真·双进程 e2e"
	elif sent:
		out["verdict"] = "★ 自环不可行：发送成功但收不到 ⇒ Steam 需要两个不同 SteamID 才建 P2P 通道 ⇒ 真联机验证要等第二个账号/另一台机器"
	else:
		out["verdict"] = "★ 发送调用本身就失败 ⇒ 先查 sendP2PPacket 口径（send_type/参数）再谈别的"

	leave_lobby(lid)
	return out
