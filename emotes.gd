class_name Emotes
extends RefCounted

# 快捷表情：**唯一**的绘制真源（2026-10-21）
# ---------------------------------------------------------------------------
# 为什么是"自绘矢量"而不是图片资源：
#   ① 零资源文件 ⇒ 不进 `.pck`、不用 `.import`、没有 `--headless` 下"图没导入"这一族失效；
#   ② 颜色由调用方传入（`ink` / `accent`）⇒ 12 套主题（宣纸…玄石）下都跟着变，
#      固定配色的 PNG 在浅色主题上会糊成一片；
#   ③ 表情要在**两处**画（HUD 的九宫格按钮里、棋盘上的气泡里）——
#      一套图形两处实现必然漂移，所以这里只有一份 `draw_emote()`。
#
# ★ 纪律：本文件**不许**出现任何具体尺寸（像素值）以外的业务判断。
#   谁是"我的气泡"、谁该淡出、能不能发 —— 全在 `game.gd`，这里只负责"给个圆心和半径，画出来"。
#
# ★★ 为什么它们**不是** emoji 字符：
#   工程正文用的 `body_font()`（见 `GameConfig`）是中文正文字体，**不含**彩色 emoji 字形；
#   写 "🙂" 在 Windows 上可能退到系统 emoji 字体渲成彩色，但：
#     · 导出包/其他机器上字体不一定在 ⇒ **静默变成豆腐块**（`--headless` 下更是量不出来）；
#     · 彩色 emoji 不受主题控制，压在宣纸主题上会跳。
#   ⇒ 全部用几何图元画，看得见的像素就是我们自己画的。

# ★★ 抗锯齿一律关闭（2026-10-21 实测，别"顺手改回来"）：
#   `draw_arc` / `draw_polyline` / `draw_line` 的 `antialiased` 参数**必须是 false**。
#   开着它时 `--emotetest` 退出阶段约 **20% 概率 `0xC0000005` 访问违规**
#   （实测：带抗锯齿 30 次崩 6 次；13 处全关后 12 次 0 崩）。
#   崩溃发生在 `quit()` **之后**的引擎窗口清理阶段（stdout 早已走完、截图也已落盘）
#   ⇒ 任何"看日志有没有 ERROR"的判据都抓不到，只能靠连跑 N 次统计退出码（§17）。
#   代价：50px 尺寸下圆与弧有 1px 锯齿，目检（`--screenshot --shotemote`）可接受。
#   ⚠️ 想恢复抗锯齿：**先**解决那个退出崩溃，再动这里。
#
# ---- 想换成自己画的图片表情包时改哪里 ----
#   只改 `draw_emote()` 一个函数体，例如：
#     var tex: Texture2D = _tex(idx)
#     ci.draw_texture_rect(tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false)
#   其余**零改动**：九宫格按钮、棋盘气泡、联机消息 `{"m":"emote","e":idx}`、
#   自检 ⑨（它只数 `draw` 被调用了几次，不认具体画法）全都不变。
#   `NAMES` 跟着改成新素材的名字即可（自检 ① 只查"非空且互不重名"）。

## 表情总数。★ 这是**唯一**的数量真源：UI 建九宫格、自检数条数、消息校验 idx 都读它。
const COUNT := 8

const NAMES: Array[String] = [
	"微笑", "大笑", "哭", "吃惊", "生气", "疑惑", "比心", "加油",
]

## 气泡 / 九宫格按钮用的字号档（相对半径），给调用方排版参考
const LABEL_BELOW := 0.0     # 占位：名字由调用方自己排版，这里不画文字


static func count() -> int:
	return COUNT


## idx → 中文名。越界返回 ""（**不**报错：网络来的 idx 可能是脏的，越界必须能被安静挡掉）。
static func name_of(idx: int) -> String:
	if idx < 0 or idx >= COUNT:
		return ""
	return NAMES[idx]


## 合法性判据。★ 消息入口必须用它，别自己写 `idx >= 0 and idx < 8`（§111 同一公式只许一处）。
static func is_valid(idx: int) -> bool:
	return idx >= 0 and idx < COUNT


