class_name BoardPanel
extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## 棋盘「盘」—— 托住棋盘的实体托盘：**几何 + 画法的唯一实现**
## ═══════════════════════════════════════════════════════════════════════════
##
## 用户 2026-10-20 两条口令：
##   ·「给棋盘一个"盘"的效果（图与面共用），记得采用主题色」
##   ·「别忘了同步设置页预览效果」
##
## 为什么要收成一份实现：设置页预览存在的意义就是"**所见即对局所得**"。
## 它跟对局盘各写一套画法，迟早长歪（本工程"两处同口径、只改一处"的坑踩过多次）。
##
## ★ 但**参数不共用**：两个盘尺度差一个数量级（对局盘整宽 ~660px，预览盘只有 ~260px）。
##   直接用绝对像素会把预览的格子吃掉一半 ⇒ pad / 厚度 / 线宽一律由调用方按自己的尺度算好传进来。
## ★ 调用方只有两个：
##     `game.gd::_draw_board_panel()`      —— 对局盘（面模式 + 图模式共用同一个函数）
##     `menu.gd::PreviewBoard._draw()`     —— 设置页预览（五角星形小盘）


## 取「盘」的形状：所有顶点 → **凸包** → 沿法向外扩 `pad`（圆角转折）。
##
## ★ 为什么是凸包，而不是"把原多边形直接外扩"：
##   · 对局盘是车轮形密铺（六瓣），外边界在凹口处**不连成单环**；
##   · 预览盘是**五角星（凹多边形）**，直接外扩只会得到"描粗的星形"，不是托盘。
##   而"盘"在物理上就是**托在底下的容器** ⇒ 凸包把凹口填平，得到的才是盘。
## ★ `JOIN_ROUND`：两个盘的外缘全是尖角，硬转折看起来像"削出来的木片"。
## ★ 早退路径都给全了：点不足 3 个 / 凸包退化 ⇒ 返回空数组，`draw()` 会直接不画。
static func shape(points: PackedVector2Array, pad: float) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() < 3:
		return PackedVector2Array()
	if pad <= 0.5:
		return hull
	var grown: Array = Geometry2D.offset_polygon(hull, pad, Geometry2D.JOIN_ROUND)
	if grown.size() > 0 and (grown[0] as PackedVector2Array).size() >= 3:
		return grown[0]
	return hull


## 画这块盘。三段，**顺序不能换**：
##   ① **厚度** —— 整块下移 `thickness`，用 `face.darkened(0.38)` 铺一层。
##      凸多边形下移后只有**下侧**露出这一条，上方被盘面自己盖住 ⇒ 不需要任何裁剪，
##      这就是 2.5D 板的标准画法（本工程 `_block_side_walls()` 同一个思路）。
##   ② **盘面** —— 颜色由调用方给（对局盘 = 主题棋盘色 × `board_panel_tint`）。
##   ③ **外轮廓** —— 让盘边"收得住"：没有它，深色棋子压在木色盘上会显得没有边界。
##
## ★ 传 `ci`：`draw_*` 系列必须落在**一个正在 `_draw()` 的 CanvasItem 实例**上，
##   静态工具自己没法画。调用方一律传 `self`。
## ★ `poly` 必须闭合吗？不用 —— 这里自己补首点成环（`draw_polyline` 不会自动闭合）。
static func draw(ci: CanvasItem, poly: PackedVector2Array, face: Color,
		thickness: float, edge: Color, edge_w: float) -> void:
	if poly.size() < 3:
		return
	if thickness > 0.5:
		var low := PackedVector2Array()
		for p in poly:
			low.push_back(p + Vector2(0.0, thickness))
		ci.draw_colored_polygon(low, face.darkened(0.38))
	ci.draw_colored_polygon(poly, face)
	var ring := poly.duplicate()
	ring.push_back(poly[0])
	ci.draw_polyline(ring, edge, maxf(edge_w, 1.0), true)


## 画一颗**圆棋子**（圆 + 同色压暗描边）—— 图模式下**对局盘与设置页预览共用**的唯一实现。
##
## ★ 描边不是装饰：圆棋子四周是空的（不像整块染色的瓷砖有格线兜着），
##   白子在浅底上只有亮度差、没有轮廓就只是一片"淡色糊"。
## ★ 描边用**同色压暗**而不是固定的格线色：霓虹 / 赛博那类主题的线是荧光色，套到棋子上会变味。
## ★ 描边 alpha 跟着棋子走（`oc.a = col.a`）：提子渐隐时不许留下一圈"空壳"。
## ★ 与 `_draw_cell()`（面模式：整块菱形染色 + 轮廓）是两套并列的画法，
##   由调用方那一侧分叉 —— 本函数只管"一颗圆棋子长什么样"，不管谁该画。
static func round_stone(ci: CanvasItem, center: Vector2, col: Color, r: float) -> void:
	if r <= 0.5:
		return
	ci.draw_circle(center, r, col)
	var ow: float = maxf(1.6, r * 0.13)
	var oc: Color = col.darkened(0.45)
	oc.a = col.a
	ci.draw_arc(center, maxf(r - ow * 0.5, 0.6), 0.0, TAU, 28, oc, ow, true)
