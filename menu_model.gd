class_name MenuModel
extends RefCounted
## 两个菜单共用的**唯一数据层**（桌面密铺菜单 `menu.gd` / 手机菜单 `menu_mobile.gd`）。
##
## ★ 为什么要有这一层（用户 2026-09-23 决定「重写一个 iOS 菜单」时明确要求"抽出共享数据层"）：
##   本项目反复踩过同一个坑 —— **同一件事在两套互不相干的代码里各写一遍，然后同样的 bug 修两遍**：
##     · 两套 ESC 面板配色（`game.gd` 暂停 / `menu.gd` 退出确认）各写一套 → 字色错两回；
##     · `--esctest` 两侧都有判据，但回归清单里只有菜单侧 → 对局侧那条**没有 runner**。
##   菜单里最贵的一次是 2026-09-19 那个 bug：二级行的**标签 / 选中态 / 回调**三处各判一次
##   "这行是大小三档还是种类三档"，结果先建行再切棋盘时，标签换了、回调没换 →
##   「点种类毫无反应」+「其他棋盘的标准/加强被改名」，而且**静默**。
##   那次是把三处统一到 `_is_hat_eff()` 一个判据才修好的（铁律 7）。
##   现在要再加一个菜单 —— 如果两个菜单各写一套槽位语义，那次 bug 会**成对复活**。
##   → 所以「槽位语义 / 选项清单 / 有效选择 / 写 GameConfig」全部收到这里，两个菜单只负责"画"。
##
## ★ 设计口径（刻意选的，别再改回去）：
##   · **纯静态函数**，不持有状态、不引用任何节点。状态仍留在各菜单自己身上
##     （`menu.gd` 有 5000 行、`_sel_board` 被 100+ 处引用，搬状态是高风险无收益的动作；
##      搬"判据"才是真正在消灭分叉）。
##   · 需要状态的函数一律**显式传参**（`hat_eff` / `sel_size` / `sel_hatkind`）——
##     这样"标签用哪个判据、选中态用哪个判据"在**调用点**一眼可见，不可能悄悄各判一套。
##   · 只有一个函数**写** `GameConfig`（`apply_choice_to_config`），与铁律 8「一处写、一处读」一致。

# ---------------- 选项清单（唯一真源） ----------------

## 棋盘清单 = 两个菜单排列选项的顺序（桌面是横排循环行，手机是设置行）。
## **新增棋盘只改这张表**（外加 `game.gd` 的生成分派）。
##  · enabled=true  ：真棋盘，可选中
##  · enabled=false ：**待开发占位**（桌面菜单里画成灰红描边、点了弹「开发中」）。
##    桌面菜单需要它把循环行的周期拉长，否则行里只有 2 项时左右相邻会出现两块同名
##    （"怎么有两个立方体"）。手机菜单**不铺占位项**（竖排列表里没有循环周期问题）。
const BOARD_KINDS: Array = [
	{"label": "彭罗斯", "id": GameConfig.BOARD_PENROSE, "enabled": true},
	{"label": "立方体", "id": GameConfig.BOARD_CUBE, "enabled": true},
	{"label": "筝形", "id": GameConfig.BOARD_KITE, "enabled": true},
	{"label": "雪花", "id": GameConfig.BOARD_SNOWFLAKE, "enabled": true},
	{"label": "爱因斯坦", "id": GameConfig.BOARD_HAT, "enabled": true},
	{"label": "敬请期待①", "id": -1, "enabled": false},
	{"label": "敬请期待②", "id": -1, "enabled": false},
]

## 爱因斯坦的三种瓦片（换的是**瓦片边长** → 直接决定盘面，所以和种子一样属于「盘面参数」，
## 开局时要跟棋盘类型一起推给 GameConfig、也要一起落盘）。
const HAT_KINDS: Array = [
	{"label": "帽子", "id": GameConfig.HAT_HAT},
	{"label": "海龟", "id": GameConfig.HAT_TURTLE},
	{"label": "幽灵", "id": GameConfig.HAT_SPECTRE},
]

## 二级行的"含义"枚举：同一组 3 个槽位承载两种含义。
## ★ 这就是 2026-09-19 那个 bug 的正主 —— 含义必须由**一个判据**现判，标签/选中态/回调共用。
const MEAN_SIZE: int = 0      # 棋盘大小三档（随机/标准/加强；筝形是迷你）
const MEAN_HAT_KIND: int = 1  # 爱因斯坦瓦片种类（帽子/海龟/幽灵）

