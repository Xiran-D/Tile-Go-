class_name UITheme
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## UI 主题装配（2026-10-13 新增，P0）
## ═══════════════════════════════════════════════════════════════════════════
##
## ## 这一层解决什么
##
## 本工程**原来根本没有 Theme 资源**：`project.godot` 里没有 `[gui]` 段、没有
## `theme/custom`，全工程跑在引擎默认主题上，字体是 `ThemeDB.fallback_font`。
## 后果是 —— 默认字体随 Godot 版本变，界面就跟着变；而且中文在 13–22px 上
## 用引擎兜底字体笔画会糊（`menu_mobile.gd` 的注释里记过实测：标签 12.0pt、
## 内切圆 33.9pt，都低于各自的可读下限）。
##
## ## 为什么不直接写 `ui_theme.tres`
##
## ★ 因为字体是**运行期按子集文件装配**的：字体已按「工程实际用字 ∪ GB2312
##   一级二级汉字」子集化（24.6MB → 3.4MB），子集清单将来可能随文案变化而重跑。
##   用 `.tres` 的话每次改字库都要手改资源引用；用代码则**只有这一处**知道字体是谁。
##
## ## 为什么挂在根 Window 而不是每个场景
##
## Autoload `GameConfig._ready()` 早于任何主场景 `_ready()`，在那里
## `get_tree().root.theme = …` 一行即可全局生效，无需改任何 `.tscn`
## （本工程三个 `.tscn` 都是薄壳，改它们等于改结构 —— 不在视觉重设计范围内）。
##
## ## ★ 字体加载失败必须**静默降级**，不能崩
##
## 新增 `.ttf` 后 Godot 需要在编辑器里生成 `.import`。若有人**从未用编辑器打开过**
## 就直接跑 headless（`--apptest` 等自检就是这么跑的），`load()` 会返回 null。
## 此时的正确行为是**退回引擎默认字体并照常自检**，而不是让整个自检红掉
## —— 否则"字体没导入"会伪装成"配色坏了"，把排查引到完全错误的方向。

const FONT_PROBE_PATHS: Array[String] = [
	UITokens.FONT_DISPLAY,
	UITokens.FONT_BODY,
	UITokens.FONT_MUTED,
]

## 已装配的字体（缓存，避免每处重复 load）。索引与 FONT_PROBE_PATHS 对齐。
static var _display: Font = null
static var _body: Font = null
static var _muted: Font = null
static var _loaded: bool = false

static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var r: Resource = load(path)
	return r as Font

## 载入三款字体（幂等）。任何一款缺失都只是该角色退回 `null`。
static func load_fonts() -> void:
	if _loaded:
		return
	_loaded = true
	_display = _load_font(UITokens.FONT_DISPLAY)
	_body = _load_font(UITokens.FONT_BODY)
	_muted = _load_font(UITokens.FONT_MUTED)

## ★★ 正文字体的**唯一取值入口**（供 `draw_string` 等自绘文字使用）。
##
## ## 为什么必须有这一层（2026-10-15 实测定案）
##
## 本工程主菜单的大部分文字是 `_draw_string` **自绘**的（瓷砖标签、行头、底栏），
## 而自绘拿不到"控件的主题字体" —— 于是原实现到处硬写 `ThemeDB.fallback_font`。
## 后果有两层，都很坏：
##   ① **画**的是引擎兜底黑体，而标题/设置页（原生 Label）**画**的是主题文楷
##      ⇒ 同一个界面两款字体（同一屏里「设置」标题是楷、底栏「设置」是黑，肉眼可见）；
##   ② **判据**（`_nav_label_overlap_count` 等 8 条）与**排版求解**（`_label_fs_fit`
##      决定字号、`_font_h` 决定行高）也读兜底字体 ⇒ 判据量的是 A 字体、画的是 B 字体，
##      于是"改字号会不会叠字"这件事**根本验不出来**（铁律 13 的同型病）。
## ⇒ 绘制与判据**共用这一个入口**，才是"判据读真源"。
##
## ★ 未载入时**必须**返回非 null：`draw_string()` 传 null 会炸，而"字体没导入"按 P0
##   既定口径是**静默降级**（见 `load_fonts()` 上方那段），不给自检制造假红。
static func body_font() -> Font:
	load_fonts()
	return _body if _body != null else ThemeDB.fallback_font

## 展示字体（L1/L2 与标题类自绘文字）。同样保证非 null。
static func display_font() -> Font:
	load_fonts()
	return _display if _display != null else ThemeDB.fallback_font

## 字体是否全部就绪（供自检断言；缺失时**不该**让整套自检红，但要有判据能报出来）。
static func fonts_ready() -> bool:
	load_fonts()
	return _display != null and _body != null and _muted != null

## 字体清单的诊断文本。
static func fonts_report() -> String:
	load_fonts()
	var arr: Array[Font] = [_display, _body, _muted]
	var parts: Array[String] = []
	for i in FONT_PROBE_PATHS.size():
		var f: Font = arr[i]
		parts.append("%s=%s" % [
			FONT_PROBE_PATHS[i].get_file(),
			("OK" if f != null else "缺(退回引擎默认字体)"),
		])
	return "  ".join(parts)

