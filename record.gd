class_name GameRecord
extends RefCounted

## ====== 棋谱数据层（2026-10-02，棋谱阶段①）======
## 规划：工作区 `棋谱与创意工坊_开发规划.md` §阶段① / §4（文件格式）。
## 地基（"同种子必得同一张盘 + 按谱重放回到同一局面"）由 `--replaytest` 钉死，见该文档 §5。
##
## ★★ **为什么是普通脚本而不是第 5 个 Autoload**：
##   棋谱读写只在 `game.gd`（记账/终局）与将来的 `menu.gd`（棋谱库界面）**显式调用处**发生，
##   不需要跨场景常驻的可变状态 ⇒ 进 Autoload 只是多一份全局可变状态（铁律 8的反面）。
##
## ★★ **本文件只管「字典 ⇄ JSON ⇄ 磁盘」，一概不碰棋理**：
##   谁落的子、提了几子、劫点多少、能不能下 —— 全部由 `game.gd` 在**记账点**传进来。
##   这条边界是判据能咬住的前提：`--recordtest` 的"逐手对账"拿谱与**另一条独立记账链**
##   （`game.gd::_hist`，悔棋用的最小信息集）**对拍** —— 两边各自写，才对得出来。
##   若本文件自己也算一遍提子/劫点，那"对拍"就退化成"自己跟自己比"（恒真式）。
##
## **两道落盘闸**（照 `GameConfig.save_record()` / `save_appearance()` 的样板，见铁律 8）：
##   ① **写点唯一入口** = 本文件的 `save()`；索引、目录创建、文件写入全在这里，
##      调用方只管传字典 —— 不散落在各调用处（"两处都记得"不是不变量，本工程的老坑）。
##   ② **自动化运行改道自检盘**：`GameConfig.is_automated_run()` 为真时，
##      `records_dir()` 返回 `user://records_selftest/` ⇒ 跑判据永远不碰玩家的棋谱库。

const FORMAT_VERSION: int = 1
## 生成器指纹（写进每份棋谱）。★ 几何由种子决定**只对同一个游戏版本成立**：
##   将来改了生成器（哪怕只调一个 ε），旧棋谱会重放出不同甚至崩掉的盘 ⇒ 复盘器要按它拒绝加载。
const GAME_BUILD: String = "gen-2026-10-02"

const DIR_RECORDS: String = "user://records"
const DIR_SELFTEST: String = "user://records_selftest"
const INDEX_NAME: String = "index.json"

# ★ 这两个常量与 `game.gd` 的 `enum Stone { EMPTY, BLACK, WHITE }` **各写一份**
#   （本文件不能引用 game.gd 的枚举：game.gd 没有 class_name，引用会成环）。
#   两份实现必须有跨实现对拍 —— `--recordtest` ① 就是那条对拍（铁律 13 ⑧）。
const STONE_BLACK: int = 1
const STONE_WHITE: int = 2

## 终局原因（写进 `result.reason`）
const REASON_SCORE: String = "SCORE"      ## 双方停手 → 面积终局
const REASON_RESIGN: String = "RESIGN"    ## 认输（含 AI 判断大势已去）
const REASON_INTERRUPTED: String = "INTERRUPTED"  ## 未终局就中断（重开/退出）

## ★★ 棋谱**分类**（写进 `kind`，2026-10-22 加）。
##
## 为什么必须有这个字段（而不是从别处推）：
##   `mode` 只有 LOCAL / VS_AI / ONLINE 三个值，**表达不了"两个 AI 互下"**——仪器批量自弈
##   跑出来的谱与玩家自己的对局会挤在同一个列表里。而这两类东西的用途完全不同：
##   前者是**实验证据**（`--liuh2h` / `--xgduel` 那一批），后者是"我那盘棋"。
##   ⇒ 分类必须是**记录自己的一个字段**，不能从 mode 推，也不能按双方名字去认引擎名
##     （§113：凡按名字认东西的，改名之后都会**静默**失效）。★ §120 同族：一个量服务两个
##     语义就得拆开——`mode` 继续回答"怎么下的"，`kind` 单独回答"谁下的"。
##
## ⚠️ **不升 `FORMAT_VERSION`**：本字段是可选的追加项，老谱没有它 ⇒ `_index_entry()` 用默认值
##   `KIND_HUMAN` 兜底（`from_json()` 的版本闸一旦改，老谱会**整批读不出来**，那比分类不准严重得多）。
const KIND_HUMAN: int = 0      ## 玩家参与的对局（单机人机 / 本地双人 / 联机）
const KIND_MACHINE: int = 1    ## AI 对 AI（仪器批量自弈），玩家没参与