const SLOT_HAT_FALLBACK: String = "帽子"

# ---------------- 清单查询 ----------------

## 启用中的棋盘（桌面循环行只铺这些；占位项不占槽位）
static func enabled_board_kinds() -> Array:
	var out: Array = []
	for k in BOARD_KINDS:
		if bool(k["enabled"]):
			out.append(k)
	return out


static func board_label(id: int) -> String:
	for k in BOARD_KINDS:
		if int(k["id"]) == id:
			return str(k["label"])
	return ""


## 该棋盘 id 是不是**当前启用**项。旧配置里的 id 可能指向已下线的盘（经典 19×19 于 2026-09-15
## 下线，编号不复用）→ 恢复上一局时靠它整份作废，绝不能去画一个不存在的选项。
static func board_id_valid(id: int) -> bool:
	for k in enabled_board_kinds():
		if int(k["id"]) == id:
			return true
	return false


## 该棋盘是不是走「种类」语义（= 爱因斯坦）
static func is_hat_board(board: int) -> bool:
	return board == GameConfig.BOARD_HAT


## 二级行的三个槽位号（顺序即显示顺序）。两种含义都恰好 3 个槽位 —— 槽位号同时是
## RANDOM/STANDARD/ENHANCED 与三个种类 id。加种类必须同时改这里（`--einsteintest` 有钉子）。
static func slots() -> Array:
	return [GameConfig.RANDOM, GameConfig.STANDARD, GameConfig.ENHANCED]


## 种类 id → 显示名（查不到退回「帽子」，**绝不返回空串** —— 空串会把瓷砖标签清掉）
static func hat_kind_label(id: int) -> String:
	for k in HAT_KINDS:
		if int(k["id"]) == id:
			return str(k["label"])
	return SLOT_HAT_FALLBACK


# ---------------- 槽位语义（标签 / 选中态 / 回调三者的**共同**来源） ----------------

## 第 slot 个槽位此刻是什么含义。★ 这是判据本身，不是"再判一遍"。
static func slot_meaning(hat_eff: bool) -> int:
	return MEAN_HAT_KIND if hat_eff else MEAN_SIZE


## 纯大小档名（不含爱因斯坦分支；手机菜单的「大小」行单独显示用）
static func size_label(slot: int, board: int) -> String:
	match slot:
		GameConfig.RANDOM:
			return "迷你" if board == GameConfig.BOARD_KITE else "随机"
		GameConfig.STANDARD:
			return "标准"
		GameConfig.ENHANCED:
			return "加强"
	return "?"


## 第 slot 个槽位在当前「有效选中棋盘」下的显示名。
## ★ 唯一真源：建项、切棋盘后改写、手机菜单的选项块 —— 都调它。
##   传 `hat_eff` 而不是让函数自己去问某个菜单的状态：这样"标签用哪套语义"在调用点可见。
static func slot_label(slot: int, hat_eff: bool, board: int) -> String:
	if hat_eff:
		return hat_kind_label(slot)
	return size_label(slot, board)


## 第 slot 个槽位的选中态。与 `slot_label` **共用同一个 `hat_eff` 判据**，
## 保证「黑砖」与「标签」永远指同一件事。
static func slot_selected(slot: int, hat_eff: bool, sel_size: int, sel_hatkind: int) -> bool:
	return sel_hatkind == slot if hat_eff else sel_size == slot


## 点击第 slot 个槽位后**应当**落到哪一套状态上：返回 `{"size": n}` 或 `{"hat_kind": n}`。
## ★ 这就是「回调」那一条腿 —— 含义在**点击那一刻**由 `hat_eff` 现判，于是回调与标签结构上
##   不可能打架（2026-09-19 的修复要点）。两个菜单都该用它来决定写哪个状态字段。
static func slot_activation(slot: int, hat_eff: bool) -> Dictionary:
	return {"hat_kind": slot} if hat_eff else {"size": slot}


# ---------------- 有效选择 / 写入 GameConfig ----------------