## 把一个表情画在 `ci` 上。只在 `ci` 的 `_draw()` 期间调用（Godot 的绘制 API 契约）。
##   center  圆心（表情的外接圆心，**不含**文字区）
##   r       外接半径（脸/图形的半径上限；描边线宽按它派生，所以传小了会糊）
##   ink     线条色（该底色上的可读文字色）
##   accent  强调色（脸的填充 / 心与星的填充）
static func draw_emote(ci: CanvasItem, idx: int, center: Vector2, r: float,
		ink: Color, accent: Color) -> void:
	if ci == null or r <= 0.0 or not is_valid(idx):
		return
	# 线宽跟半径走：同一份代码在九宫格（r≈18）和大气泡（r≈34）里都成立。
	var lw: float = maxf(1.4, r * 0.075)
	var face_r: float = r * 0.80
	# ★★ 填充色**一律由 `ink` 派生**（不是直接用 `accent`）—— 这是 2026-10-21 目检改的：
	#   本函数不知道底盘是什么颜色，只知道"这块底上该用什么色画线"（= ink）。
	#   第一版拿 `accent` 当脸的填充，在**深色弹窗**（宣纸主题的 dialog panel 是深棕）
	#   上 accent 本身就是深色 ⇒ 脸和底糊成一片，观感变成"只有白线条"。
	#   ink 的 alpha 版本则天然成立：浅底上 ink 深 ⇒ 淡黑脸；深底上 ink 白 ⇒ 淡白脸。
	var face_fill := Color(ink.r, ink.g, ink.b, 0.15)
	# 心 / 星这类"实心图形"给强一点，并把 accent 只当**调味**（混 35%），
	# 不直接用它当主填充 —— 理由同上。
	var emph := ink.lerp(accent, 0.35)
	emph.a = 0.30
	match idx:
		0:
			_face(ci, center, face_r, face_fill, ink, lw)
			_eye_dots(ci, center, face_r, ink, 0.085, 0.32, -0.22)
			# 笑 = U 形：下半圆（y 轴向下 ⇒ 角度 0~PI 是下方）
			ci.draw_arc(center + Vector2(0, face_r * 0.10), face_r * 0.46,
					PI * 0.18, PI * 0.82, 22, ink, lw, false)
		1:
			_face(ci, center, face_r, face_fill, ink, lw)
			# 眼画成 ^ ^（上半圆）
			for sx in [-1.0, 1.0]:
				ci.draw_arc(center + Vector2(sx * face_r * 0.30, -face_r * 0.20),
						face_r * 0.15, PI * 1.12, PI * 1.88, 16, ink, lw, false)
			# 张开的嘴：下半圆填充 + 描边
			var mc: Vector2 = center + Vector2(0, face_r * 0.14)
			var mr: float = face_r * 0.46
			var mouth := PackedVector2Array()
			mouth.append(mc + Vector2(-mr, 0))
			for i in range(15):
				var a: float = PI * float(i) / 14.0
				mouth.append(mc + Vector2(cos(a), sin(a)) * mr)
			ci.draw_colored_polygon(mouth, ink)
		2:
			_face(ci, center, face_r, face_fill, ink, lw)
			_eye_dots(ci, center, face_r, ink, 0.085, 0.30, -0.20)
			# 泪珠：眼下一个小圆 + 一道短水痕
			for sx in [-1.0, 1.0]:
				var tp: Vector2 = center + Vector2(sx * face_r * 0.30, face_r * 0.16)
				ci.draw_circle(tp, face_r * 0.10, ink)
				ci.draw_line(tp + Vector2(0, face_r * 0.14),
						tp + Vector2(0, face_r * 0.40), ink, lw * 0.85, false)
			# 难过的嘴 = ∩ 形（上半圆）
			ci.draw_arc(center + Vector2(0, face_r * 0.44), face_r * 0.34,
					PI * 1.18, PI * 1.82, 20, ink, lw, false)
		3:
			_face(ci, center, face_r, face_fill, ink, lw)
			_eye_dots(ci, center, face_r, ink, 0.13, 0.30, -0.26)
			# 嘴 = 空心小圆（O）
			ci.draw_arc(center + Vector2(0, face_r * 0.40), face_r * 0.18,
					0.0, TAU, 26, ink, lw, false)
		4:
			_face(ci, center, face_r, face_fill, ink, lw)
			_eye_dots(ci, center, face_r, ink, 0.075, 0.30, -0.16)
			# 怒眉：内侧低、外侧高（两条斜线）
			ci.draw_line(center + Vector2(-face_r * 0.52, -face_r * 0.46),
					center + Vector2(-face_r * 0.14, -face_r * 0.30), ink, lw, false)
			ci.draw_line(center + Vector2(face_r * 0.52, -face_r * 0.46),
					center + Vector2(face_r * 0.14, -face_r * 0.30), ink, lw, false)
			ci.draw_arc(center + Vector2(0, face_r * 0.46), face_r * 0.36,
					PI * 1.20, PI * 1.80, 20, ink, lw, false)
		5:
			_face(ci, center, face_r, face_fill, ink, lw)
			# 一高一低的眼（左小右大）+ 歪嘴 + 头顶问号侧的一道弧
			ci.draw_circle(center + Vector2(-face_r * 0.30, -face_r * 0.18), face_r * 0.075, ink)
			ci.draw_circle(center + Vector2(face_r * 0.30, -face_r * 0.10), face_r * 0.105, ink)
			ci.draw_line(center + Vector2(-face_r * 0.26, face_r * 0.42),
					center + Vector2(face_r * 0.22, face_r * 0.30), ink, lw, false)
			# 眉：右边挑起来
			ci.draw_line(center + Vector2(face_r * 0.14, -face_r * 0.48),
					center + Vector2(face_r * 0.50, -face_r * 0.62), ink, lw, false)
		6:
			# 比心：心形多边形（参数方程标准化到 r）
			_heart(ci, center, r * 0.92, emph, ink, lw)
		7:
			# 加油：五角星
			_star(ci, center, r * 0.95, emph, ink, lw)


# ------------------------------------------------------------------ 图元
static func _face(ci: CanvasItem, c: Vector2, fr: float, fill: Color, ink: Color, lw: float) -> void:
	ci.draw_circle(c, fr, fill)
	ci.draw_arc(c, fr, 0.0, TAU, 48, ink, lw, false)


static func _eye_dots(ci: CanvasItem, c: Vector2, fr: float, ink: Color,
		eye_k: float, dx: float, dy: float) -> void:
	ci.draw_circle(c + Vector2(-fr * dx, fr * dy), fr * eye_k, ink)
	ci.draw_circle(c + Vector2(fr * dx, fr * dy), fr * eye_k, ink)


static func _heart(ci: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var pts := PackedVector2Array()
	var n := 48
	# 标准心形参数方程；y 取负是因为屏幕 y 向下（否则心是倒的）
	for i in range(n):
		var t: float = TAU * float(i) / float(n)
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t)
				- 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * (r / 17.0))
	ci.draw_colored_polygon(pts, fill)
	# 闭合描边：把首点追加到末尾再 polyline（`draw_colored_polygon` 不描边）
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, ink, lw, false)


static func _star(ci: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a: float = -PI * 0.5 + PI * float(i) / 5.0
		var rad: float = r if (i % 2) == 0 else r * 0.44
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, ink, lw, false)