## 机器对局的**引擎显示名**。★ 只给「老谱补分类」那一次的迁移用（见 `game.gd::_record_migrate_kind`）：
##   2026-10-22 之前写的谱没有 `kind` 字段，唯一能认出来的线索就是谱头里的双方名。
##   规则**只对"缺 kind 的老谱"生效**，新谱一律由写谱方直接给 `kind` ⇒ 它不会长期承重。
const MACHINE_PLAYER_NAMES: PackedStringArray = ["磐石", "疾风", "流水"]


static func color_tag(color: int) -> String:
	return "B" if color == STONE_BLACK else ("W" if color == STONE_WHITE else "?")


## 造一份新棋谱（**空谱头**，第一手由 `append_move()` 追加）。
## mode / board_type / board_size / komi 直接存**整数值**（与 GameConfig 同源）——
##   另附一份可读名（`mode_name` 等）纯粹给人看，复盘器一律读整数值。
## gen_fp = 生成器指纹（由 game.gd 拼：盘型 + 所有影响几何的参数），
##   seed = `game.gd::_rand_seed`（固定档为 0：固定盘"无种子也确定"）。
static func new_record(mode: int, board_type: int, board_size: int,
		seed: int, komi: int, gen_fp: String, players: Dictionary,
		kind: int = KIND_HUMAN) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"game_build": GAME_BUILD,
		"generator_fingerprint": gen_fp,
		"created_at": Time.get_datetime_string_from_system(),
		"mode": mode,
		# ★ 分类（见 `KIND_HUMAN` / `KIND_MACHINE` 的长注释）。身份字段有三处：这里建档，
		#   `_index_entry()` 投影进索引，`menu.gd::_rec_filtered()` 读它分类 —— 三处同源。
		"kind": kind,
		"board_type": board_type,
		"board_size": board_size,
		"board_seed": seed,
		"komi": komi,
		"players": players.duplicate(),
		# ★ `result` 为 null = 这局还没终局。复盘器看到 null 就知道这是半局（`INTERRUPTED`）。
		"result": null,
		"moves": [] as Array,
		"puzzle": null,
	}


## 追加一手。**只追加，不判断合法性**（合法性由调用方 `place_stone()` 判过了）。
## tile = -1 表示「停一手」（`color` 仍是停手方）。
## ko = **本手落定之后**的劫点（不是本手之前的 —— 那是 `_hist.ko_before` 的口径，别混）。
static func append_move(rec: Dictionary, tile: int, color: int, captures: int, ko: int) -> void:
	if rec.is_empty():
		return
	var moves: Array = rec["moves"]
	moves.append({
		"ply": moves.size() + 1,
		"tile": tile,
		"color": color_tag(color),
		"captures": captures,
		"ko": ko,
	})


## 悔棋同步截断：把谱截回到只剩前 `keep` 手（`keep` <= 当前手数）。
## ★ 为什么必须截：棋谱描述的是**这盘棋实际走的路**。悔棋后重走就是另一条路，
##   不截的话谱会比盘面多出若干手 ⇒ 按谱重放走到末手时盘面与实际终局不符（复盘器会以为
##   玩家悔了棋却仍然存在），而且"谱手数 == 盘面手数"这条最基本的不变量会破。
static func trim_moves(rec: Dictionary, keep: int) -> void:
	if rec.is_empty():
		return
	var moves: Array = rec["moves"]
	var k: int = clampi(keep, 0, moves.size())
	while moves.size() > k:
		moves.pop_back()