## 开局与预览**共用的**「有效选择」三元组 `{board, size, hat_kind}`。
## ★ 这是「爱因斯坦一律走随机档」这条规则的**唯一落点**。
##   分头各写一遍就会出现「预览画的是标准盘、点开始却是随机盘」这种鬼状态
##   （本项目在完全同型的地方踩过）。手机菜单的「大小」行在帽子盘下要显示"由棋盘决定"，
##   也必须读这里，不能自己判 `board == HAT`。
static func effective_choice(board: int, sel_size: int, sel_hatkind: int) -> Dictionary:
	var b: int = board
	if b < 0:
		b = GameConfig.BOARD_PENROSE
	return {
		"board": b,
		"size": GameConfig.RANDOM if is_hat_board(b) else sel_size,
		"hat_kind": sel_hatkind,
	}


## **唯一**把选项写进 `GameConfig` 的地方（铁律 8）。`ch` 来自 `effective_choice()`。
## ⚠️ 只管这 3 个字段：「落盘上一局」（`save_last_match`）带难度/对战方式、还带"自动化运行不落盘"
##    的判断，那是菜单自己的事，别塞进来。
static func apply_choice_to_config(ch: Dictionary) -> void:
	GameConfig.board_type = int(ch.get("board", GameConfig.BOARD_PENROSE))
	GameConfig.hat_kind = int(ch.get("hat_kind", GameConfig.HAT_HAT))
	GameConfig.board_size = int(ch.get("size", GameConfig.STANDARD))