## ★★ 「这个字体是不是我们自己加载的那一款」的**唯一口径**（2026-10-15 补，两处判据共用）。
##
## ## 为什么**不能**拿 `ThemeDB.fallback_font` 当参照（本轮下刀实测踩到，值得记）
## 先写的那版判据是「`font == ThemeDB.fallback_font` ⇒ 算退化」。它**两头都不成立**：
##   · `GameConfig.apply_ui_theme()` 末尾有一句 `ThemeDB.fallback_font = UITheme.body_font()`
##     （次要保险）⇒ 字体**一切正常**时，`font == ThemeDB.fallback_font` 对**每一个**控件
##     都成立 ⇒ **假红**（实测：撤刀后 19/19 全被算成"引擎兜底"）；
##   · 而字体**缺失**时 `body_font()` 返回的也**正是** `ThemeDB.fallback_font` ⇒ 被测物与
##     参照物**同时退化** ⇒ **真红不出来**（补牙前那条判据就是这么恒绿的）。
##   ⇒ 一句话：**当被测物的"退化出口"与判据的"参照物"是同一个对象时，这个比较没有信息量。**
##
## ## 正解：问"它到底从哪个文件来的"
## 我们自己的三款字体一定是 `load("res://art/font/*.ttf")` 来的 ⇒ `resource_path` 必然等于
## 三个 token 路径之一；而引擎内建兜底字体**没有文件**，`resource_path` 是**空串**。
## 这条口径**绕开了 fallback 那个出口**，所以刀下会红、真状态下会绿（两向均已实测）。
static func is_theme_font(f: Font) -> bool:
	if f == null:
		return false
	var p: String = f.resource_path
	return p == UITokens.FONT_DISPLAY or p == UITokens.FONT_BODY or p == UITokens.FONT_MUTED

## 组装主题。★ 这里**只装字体，不装字号**。
##
## ★★ 为什么刻意不设 `default_font_size` / 各类型的 `font_size`（2026-10-13 定稿时改）：
##   ① `--mtest` 的判据 ⑦b 是**阴性对照**：它把行标签的 `font_size` override 整个摘掉，
##      要求此时字号**掉回主题默认**并因此**低于** `TEXT_MIN_PT` 让判据报警。
##      若主题把 Label 默认字号设成 L4（竖屏 32 ≈ 17.5pt），摘掉 override 后仍是 32
##      → 判据照样通过 → ⑦b 报「判据没读控件的实际字号」。
##      ⇒ 那是一条**假失败**，而且它报出来的原因会把我引向完全错误的方向
##      （像是「摘 override」这个测试手法坏了，而不是主题多设了一个字号）。
##   ② 更本质的原因：本工程现有字号**全部**来自显式的 `add_theme_font_size_override`
##      —— 字号是"逐个控件刻意定的"，不是"继承来的"。主题一旦规定默认字号，
##      那些**没有**显式 override 的控件就会**静默**换一个字号。
##      字号该由 `UITokens.fs()` 逐站点显式取值，而不是靠主题兜底 ——
##      后者正是本工程记忆里反复出现的那类"改动看不见后果"。
##   ③ 所以本层的职责边界是：**换字体（可见且全面）**，字号留给 token 逐站点迁移。
##
## ★ 参数 `_portrait` 保留是为了让调用点（`GameConfig.apply_ui_theme()`）在将来字号
##   也收进主题时不必改签名；当前**故意不用**它（理由见上）。
static func build(_portrait: bool) -> Theme:
	load_fonts()
	var th := Theme.new()

	# 默认字体：正文用黑体（晰黑）。展示用衬线（文楷）由 `apply_display_font()`
	# 打在具体控件上 —— 不能把默认字体设成楷体，那会让全界面的小字一起变糊。
	if _body != null:
		th.default_font = _body

	# 常见控件统一绑到同一款正文字体（只绑字体，不绑字号 —— 见上面的定稿理由）。
	if _body != null:
		for t in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton",
				"MenuButton", "LinkButton", "LineEdit", "TextEdit",
				"ItemList", "Tree", "RichTextLabel", "TooltipLabel"]:
			th.set_font("font", t, _body)
	return th

## 把**展示级**字体（楷体）打在某个控件上 —— 用于 L1 展示 / L2 页面标题。
##
## ★ 为什么不把默认字体设成楷体：楷体在 13pt 小字上笔画密度高、辨识度不如黑体，
##   全界面都用会糊。本工程取「标题古典 + 正文清晰」——中文编辑排版的常规做法。
##
## ★ 为什么走 override 而不是改 theme 的类型绑定：展示字体只应出现在**少数几个**
##   控件上（主菜单标题、手机菜单标题、弹窗标题）。逐个 override 是有意为之，
##   它让"哪些控件用展示字体"成为一处**显式可查**的清单，而不是散在主题类型里。
static func apply_display_font(ctrl: Control, portrait: bool) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	load_fonts()
	if _display != null:
		ctrl.add_theme_font_override("font", _display)
	ctrl.add_theme_font_size_override("font_size", UITokens.fs(UITokens.Level.L1, portrait))

## 展示字体的**粗一档**版本，供 L2 页面标题使用（同样是楷体，字号小一号）。
static func apply_page_title_font(ctrl: Control, portrait: bool) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	load_fonts()
	if _display != null:
		ctrl.add_theme_font_override("font", _display)
	ctrl.add_theme_font_size_override("font_size", UITokens.fs(UITokens.Level.L2, portrait))