## 写终局条目。**幂等**：已写过就不覆盖（终局路径可能被踩两次 ——
##   `_apply_pass()` 里 `passes >= 2` 会调 `_finish_game()`，而联机那侧还有一条平行的路）。
static func finish(rec: Dictionary, reason: String, winner: int,
		score_black: int, score_white: int) -> void:
	if rec.is_empty() or rec.get("result") != null:
		return
	var w := "DRAW"
	if winner == STONE_BLACK:
		w = "BLACK"
	elif winner == STONE_WHITE:
		w = "WHITE"
	rec["result"] = {
		"winner": w,
		"reason": reason,
		"score": [score_black, score_white],
		"plies": (rec["moves"] as Array).size(),
	}


## 标中断（这局没走到终局就被重开/退出）。幂等，且**不会覆盖已写的终局条目**。
static func mark_interrupted(rec: Dictionary) -> void:
	if rec.is_empty() or rec.get("result") != null:
		return
	var moves: Array = rec["moves"]
	if moves.is_empty():
		return          # 空谱不必入库：库里全是 0 手的条目没有意义
	finish(rec, REASON_INTERRUPTED, 0, 0, 0)


## 取 `result` 子字典（类型安全）。★ 供 `game.gd` 的判据与本文件的调用方共用，
##   免得各处都写一遍 `or {}` 然后踩同一个坑（见 `_index_entry` 的注释）。
static func result_of(rec: Dictionary) -> Dictionary:
	var r: Variant = rec.get("result")
	return (r as Dictionary) if typeof(r) == TYPE_DICTIONARY else {}


# ====== 序列化======

static func to_json(rec: Dictionary) -> String:
	return JSON.stringify(rec, "\t")


## JSON → 字典，并做一次**深度规整**。
## ★★ 为什么必须有这一步：`JSON.parse_string()` 把**所有**数字解析成 float。
##   不规整的话 `moves[k].tile` 是 `42.0`，再 `to_json` 写出来就是 `42.0` ——
##   文件体积膨胀、谱面看着像坏了，而且 `board[tile]` 用 float 键去取虽有风险但更坏的是
##   **"读回来再存一遍，文件内容变了"** 这件事会让 `--recordtest` 的往返判据莫名其妙地红。
##   判据③（`to_json(from_json(x)) == to_json(x)`）就是钉这一层的。
static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = _normalize(parsed)
	if int(d.get("format_version", -1)) != FORMAT_VERSION:
		return {}
	return d