## 校验/夹取一份「上一局选项」记录，返回 `{board,size,hat_kind,diff,mode}`；
## **整份作废**（返回空字典）的条件：空记录、或棋盘 id 不是当前启用项。
## 其余字段越界一律夹回合法区间（文件被手改过也不至于崩）。
## ★ 纯函数（不碰任何节点状态）→ 两个菜单的"恢复上一局"共用同一套口径，且能被 headless 自检直接验。
##
## ★★ 对战方式只采纳 本地/人机，**「线上」一律不采纳**。理由不是偷懒，是恢复它有真实副作用：
##   菜单 `_ready()` 见到「线上」就会站到联机入口上（自建时代更硬：真的建房、可能拉起信令服务器；
##   现在是 Steam 建房 / 加入的门槛）。
##   ★ 2026-09-30 §24 第 5 步：原注释还举了一个更硬的例子 ——「随机匹配**选中即进排队队列**」。
##     那个功能（自建撮合）已随自建联机删除，现在只剩上面这一条理由。
##   ⚠️ 这条规则因此**更容易被误删**了（看着好像"没什么大不了"）。别删 ——
##     恢复「线上」会让玩家一进菜单就站在联机入口上，而他上一局只想下盘单机。
static func restore_state(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var bid: int = int(d.get("board", -1))
	if not board_id_valid(bid):
		return {}
	var md: int = int(d.get("mode", GameConfig.LOCAL))
	return {
		"board": bid,
		"size": clampi(int(d.get("size", GameConfig.STANDARD)),
			GameConfig.RANDOM, GameConfig.ENHANCED),
		"hat_kind": clampi(int(d.get("hat_kind", GameConfig.HAT_HAT)),
			GameConfig.HAT_HAT, GameConfig.HAT_SPECTRE),
		"diff": clampi(int(d.get("diff", 1)), 0, 2),
		# ★ 2026-10-13：LUDII 已退役（用户口令「彻底砍掉 Ludii」）⇒ 这里只剩 VS_AI 一个放行项。
		#   仍**不采纳** ONLINE —— 理由见函数头那段（恢复它会让人一进菜单就站在联机入口上）。
		"mode": md if md == GameConfig.VS_AI else GameConfig.LOCAL,
		# ★ 2026-10-15：「测试AI」转正为正式档「疾风」⇒ 它的选中态**跟着持久化**
		#   （否则"选了它、下完棋返回菜单又变回人机"——那不叫正式档）。
		#   夹取 0/1：文件被手改过也不至于崩（与上面 size/hat_kind 同一口径）。
		#   ★★ 2026-10-15b：桌面菜单把「疾风」并列化之后，**文件格式与本节口径都没变** ——
		#     这里仍然只在 `mode` 这一栏收发 LOCAL/VS_AI 两个值（哨兵 100 永远不进文件），
		#     疾风那一档走 `xg`。两个字段**合成 `_sel_mode` 一个状态**的活由菜单侧
		#     （`menu.gd::_apply_last_match`）干，本文件保持与手机菜单/棋谱共用的原样。
		"xg": clampi(int(d.get("xg", 0)), 0, 1),
	}


# ---------------- 显示名（手机菜单的"当前值"要用，桌面菜单也可复用） ----------------

## ⚠️ 这里**只认 `GameConfig` 层的三个 mode 值**（LOCAL/VS_AI/ONLINE）——
##   桌面菜单那个内部哨兵 `MODE_XGAI = 100` **不进这里**（它由 `menu.gd::_mode_label()`
##   在菜单侧就地给名字）。传 100 会落到 `return "?"`：那是**静默**的坏法，
##   2026-10-15b 并列化时 `_restore_last_match()` 的日志差点因此印成"对战方式=?"。
static func mode_label(m: int) -> String:
	match m:
		GameConfig.VS_AI: return "磐石"
		GameConfig.LOCAL: return "本地"
		GameConfig.ONLINE: return "线上"

	return "?"


static func diff_label(d: int) -> String:
	match d:
		0: return "简单"
		1: return "普通"
		2: return "困难"
	return "?"


# ★ 2026-09-30 §24 第 5 步：`netmode_label(n)` 已删除。
#   它服务的「联机方式」那一行（邀请好友 / 随机匹配）在**两个菜单**里都只剩一档 ⇒ 整行移除：
#   桌面上是那一瓣瓷砖，手机上是 `_row_defs` 里的一行。留着一个"只有一种取值"的 label 函数
#   会让 `--mtest` / `--steamuitest` 里出现"对常量做断言"的假判据。


## 手机菜单「大小」行的当前值文案。
## ★ 帽子盘下大小档**没有意义**（一律随机）→ 显示"由棋盘决定"，而不是把那个被忽略的
##   `sel_size` 显示出来让人以为能改。这条与 `effective_choice()` 同源。
static func size_row_value(board: int, sel_size: int) -> String:
	if is_hat_board(board):
		return "由棋盘决定"
	return size_label(sel_size, board)


# ---------------- 外观（主题预设） ----------------
# ★ 主题清单的真源是 `GameConfig.PRESETS`（2026-10-08 起 **12 个单档**；旧版是 14 个 = 7 色系 × 浅/深），
#   这里只做"展示怎么分组"，不复制任何配色，也不自己拼主题名。
#   桌面设置页排成一行（`HFlowContainer` 自动换行）、手机选项层排一节，用的都是同一套分层。
# ★★ 别在这里写死主题个数 —— 个数会随主题表改版变（14 → 12 已经发生过一次）；
#   真源是 `PRESETS.size()`，判据要断"个数对不对"请从 `GameConfig.preset_names().size()` 取。

## 主题分组标签：桌面设置页画在行首一格，手机选项层当**分节标题**。
## ★ 2026-10-08 主题改**单档**（不再分浅/深两版）⇒ 只有一组，标签是**空串**。
##   两处消费方都按「空串 ⇒ 不画标题」处理（桌面 `_build_appearance_group` / 手机 `_show_sheet`）。
## ★ 为什么保留这一层常量而不是删掉：`theme_sections()` 与桌面设置页都靠"分组"决定**排几行**；
##   留着它，将来若要再分组（例如「经典 / 霓虹」）只改这个常量 + `GameConfig.preset_name_groups()`。
##   旧名 `TIER_LABELS_SHORT/FULL` 已删 —— 单档后"tier（深浅）"这个概念不存在了（名字必须跟行为走）。
const GROUP_LABELS: Array[String] = [""]

## 主题清单的分节：[{"tier": 组号, "header": 组标签, "names": [...]}, ...]
## 顺序与 `GameConfig.preset_name_groups()` 一致。
## ★ 键名仍叫 `"tier"` 是**刻意的兼容**：手机选项层与 `--mtest` 判据都按 {header, names} 读，
##   而 "tier" 这个键目前无人读；下一轮若有人要清，请连同两层一起改（别只改这里）。
static func theme_sections() -> Array:
	var out: Array = []
	var groups: Array = GameConfig.preset_name_groups()
	for gi in groups.size():
		var names: Array = groups[gi]
		if names.is_empty():
			continue
		out.append({
			"tier": gi,
			"header": GROUP_LABELS[gi] if gi < GROUP_LABELS.size() else "",
			"names": names,
		})
	return out


## 「主题」行的当前值：当前预设名；配色被改过（不在任何预设里）时显示"自定义"。
## 与桌面设置页的 `matches_preset()` 判据同源（那边是"全部不高亮"，这里是"显示自定义"）。
static func theme_row_value() -> String:
	var m: String = GameConfig.matches_preset()
	return m if m != "" else "自定义"