static func _normalize(v: Variant) -> Variant:
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		# 只把"恰好是整数"的 float 收回int（`42.0 → 42`），其余（真小数）原样保留
		if f == floor(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if typeof(v) == TYPE_DICTIONARY:
		var out := {}
		for k in (v as Dictionary).keys():
			out[k] = _normalize((v as Dictionary)[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = []
		for e in (v as Array):
			arr.append(_normalize(e))
		return arr
	return v


# ====== SGF 导出（棋谱库「导出 SGF」）======
#
# ★★ 先说清楚它**不是**什么（必须写在代码里，否则下一个人会以为能拿去看棋）：
#   本项目的棋盘是**非规则密铺**（彭罗斯菱形 / 立方体蜂窝 / 筝形三角 / 雪花 A-B / 帽子家族），
#   根本没有 `(列, 行)` 这套网格坐标 ⇒ SGF 的坐标语义在这里**无法表达**。
#   于是着法用**瓦片编号**编码（`_sgf_point()`），它能被本项目的工具读回，
#   但**标准围棋软件打开会看到一堆无意义的坐标**（它们会按 `SZ[]` 去摆）。
#   ⇒ 定位：**归档 / 自有工具互通**，不是"拿去用 Sabaki 复盘"。
#   真要给外部工具，前提是先有一张"瓦片编号 ↔ 外部坐标系"的对照表，那是另一件事。
#
# ★ 为什么做成**纯函数**（`to_sgf(rec) -> String`，不碰文件）：
#   判据才能直接对字符串断言（结构、手数、转义），不必落盘再读回来 ——
#   落盘那一段由 `--grecotest` 的既有往返判据覆盖，两件事分开量（铁律 13）。
#   ★ 也正因为它不碰文件，它**不需要**"自动化运行改道自检盘"那套闸（没有写点）。

## 瓦片编号 → SGF 的"着法值"。SGF 的点值是两字符、每字符 52 个可用值（a-z + A-Z）。
## ⇒ 两位可表示 52×52 = 2704 个位置，够本项目所有盘型（最大盘几百格）。
## ★ 编解码必须是一对（`_sgf_point` / `_sgf_point_decode`），且要有**往返判据**：
##   单看"导出能读"会漏掉"两个不同瓦片编成同一个值"这种静默丢子（本工程同族老坑）。
static func _sgf_char(v: int) -> String:
	var i: int = v % 52
	if i < 26:
		return char(97 + i)          # a-z
	return char(65 + (i - 26))       # A-Z


static func _sgf_char_value(c: String) -> int:
	var o: int = c.unicode_at(0)
	if o >= 97 and o <= 122:
		return o - 97
	if o >= 65 and o <= 90:
		return 26 + (o - 65)
	return -1


## tile < 0（停一手）→ `tt`（SGF 里 pass 的惯用写法）。
static func _sgf_point(tile: int) -> String:
	if tile < 0:
		return "tt"
	return _sgf_char(tile % 52) + _sgf_char(tile / 52)


## 反向解码（**目前只有判据用它**，导出是单向的）。
## ★ 留着它不是"为将来准备"，而是往返判据的另一半：没有它，那条判据就只能是
##   "导出的字符串看着像样"，而那种判据量不到"两个瓦片撞成同一个值"。
static func _sgf_point_decode(s: String) -> int:
	if s == "tt" or s.length() != 2:
		return -1
	return _sgf_char_value(s.substr(0, 1)) + _sgf_char_value(s.substr(1, 1)) * 52


## SGF 属性值转义：`\` 与 `]` 必须转义，否则值里的 `]` 会提前结束该属性
## （而后果不是报错，是**后面整段被当成新属性**，静默错位）。
## ★ 顺序铁律：**先转 `\` 再转 `]`**。反过来的话，第一步产生的 `\]` 会被第二步的
##   转 `\` 再转一遍 ⇒ `\\]` ⇒ 读回时就多了一个反斜杠（值被静默改坏）。
static func _sgf_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("]", "\\]")


## `_sgf_escape` 的**逆**（成对存在，与 `_sgf_point`/`_sgf_point_decode` 同理）。
## 目前只有判据用它；它的价值就是"让转义那条判据有牙齿" ——
## 没有逆函数，能写的判据只剩"输出里有没有反斜杠"（那种判据漏转义也照样绿）。
static func _sgf_unescape(s: String) -> String:
	var out: String = ""
	var i: int = 0
	while i < s.length():
		if s[i] == "\\" and i + 1 < s.length():
			out += s[i + 1]
			i += 2
			continue
		out += s[i]
		i += 1
	return out


## 从一份 SGF 文本里取某个属性的值（**按转义规则扫描**：`\]` 不算结束）。
## ★ 用途：判据要能回答"塞进值里的 `]` 有没有把属性提前截断" ——
##   这必须是"读回文档里的那一项"才算量到，只看导出的字符串里有没有反斜杠是量不到的。
## 取不到返回空串；同一属性出现多次时返回**第一个**。
static func sgf_value(sgf: String, key: String) -> String:
	var tag: String = key + "["
	var at: int = sgf.find(tag)
	if at < 0:
		return ""
	var i: int = at + tag.length()
	var out: String = ""
	while i < sgf.length():
		var c: String = sgf[i]
		if c == "\\" and i + 1 < sgf.length():
			out += c + sgf[i + 1]          # 原样保留转义对，交给 `_sgf_unescape`
			i += 2
			continue
		if c == "]":
			return _sgf_unescape(out)
		out += c
		i += 1
	return _sgf_unescape(out)


static func to_sgf(rec: Dictionary) -> String:
	if rec.is_empty():
		return ""
	var moves: Array = rec.get("moves", [])
	var res: Dictionary = result_of(rec)
	var score: Array = res.get("score", [0, 0])
	var parts: Array[String] = []
	# ---- 根节点：标准属性 + 本项目的**自定义属性**（SGF 规范允许：读不懂的会被忽略）----
	parts.append("GM[1]")                # 1 = Go
	parts.append("FF[4]")                # 文件格式 4
	parts.append("CA[UTF-8]")
	parts.append("AP[瓷砖围棋:%d]" % FORMAT_VERSION)
	# SZ 用**着法里出现过的最大瓦片编号 + 1**（真正的"盘有多大规模"）。
	# ★ 标准软件会拿它当 N×N 网格去摆 ⇒ 摆出来毫无意义 ——
	#   这正是上面那段"它不是什么"说的那件事。
	parts.append("SZ[%d]" % _sgf_tile_bound(moves))
	parts.append("DT[%s]" % _sgf_escape(str(rec.get("created_at", "")).substr(0, 10)))
	# 自定义：盘型 / 种子 / 生成器指纹 / 贴目 / 模式 / 终局
	parts.append("PZ[%d]" % int(rec.get("board_type", 0)))
	parts.append("PS[%d]" % int(rec.get("board_size", 0)))
	parts.append("BS[%d]" % int(rec.get("board_seed", 0)))
	parts.append("KM[%d]" % int(rec.get("komi", 0)))
	parts.append("MD[%d]" % int(rec.get("mode", 0)))
	parts.append("GF[%s]" % _sgf_escape(str(rec.get("generator_fingerprint", ""))))
	if not res.is_empty():
		parts.append("RE[%s]" % _sgf_escape("%s+%s" % [str(res.get("winner", "DRAW")),
			str(res.get("reason", ""))]))
		parts.append("SB[%d]" % (int(score[0]) if score.size() > 0 else 0))
		parts.append("SW[%d]" % (int(score[1]) if score.size() > 1 else 0))
	# 把人话写进注释：拿到文件的人第一眼就该知道坐标不是网格坐标
	parts.append("C[%s]" % _sgf_escape(
		"非规则密铺棋盘（瓦片编号制，非网格坐标）；盘型 %d · 种子 %d · 生成器 %s"
		% [int(rec.get("board_type", 0)), int(rec.get("board_seed", 0)),
			str(rec.get("generator_fingerprint", ""))]))
	var out: String = "(;" + "".join(parts)
	# ---- 着法序列 ----
	for mv in moves:
		var m: Dictionary = mv
		var col: String = "B" if str(m.get("color", "B")) == "B" else "W"
		out += ";%s[%s]" % [col, _sgf_point(int(m.get("tile", -1)))]
	out += ")"
	return out


## SZ 用：着法里出现过的最大瓦片编号 + 1（近似"盘上有多少格"）。
## ★ 为什么不去读盘型表：导出是**纯函数**，不该为了一个显示用数字去碰生成器；
##   而且 SZ 在这里只当"盘规模"的提示，不影响可读回性。
static func _sgf_tile_bound(moves: Array) -> int:
	var mx: int = 0
	for mv in moves:
		mx = maxi(mx, int((mv as Dictionary).get("tile", -1)))
	return mx + 1


# ====== 落盘（两道闸都在这一节）======

## 闸② 的唯一真源：**所有**路径都从这里取，调用方不许自己拼 `user://records`。
static func records_dir() -> String:
	return DIR_SELFTEST if GameConfig.is_automated_run() else DIR_RECORDS


## 写点唯一入口（闸①）：目录创建 + 写文件 + 更新索引，全在这里。
## 返回实际落盘路径；失败返回空串。
static func save(rec: Dictionary) -> String:
	if rec.is_empty():
		return ""
	var id: String = str(rec.get("id", ""))
	if id == "":
		id = make_id(rec)
		rec["id"] = id
	var dir: String = records_dir()
	if not _ensure_dir(dir):
		push_warning("棋谱落盘失败：目录建不出来 %s" % dir)
		return ""
	var path: String = "%s/%s.json" % [dir, id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("棋谱落盘失败：%s（err %d）" % [path, FileAccess.get_open_error()])
		return ""
	f.store_string(to_json(rec))
	f.close()
	_index_upsert(rec, id)
	return path


static func load_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_json(FileAccess.get_file_as_string(path))


static func load_by_id(id: String) -> Dictionary:
	return load_from("%s/%s.json" % [records_dir(), id])


## 棋谱库索引（列表页用；不读全谱，省得几百份谱把内存吃满）。
static func list_index() -> Array:
	var p: String = "%s/%s" % [records_dir(), INDEX_NAME]
	if not FileAccess.file_exists(p):
		return []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(v) != TYPE_ARRAY:
		return []
	return v as Array


static func delete_by_id(id: String) -> bool:
	var p: String = "%s/%s.json" % [records_dir(), id]
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	var idx: Array = list_index()
	var kept: Array = []
	for e in idx:
		if str((e as Dictionary).get("id", "")) != id:
			kept.append(e)
	_write_index(kept)
	return true


# ====== 内部======

static func make_id(rec: Dictionary) -> String:
	var stamp: String = Time.get_datetime_string_from_system() \
		.replace("-", "").replace(":", "").replace("T", "-").replace(" ", "_")
	# ★ 带一段手数/种子尾巴：同一秒内开两局（判据里就是这样连着造局的）不能撞名，
	#   撞名会把前一份**静默覆盖** —— 而覆盖在判据里表现为"两份一样"，看着像通过。
	return "%s_p%d_s%d" % [stamp,
		(rec["moves"] as Array).size(), int(rec.get("board_seed", 0))]


static func _ensure_dir(dir_path: String) -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK


static func _index_entry(rec: Dictionary, id: String) -> Dictionary:
	# ★★ 别写 `rec.get("result") or {}`：GDScript 的 `or` 是**布尔**运算符（永远返回 bool），
	#   `Dictionary or Dictionary` 会把 `{}` 赋给 `var res: Dictionary` 报类型错。
	#   症状不是"崩"，而是**这个函数整个不返回** ⇒ 索引里那条静默缺失（本工程已在三处踩过）。
	var res: Dictionary = {}
	var r: Variant = rec.get("result")
	if typeof(r) == TYPE_DICTIONARY:
		res = r
	var score: Array = res.get("score", [0, 0])
	# ★ 双方名（2026-10-22）：棋谱列表要显示「磐石 vs 疾风」这类**对局双方**，而索引是列表页
	#   唯一的读源（`list_index()` 不读全谱，几百份谱读全谱会吃满内存）。
	#   投影时**只留 black/white 两个字符串**，不让整份 players 字典进索引（索引是摘要）。
	var pl: Dictionary = {}
	var pv: Variant = rec.get("players")
	if typeof(pv) == TYPE_DICTIONARY:
		pl = pv
	return {
		"id": id,
		"created_at": str(rec.get("created_at", "")),
		"mode": int(rec.get("mode", 0)),
		# ★ 缺 `kind` = 2026-10-22 之前写的老谱 ⇒ 一律按「我的对局」算（保守方向：
		#   宁可把老谱留在默认类里，也不要把玩家的对局藏进"机器对局"）。
		"kind": int(rec.get("kind", KIND_HUMAN)),
		"players": {"black": str(pl.get("black", "")), "white": str(pl.get("white", ""))},
		"board_type": int(rec.get("board_type", 0)),
		"board_seed": int(rec.get("board_seed", 0)),
		"komi": int(rec.get("komi", 0)),
		"plies": (rec["moves"] as Array).size(),
		"winner": str(res.get("winner", "")),
		"reason": str(res.get("reason", "")),
		"score_black": int(score[0]) if score.size() > 0 else 0,
		"score_white": int(score[1]) if score.size() > 1 else 0,
	}


static func _index_upsert(rec: Dictionary, id: String) -> void:
	var idx: Array = list_index()
	var kept: Array = []
	var replaced: bool = false
	for e in idx:
		if str((e as Dictionary).get("id", "")) == id:
			kept.append(_index_entry(rec, id))   # 同名覆盖（幂等，不重复追加）
			replaced = true
		else:
			kept.append(e)
	if not replaced:
		kept.append(_index_entry(rec, id))
	_write_index(kept)


static func _write_index(idx: Array) -> void:
	var dir: String = records_dir()
	if not _ensure_dir(dir):
		return
	var f := FileAccess.open("%s/%s" % [dir, INDEX_NAME], FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(idx, "\t"))
	f.close()
